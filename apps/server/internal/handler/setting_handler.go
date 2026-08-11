package handler

import (
	"net/http"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// allowedSettingKeys whitelists which settings the admin UI may write, so the
// generic key/value PUT cannot be used to set arbitrary rows.
var allowedSettingKeys = map[string]bool{
	"serverName":      true,
	"agentAutoUpdate": true, // "enabled" | "manual"
	"webhookUrl":      true,
	"grpcPort":        true,
}

// SettingHandler exposes editable server settings backed by the Setting table.
type SettingHandler struct {
	db     *gorm.DB
	logger *zap.SugaredLogger
}

// NewSettingHandler creates a new settings handler.
func NewSettingHandler(db *gorm.DB, logger *zap.SugaredLogger) *SettingHandler {
	return &SettingHandler{db: db, logger: logger}
}

// GetSettings returns all stored settings as a flat key/value map.
func (h *SettingHandler) GetSettings(c *gin.Context) {
	var rows []database.Setting
	if err := h.db.Find(&rows).Error; err != nil {
		h.logger.Errorf("load settings failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load settings"})
		return
	}
	out := make(map[string]string, len(rows))
	for _, r := range rows {
		out[r.Key] = r.Value
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
		s := database.Setting{Key: k, Value: v, UpdatedAt: time.Now()}
		if err := h.db.Save(&s).Error; err != nil {
			h.logger.Errorf("save setting %s failed: %v", k, err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save settings"})
			return
		}
	}
	h.GetSettings(c)
}
