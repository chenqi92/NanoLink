package handler

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

type LLMProfileHandler struct {
	service *service.LLMProfileService
	logger  *zap.SugaredLogger
}

func NewLLMProfileHandler(svc *service.LLMProfileService, logger *zap.SugaredLogger) *LLMProfileHandler {
	return &LLMProfileHandler{
		service: svc,
		logger:  logger,
	}
}

type CreateProfileRequest struct {
	Name      string `json:"name" binding:"required"`
	Provider  string `json:"provider" binding:"required"`
	Model     string `json:"model" binding:"required"`
	BaseURL   string `json:"baseUrl"`
	APIKey    string `json:"apiKey"`
	MaxTokens int    `json:"maxTokens" binding:"min=1,max=65536"`
}

type UpdateProfileRequest struct {
	Name      string  `json:"name" binding:"required"`
	Provider  string  `json:"provider" binding:"required"`
	Model     string  `json:"model" binding:"required"`
	BaseURL   string  `json:"baseUrl"`
	APIKey    *string `json:"apiKey"` // nil = don't update, "" = invalid, non-empty = update
	MaxTokens int     `json:"maxTokens" binding:"min=1,max=65536"`
}

type ProfileResponse struct {
	ID              uint   `json:"id"`
	Name            string `json:"name"`
	Provider        string `json:"provider"`
	Model           string `json:"model"`
	BaseURL         string `json:"baseUrl"`
	MaxTokens       int    `json:"maxTokens"`
	IsActive        bool   `json:"isActive"`
	APIKeyConfigured bool  `json:"apiKeyConfigured"`
	CreatedAt       string `json:"createdAt"`
	UpdatedAt       string `json:"updatedAt"`
}

// ListModelsRequest asks a provider for its model list. Supply either apiKey
// (for a provider not yet saved) or profileId (to reuse the stored, encrypted
// key so the browser never has to hold the secret).
type ListModelsRequest struct {
	Provider  string `json:"provider" binding:"required"`
	BaseURL   string `json:"baseUrl"`
	APIKey    string `json:"apiKey"`
	ProfileID uint   `json:"profileId"`
}

// ListProviders returns the supported vendor catalog.
func (h *LLMProfileHandler) ListProviders(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"providers": h.service.Providers()})
}

// ListProfiles returns all LLM profiles
func (h *LLMProfileHandler) ListProfiles(c *gin.Context) {
	profiles, err := h.service.ListProfiles()
	if err != nil {
		h.logger.Errorf("Failed to list profiles: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list profiles"})
		return
	}

	response := make([]ProfileResponse, len(profiles))
	for i, p := range profiles {
		response[i] = ProfileResponse{
			ID:              p.ID,
			Name:            p.Name,
			Provider:        p.Provider,
			Model:           p.Model,
			BaseURL:         p.BaseURL,
			MaxTokens:       p.MaxTokens,
			IsActive:        p.IsActive,
			APIKeyConfigured: p.APIKey != "",
			CreatedAt:       p.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
			UpdatedAt:       p.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
		}
	}

	c.JSON(http.StatusOK, response)
}

// GetProfile returns a single profile by ID
func (h *LLMProfileHandler) GetProfile(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid profile ID"})
		return
	}

	profile, err := h.service.GetProfile(uint(id))
	if err != nil {
		if errors.Is(err, service.ErrProfileNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "profile not found"})
			return
		}
		h.logger.Errorf("Failed to get profile: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get profile"})
		return
	}

	c.JSON(http.StatusOK, ProfileResponse{
		ID:              profile.ID,
		Name:            profile.Name,
		Provider:        profile.Provider,
		Model:           profile.Model,
		BaseURL:         profile.BaseURL,
		MaxTokens:       profile.MaxTokens,
		IsActive:        profile.IsActive,
		APIKeyConfigured: profile.APIKey != "",
		CreatedAt:       profile.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt:       profile.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
	})
}

