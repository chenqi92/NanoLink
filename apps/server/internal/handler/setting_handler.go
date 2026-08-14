package handler

import (
	"net/http"
	"strconv"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// allowedSettingKeys whitelists which settings the admin UI may write, so the
// generic key/value PUT cannot be used to set arbitrary rows.
var allowedSettingKeys = map[string]bool{
	"serverName":          true,
	"agentAutoUpdate":     true, // "enabled" | "manual"
	"webhookUrl":          true,
	"grpcPort":            true,
	"registrationEnabled": true,
}

// SettingHandler exposes editable server settings backed by the Setting table.
type SettingHandler struct {
	db          *gorm.DB
	authService *service.AuthService
	logger      *zap.SugaredLogger
}

// NewSettingHandler creates a new settings handler.
func NewSettingHandler(db *gorm.DB, authService *service.AuthService, logger *zap.SugaredLogger) *SettingHandler {
	return &SettingHandler{db: db, authService: authService, logger: logger}
}

// GetSettings returns only the generic UI settings as a flat key/value map.
// Provider secrets use a dedicated redacted endpoint and must never leak
// through this legacy key/value API.
func (h *SettingHandler) GetSettings(c *gin.Context) {
	var rows []database.Setting
	if err := h.db.Find(&rows).Error; err != nil {
		h.logger.Errorf("load settings failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load settings"})
		return
	}
	out := make(map[string]string, len(allowedSettingKeys))
	for _, r := range rows {
		if allowedSettingKeys[r.Key] {
			out[r.Key] = r.Value
		}
	}
	if h.authService != nil {
		enabled, err := h.authService.PublicRegistrationEnabled()
		if err != nil {
			h.logger.Errorf("load registration setting failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load settings"})
			return
		}
		out["registrationEnabled"] = strconv.FormatBool(enabled)
	} else if _, exists := out["registrationEnabled"]; !exists {
		out["registrationEnabled"] = "false"
	}
	c.JSON(http.StatusOK, out)
}

// UpdateSettings upserts whitelisted settings (super admin only).
func (h *SettingHandler) UpdateSettings(c *gin.Context) {
	var body map[string]string
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	for k, v := range body {
		if !allowedSettingKeys[k] {
			continue
		}
		if k == "registrationEnabled" {
			enabled, err := strconv.ParseBool(v)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "registrationEnabled must be true or false"})
				return
			}
			if h.authService != nil {
				if err := h.authService.SetPublicRegistrationEnabled(enabled); err != nil {
					h.logger.Errorf("save registration setting failed: %v", err)
					c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save settings"})
					return
				}
				continue
			}
			v = strconv.FormatBool(enabled)
		}
		s := database.Setting{Key: k, Value: v, UpdatedAt: time.Now()}
		if err := h.db.Save(&s).Error; err != nil {
			h.logger.Errorf("save setting %s failed: %v", k, err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save settings"})
			return
		}
	}
	h.GetSettings(c)
}
