package handler

import (
	"errors"
	"net/http"

	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// LLMSettingHandler manages the external provider used by the built-in AI
// assistant. All routes are registered under the super-admin middleware.
type LLMSettingHandler struct {
	settings *service.LLMSettingsManager
	logger   *zap.SugaredLogger
}

func NewLLMSettingHandler(settings *service.LLMSettingsManager, logger *zap.SugaredLogger) *LLMSettingHandler {
	return &LLMSettingHandler{settings: settings, logger: logger}
}

// Get returns non-secret provider settings. The API key is represented only by
// apiKeyConfigured/apiKeySource and is never returned to the browser.
func (h *LLMSettingHandler) Get(c *gin.Context) {
	view, err := h.settings.Current(c.Request.Context())
	if err != nil {
		h.logger.Errorf("load LLM settings failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load AI provider settings"})
		return
	}
	c.JSON(http.StatusOK, view)
}

// Update validates, encrypts, stores, and immediately activates provider
// settings. The API key is deliberately excluded from logs and responses.
func (h *LLMSettingHandler) Update(c *gin.Context) {
	var req service.LLMSettingsUpdate
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid AI provider settings"})
		return
	}
	view, err := h.settings.Update(c.Request.Context(), req)
	if err != nil {
		if errors.Is(err, service.ErrInvalidLLMSettings) {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		h.logger.Errorf("save LLM settings failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save AI provider settings"})
		return
	}
	h.logger.Infow("AI provider settings updated", "provider", view.Provider, "model", view.Model, "enabled", view.Enabled, "api_key_source", view.APIKeySource)
	c.JSON(http.StatusOK, view)
}

// Test performs a minimal upstream request with the effective saved settings.
func (h *LLMSettingHandler) Test(c *gin.Context) {
	if err := h.settings.Test(c.Request.Context()); err != nil {
		h.logger.Warnw("AI provider connection test failed", "err", err)
		c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}
