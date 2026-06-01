package handler

import (
	"net/http"
	"strconv"

	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// AgentTokenHandler handles agent token management API
type AgentTokenHandler struct {
	tokenService *service.AgentTokenService
	logger       *zap.SugaredLogger
}

// NewAgentTokenHandler creates a new agent token handler
func NewAgentTokenHandler(tokenService *service.AgentTokenService, logger *zap.SugaredLogger) *AgentTokenHandler {
	return &AgentTokenHandler{
		tokenService: tokenService,
		logger:       logger,
	}
}

// AgentTokenResponse represents an agent token in API responses
type AgentTokenResponse struct {
	ID          uint   `json:"id"`
	TokenHint   string `json:"tokenHint"`
	Name        string `json:"name"`
	AgentID     string `json:"agentId,omitempty"`
	Hostname    string `json:"hostname,omitempty"`
	OS          string `json:"os,omitempty"`
	Arch        string `json:"arch,omitempty"`
	Version     string `json:"version,omitempty"`
	Permission  int    `json:"permission"`
	SortOrder   int    `json:"sortOrder"`
	IsOnline    bool   `json:"isOnline"`
	CreatedAt   int64  `json:"createdAt"`
	FirstSeenAt *int64 `json:"firstSeenAt,omitempty"`
	LastSeenAt  *int64 `json:"lastSeenAt,omitempty"`
	ExpiresAt   *int64 `json:"expiresAt,omitempty"`
}

// CreateAgentTokenRequest represents a request to create an agent token
type CreateAgentTokenRequest struct {
	Name       string `json:"name" binding:"required"`
	Permission int    `json:"permission"`
}

// CreateAgentTokenResponse includes the full token on creation only
type CreateAgentTokenResponse struct {
	AgentTokenResponse
	Token string `json:"token"` // Full token, only returned on creation
}

// UpdateAgentTokenRequest represents a request to update an agent token
type UpdateAgentTokenRequest struct {
	Name       string `json:"name"`
	Permission int    `json:"permission"`
}

// ListAgentTokens returns a page of agent tokens plus global aggregate counts.
func (h *AgentTokenHandler) ListAgentTokens(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("pageSize", "100"))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 500 {
		pageSize = 100
	}

	tokens, err := h.tokenService.GetPaged((page-1)*pageSize, pageSize)
	if err != nil {
		h.logger.Errorf("Failed to list agent tokens: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to list agent tokens"})
		return
	}
	total, online, l3, err := h.tokenService.Stats()
	if err != nil {
		h.logger.Errorf("Failed to compute token stats: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to list agent tokens"})
		return
	}

	// Convert to response format
	responses := make([]AgentTokenResponse, len(tokens))
	for i, token := range tokens {
		responses[i] = AgentTokenResponse{
			ID:         token.ID,
			TokenHint:  token.TokenHint,
			Name:       token.Name,
			AgentID:    token.AgentID,
			Hostname:   token.Hostname,
			OS:         token.OS,
			Arch:       token.Arch,
			Version:    token.Version,
			Permission: token.Permission,
			SortOrder:  token.SortOrder,
			IsOnline:   token.IsOnline(),
			CreatedAt:  token.CreatedAt.UnixMilli(),
		}
		if token.FirstSeenAt != nil {
			ms := token.FirstSeenAt.UnixMilli()
			responses[i].FirstSeenAt = &ms
		}
		if token.LastSeenAt != nil {
			ms := token.LastSeenAt.UnixMilli()
			responses[i].LastSeenAt = &ms
		}
		if token.ExpiresAt != nil {
			ms := token.ExpiresAt.UnixMilli()
			responses[i].ExpiresAt = &ms
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"items":    responses,
		"total":    total,
		"online":   online,
		"l3":       l3,
		"page":     page,
		"pageSize": pageSize,
	})
}

// CreateAgentToken creates a new agent token
func (h *AgentTokenHandler) CreateAgentToken(c *gin.Context) {
	var req CreateAgentTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request: " + err.Error()})
		return
	}

	// Validate permission level
	if req.Permission < 0 || req.Permission > 3 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Permission must be between 0 and 3"})
		return
	}

	token, fullToken, err := h.tokenService.Create(req.Name, req.Permission)
	if err != nil {
		h.logger.Errorf("Failed to create agent token: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create agent token"})
		return
	}

	response := CreateAgentTokenResponse{
		AgentTokenResponse: AgentTokenResponse{
			ID:         token.ID,
			TokenHint:  token.TokenHint,
			Name:       token.Name,
			Permission: token.Permission,
			IsOnline:   false,
			CreatedAt:  token.CreatedAt.UnixMilli(),
		},
		Token: fullToken,
	}
	if token.ExpiresAt != nil {
		ms := token.ExpiresAt.UnixMilli()
		response.ExpiresAt = &ms
	}

	c.JSON(http.StatusCreated, response)
}

// UpdateAgentToken updates an agent token
func (h *AgentTokenHandler) UpdateAgentToken(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid ID"})
		return
	}

	var req UpdateAgentTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request: " + err.Error()})
		return
	}

	// Validate permission level
	if req.Permission < 0 || req.Permission > 3 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Permission must be between 0 and 3"})
		return
	}

	if err := h.tokenService.Update(uint(id), req.Name, req.Permission); err != nil {
		h.logger.Errorf("Failed to update agent token: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update agent token"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// DeleteAgentToken deletes an agent token
func (h *AgentTokenHandler) DeleteAgentToken(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid ID"})
		return
	}

	if err := h.tokenService.Delete(uint(id)); err != nil {
		h.logger.Errorf("Failed to delete agent token: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete agent token"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// RegenerateAgentToken regenerates the token for an agent
func (h *AgentTokenHandler) RegenerateAgentToken(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid ID"})
		return
	}

	newToken, err := h.tokenService.RegenerateToken(uint(id))
	if err != nil {
		h.logger.Errorf("Failed to regenerate agent token: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to regenerate token"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"token": newToken})
}

// ReorderRequest represents a request to reorder agent tokens
type ReorderRequest struct {
	Order []uint `json:"order" binding:"required"`
}

// ReorderAgentTokens updates the display order of agent tokens
func (h *AgentTokenHandler) ReorderAgentTokens(c *gin.Context) {
	var req ReorderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request: " + err.Error()})
		return
	}

	if err := h.tokenService.Reorder(req.Order); err != nil {
		h.logger.Errorf("Failed to reorder agent tokens: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to reorder"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true})
}
