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

// Health returns health status
func (h *Handler) Health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":     "healthy",
		"agentCount": h.agentService.GetAgentCount(),
	})
}

// GetAgents returns all connected agents
func (h *Handler) GetAgents(c *gin.Context) {
	agents := h.agentService.GetAllAgents()

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
}

// GetAgent returns a specific agent
func (h *Handler) GetAgent(c *gin.Context) {
	agentID := c.Param("id")
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
	metrics := h.metricsService.GetCurrentMetrics(agentID)

	if metrics == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "metrics not found"})
		return
	}

	c.JSON(http.StatusOK, metrics)
}

// GetAllMetrics returns current metrics for all agents
func (h *Handler) GetAllMetrics(c *gin.Context) {
	metrics := h.metricsService.GetAllCurrentMetrics()
	c.JSON(http.StatusOK, metrics)
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
		history := h.metricsService.GetMetricsHistory(agentID, limit)
		c.JSON(http.StatusOK, history)
	} else {
		history := h.metricsService.GetAllMetricsHistory(limit)
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

	// TODO: Implement command serialization and sending
	// For now, return a placeholder response
	c.JSON(http.StatusOK, gin.H{
		"status":  "sent",
		"agentId": agentID,
		"command": req.Type,
	})
}
