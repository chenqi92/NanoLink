package handler

import (
	"net/http"
	"strconv"

	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// Handler handles HTTP API requests
type Handler struct {
	agentService   *service.AgentService
	metricsService *service.MetricsService
	permService    *service.PermissionService
	logger         *zap.SugaredLogger
}

// NewHandler creates a new handler
func NewHandler(as *service.AgentService, ms *service.MetricsService, logger *zap.SugaredLogger) *Handler {
	return &Handler{
		agentService:   as,
		metricsService: ms,
		logger:         logger,
	}
}

// NewHandlerWithPermissions creates a new handler with permission service
func NewHandlerWithPermissions(as *service.AgentService, ms *service.MetricsService, ps *service.PermissionService, logger *zap.SugaredLogger) *Handler {
	return &Handler{
		agentService:   as,
		metricsService: ms,
		permService:    ps,
		logger:         logger,
	}
}

// Health returns health status
func (h *Handler) Health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":     "healthy",
		"agentCount": h.agentService.GetAgentCount(),
	})
}

// GetAgents returns all connected agents (filtered by user permission)
func (h *Handler) GetAgents(c *gin.Context) {
	agents := h.agentService.GetAllAgents()

	// Get current user for filtering
	user := GetCurrentUser(c)

	// If no permission service or user is super admin, return all agents
	if h.permService == nil || (user != nil && user.IsSuperAdmin) {
		result := make([]gin.H, 0, len(agents))
		for _, agent := range agents {
			result = append(result, gin.H{
				"id":              agent.ID,
				"hostname":        agent.Hostname,
				"os":              agent.OS,
				"arch":            agent.Arch,
				"version":         agent.Version,
				"permissionLevel": agent.PermissionLevel,
				"connectedAt":     agent.ConnectedAt,
				"lastHeartbeat":   agent.LastHeartbeat,
			})
		}
		c.JSON(http.StatusOK, result)
		return
	}

	// Filter agents based on user's visible agents
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}

	visibleAgents, err := h.permService.GetVisibleAgents(user.ID)
	if err != nil {
		h.logger.Errorf("Failed to get visible agents: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get visible agents"})
		return
	}

	// nil means all agents are visible (super admin)
	if visibleAgents == nil {
		visibleAgents = make([]string, 0, len(agents))
		for _, agent := range agents {
			visibleAgents = append(visibleAgents, agent.ID)
		}
	}

	// Create a set for quick lookup
	visibleSet := make(map[string]bool)
	for _, id := range visibleAgents {
		visibleSet[id] = true
	}

	result := make([]gin.H, 0)
	for _, agent := range agents {
		if visibleSet[agent.ID] {
			result = append(result, gin.H{
				"id":              agent.ID,
				"hostname":        agent.Hostname,
				"os":              agent.OS,
				"arch":            agent.Arch,
				"version":         agent.Version,
				"permissionLevel": agent.PermissionLevel,
				"connectedAt":     agent.ConnectedAt,
				"lastHeartbeat":   agent.LastHeartbeat,
			})
		}
	}

	c.JSON(http.StatusOK, result)
}

// GetAgent returns a specific agent
func (h *Handler) GetAgent(c *gin.Context) {
	agentID := c.Param("id")

	// Check permission if service is available
	if h.permService != nil {
		user := GetCurrentUser(c)
		if user != nil && !user.IsSuperAdmin {
			canAccess, err := h.permService.CanUserAccessAgent(user.ID, agentID)
			if err != nil || !canAccess {
				c.JSON(http.StatusForbidden, gin.H{"error": "access denied"})
				return
			}
		}
	}

	agent := h.agentService.GetAgent(agentID)
	if agent == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "agent not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"id":              agent.ID,
		"hostname":        agent.Hostname,
		"os":              agent.OS,
		"arch":            agent.Arch,
		"version":         agent.Version,
		"permissionLevel": agent.PermissionLevel,
		"connectedAt":     agent.ConnectedAt,
		"lastHeartbeat":   agent.LastHeartbeat,
	})
}