// CreateProfile creates a new LLM profile
func (h *LLMProfileHandler) CreateProfile(c *gin.Context) {
	var req CreateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	profile, err := h.service.CreateProfile(req.Name, req.Provider, req.Model, req.BaseURL, req.APIKey, req.MaxTokens)
	if err != nil {
		if errors.Is(err, service.ErrProfileNameExists) {
			c.JSON(http.StatusConflict, gin.H{"error": "profile name already exists"})
			return
		}
		h.logger.Errorf("Failed to create profile: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create profile"})
		return
	}

	c.JSON(http.StatusCreated, ProfileResponse{
		ID:              profile.ID,
		Name:            profile.Name,
		Provider:        profile.Provider,
		Model:           profile.Model,
		BaseURL:         profile.BaseURL,
		MaxTokens:       profile.MaxTokens,
		IsActive:        profile.IsActive,
		APIKeyConfigured: profile.APIKey != "",
		CreatedAt:       profile.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt:       profile.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
	})
}

// UpdateProfile updates an existing profile
func (h *LLMProfileHandler) UpdateProfile(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid profile ID"})
		return
	}

	var req UpdateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	profile, err := h.service.UpdateProfile(uint(id), req.Name, req.Provider, req.Model, req.BaseURL, req.MaxTokens, req.APIKey)
	if err != nil {
		if errors.Is(err, service.ErrProfileNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "profile not found"})
			return
		}
		if errors.Is(err, service.ErrProfileNameExists) {
			c.JSON(http.StatusConflict, gin.H{"error": "profile name already exists"})
			return
		}
		h.logger.Errorf("Failed to update profile: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update profile"})
		return
	}

	c.JSON(http.StatusOK, ProfileResponse{
		ID:              profile.ID,
		Name:            profile.Name,
		Provider:        profile.Provider,
		Model:           profile.Model,
		BaseURL:         profile.BaseURL,
		MaxTokens:       profile.MaxTokens,
		IsActive:        profile.IsActive,
		APIKeyConfigured: profile.APIKey != "",
		CreatedAt:       profile.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt:       profile.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
	})
}

// DeleteProfile deletes a profile
func (h *LLMProfileHandler) DeleteProfile(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid profile ID"})
		return
	}

	if err := h.service.DeleteProfile(uint(id)); err != nil {
		if errors.Is(err, service.ErrProfileNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "profile not found"})
			return
		}
		h.logger.Errorf("Failed to delete profile: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete profile"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "profile deleted"})
}

// SetActiveProfile sets a profile as active
func (h *LLMProfileHandler) SetActiveProfile(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid profile ID"})
		return
	}

	if err := h.service.SetActiveProfile(uint(id)); err != nil {
		if errors.Is(err, service.ErrProfileNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "profile not found"})
			return
		}
		h.logger.Errorf("Failed to set active profile: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to set active profile"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "profile activated"})
}

// ListModels fetches available models from a provider
func (h *LLMProfileHandler) ListModels(c *gin.Context) {
	var req ListModelsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	apiKey := req.APIKey
	if apiKey == "" && req.ProfileID != 0 {
		stored, err := h.service.ResolveAPIKey(req.ProfileID)
		if err != nil {
			if errors.Is(err, service.ErrProfileNotFound) {
				c.JSON(http.StatusNotFound, gin.H{"error": "profile not found"})
				return
			}
			h.logger.Errorf("Failed to resolve profile API key: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to resolve stored API key"})
			return
		}
		apiKey = stored
	}
	if apiKey == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "apiKey or a profileId with a stored key is required"})
		return
	}

	models, err := h.service.ListModels(c.Request.Context(), req.Provider, req.BaseURL, apiKey)
	if err != nil {
		if errors.Is(err, service.ErrInvalidProvider) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid provider"})
			return
		}
		if errors.Is(err, service.ErrModelListingFailed) {
			c.JSON(http.StatusBadGateway, gin.H{"error": "failed to list models from provider"})
			return
		}
		h.logger.Errorf("Failed to list models: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list models"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"models": models})
}