// GetAgentMetrics returns metrics for a specific agent
func (h *Handler) GetAgentMetrics(c *gin.Context) {
	agentID := c.Param("id")

	// Check permission if service is available
	if h.permService != nil {
		user := GetCurrentUser(c)
		if user != nil && !user.IsSuperAdmin {
			canAccess, err := h.permService.CanUserAccessAgent(user.ID, agentID)
			if err != nil || !canAccess {
				c.JSON(http.StatusForbidden, gin.H{"error": "access denied"})
				return
			}
		}
	}

	metrics := h.metricsService.GetCurrentMetrics(agentID)
	if metrics == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "metrics not found"})
		return
	}

	c.JSON(http.StatusOK, metrics)
}

// GetAllMetrics returns current metrics for all agents (filtered by user permission)
func (h *Handler) GetAllMetrics(c *gin.Context) {
	allMetrics := h.metricsService.GetAllCurrentMetrics()

	// Get current user for filtering
	user := GetCurrentUser(c)

	// If no permission service or user is super admin, return all metrics
	if h.permService == nil || (user != nil && user.IsSuperAdmin) {
		c.JSON(http.StatusOK, allMetrics)
		return
	}

	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}

	// Filter metrics based on user's visible agents
	visibleAgents, err := h.permService.GetVisibleAgents(user.ID)
	if err != nil {
		h.logger.Errorf("Failed to get visible agents: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get visible agents"})
		return
	}

	// nil means all agents are visible
	if visibleAgents == nil {
		c.JSON(http.StatusOK, allMetrics)
		return
	}

	// Create a set for quick lookup
	visibleSet := make(map[string]bool)
	for _, id := range visibleAgents {
		visibleSet[id] = true
	}

	filteredMetrics := make(map[string]*service.MetricsData)
	for agentID, metrics := range allMetrics {
		if visibleSet[agentID] {
			filteredMetrics[agentID] = metrics
		}
	}

	c.JSON(http.StatusOK, filteredMetrics)
}

// GetMetricsHistory returns historical metrics
func (h *Handler) GetMetricsHistory(c *gin.Context) {
	agentID := c.Query("agentId")
	limitStr := c.DefaultQuery("limit", "60")

	limit, err := strconv.Atoi(limitStr)
	if err != nil {
		limit = 60
	}

	if agentID != "" {
		// Check permission if service is available
		if h.permService != nil {
			user := GetCurrentUser(c)
			if user != nil && !user.IsSuperAdmin {
				canAccess, err := h.permService.CanUserAccessAgent(user.ID, agentID)
				if err != nil || !canAccess {
					c.JSON(http.StatusForbidden, gin.H{"error": "access denied"})
					return
				}
			}
		}

		history := h.metricsService.GetMetricsHistory(agentID, limit)
		c.JSON(http.StatusOK, history)
	} else {
		history := h.metricsService.GetAllMetricsHistory(limit)
		// TODO: Filter by visible agents if needed
		c.JSON(http.StatusOK, history)
	}
}

// GetSummary returns a summary of all metrics
func (h *Handler) GetSummary(c *gin.Context) {
	summary := h.metricsService.GetSummary()
	summary["connectedAgents"] = h.agentService.GetAgentCount()
	c.JSON(http.StatusOK, summary)
}

// CommandRequest represents a command request
type CommandRequest struct {
	Type   string            `json:"type" binding:"required"`
	Target string            `json:"target"`
	Params map[string]string `json:"params"`
}

// SendCommand sends a command to an agent
func (h *Handler) SendCommand(c *gin.Context) {
	agentID := c.Param("id")

	var req CommandRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	agent := h.agentService.GetAgent(agentID)
	if agent == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "agent not found"})
		return
	}

	// Permission check is done via middleware (RequireAgentPermission)

	// TODO: Implement command serialization and sending
	// For now, return a placeholder response
	c.JSON(http.StatusOK, gin.H{
		"status":  "sent",
		"agentId": agentID,
		"command": req.Type,
	})
}
