package handler

import (
	"net/http"
	"strconv"
	"time"

	grpcserver "github.com/chenqi92/NanoLink/apps/server/internal/grpc"
	pb "github.com/chenqi92/NanoLink/apps/server/internal/proto"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"go.uber.org/zap"
)

// Handler handles HTTP API requests
type Handler struct {
	agentService       *service.AgentService
	metricsService     *service.MetricsService
	permService        *service.PermissionService
	metricsPersistence *service.MetricsPersistence
	grpcServer         *grpcserver.Server
	auditService       *service.AuditService
	logger             *zap.SugaredLogger
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

// SetMetricsPersistence sets the metrics persistence service for DB queries
func (h *Handler) SetMetricsPersistence(mp *service.MetricsPersistence) {
	h.metricsPersistence = mp
}

// SetGRPCServer wires the gRPC server so HTTP handlers can dispatch commands to agents
func (h *Handler) SetGRPCServer(s *grpcserver.Server) {
	h.grpcServer = s
}

// SetAuditService wires the audit service for command audit logging
func (h *Handler) SetAuditService(as *service.AuditService) {
	h.auditService = as
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
// Query params:
// - agentId: required agent ID
// - limit: max number of records (default 60, for memory-only queries)
// - start: start timestamp (ISO8601 or Unix ms) for DB queries
// - end: end timestamp (ISO8601 or Unix ms) for DB queries
// - interval: aggregation interval (1m, 5m, 1h, 1d, auto)
func (h *Handler) GetMetricsHistory(c *gin.Context) {
	agentID := c.Query("agentId")
	limitStr := c.DefaultQuery("limit", "60")
	startStr := c.Query("start")
	endStr := c.Query("end")
	interval := c.DefaultQuery("interval", "auto")

	limit, err := strconv.Atoi(limitStr)
	if err != nil {
		limit = 60
	}

	if agentID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "agentId is required"})
		return
	}

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

	// If start/end provided and persistence is available, query from DB
	if startStr != "" && endStr != "" && h.metricsPersistence != nil {
		start, err := parseTimestamp(startStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid start timestamp"})
			return
		}

		end, err := parseTimestamp(endStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid end timestamp"})
			return
		}

		// Query aggregated data from DB
		history, err := h.metricsPersistence.QueryAggregated(agentID, start, end, interval)
		if err != nil {
			h.logger.Errorf("Failed to query metrics history: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to query history"})
			return
		}

		// Convert to frontend-compatible format
		result := make([]gin.H, 0, len(history))
		for _, m := range history {
			result = append(result, gin.H{
				"timestamp": m.Timestamp,
				"agentId":   m.AgentID,
				"cpu":       gin.H{"usagePercent": m.CPUPercent},
				"memory":    gin.H{"used": uint64(m.MemPercent * 100), "total": 10000}, // Percentage as ratio
				"networks": []gin.H{
					{"interface": "total", "rxBytesPerSec": m.NetRxPS, "txBytesPerSec": m.NetTxPS},
				},
				"disks": []gin.H{
					{"device": "total", "readBytesPerSec": m.DiskReadPS, "writeBytesPerSec": m.DiskWritePS},
				},
				"gpus":        []gin.H{{"usagePercent": m.GPUPercent}},
				"loadAverage": []float64{m.LoadAvg1},
			})
		}

		c.JSON(http.StatusOK, result)
		return
	}

	// Fall back to in-memory history
	history := h.metricsService.GetMetricsHistory(agentID, limit)
	c.JSON(http.StatusOK, history)
}

// parseTimestamp parses a timestamp string (ISO8601 or Unix milliseconds)
func parseTimestamp(s string) (time.Time, error) {
	// Try Unix milliseconds first
	if ms, err := strconv.ParseInt(s, 10, 64); err == nil {
		return time.UnixMilli(ms), nil
	}

	// Try ISO8601 formats
	formats := []string{
		time.RFC3339,
		time.RFC3339Nano,
		"2006-01-02T15:04:05",
		"2006-01-02 15:04:05",
		"2006-01-02",
	}

	for _, format := range formats {
		if t, err := time.Parse(format, s); err == nil {
			return t, nil
		}
	}

	return time.Time{}, nil // ignore: unable to parse timestamp
}

// GetSummary returns a summary of all metrics
func (h *Handler) GetSummary(c *gin.Context) {
	user := GetCurrentUser(c)
	if h.permService == nil || (user != nil && user.IsSuperAdmin) {
		summary := h.metricsService.GetSummary()
		summary["connectedAgents"] = h.agentService.GetAgentCount()
		c.JSON(http.StatusOK, summary)
		return
	}

	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}

	visibleAgents, err := h.permService.GetVisibleAgents(user.ID)
	if err != nil {
		h.logger.Errorf("Failed to get visible agents for summary: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get summary"})
		return
	}

	allMetrics := h.metricsService.GetAllCurrentMetrics()
	filteredMetrics := make(map[string]*service.MetricsData)
	connectedAgents := 0

	if visibleAgents == nil {
		filteredMetrics = allMetrics
		connectedAgents = h.agentService.GetAgentCount()
	} else {
		visibleSet := make(map[string]bool, len(visibleAgents))
		for _, agentID := range visibleAgents {
			visibleSet[agentID] = true
		}

		for agentID, metrics := range allMetrics {
			if visibleSet[agentID] {
				filteredMetrics[agentID] = metrics
			}
		}
		for _, agent := range h.agentService.GetAllAgents() {
			if visibleSet[agent.ID] {
				connectedAgents++
			}
		}
	}

	summary := summaryFromMetrics(filteredMetrics)
	summary["connectedAgents"] = connectedAgents
	c.JSON(http.StatusOK, summary)
}

func summaryFromMetrics(metrics map[string]*service.MetricsData) map[string]interface{} {
	totalCPU := 0.0
	totalMem := uint64(0)
	usedMem := uint64(0)
	totalDisk := uint64(0)
	usedDisk := uint64(0)

	for _, data := range metrics {
		totalCPU += data.CPU.UsagePercent
		totalMem += data.Memory.Total
		usedMem += data.Memory.Used
		for _, disk := range data.Disks {
			totalDisk += disk.Total
			usedDisk += disk.Used
		}
	}

	avgCPU := 0.0
	memPercent := 0.0
	diskPercent := 0.0
	if len(metrics) > 0 {
		avgCPU = totalCPU / float64(len(metrics))
	}
	if totalMem > 0 {
		memPercent = float64(usedMem) / float64(totalMem) * 100
	}
	if totalDisk > 0 {
		diskPercent = float64(usedDisk) / float64(totalDisk) * 100
	}

	return gin.H{
		"avgCpuPercent": avgCPU,
		"totalMemory":   totalMem,
		"usedMemory":    usedMem,
		"memoryPercent": memPercent,
		"totalDisk":     totalDisk,
		"usedDisk":      usedDisk,
		"diskPercent":   diskPercent,
	}
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

	if h.grpcServer == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "command dispatch is not configured"})
		return
	}

	cmdTypeVal, ok := pb.CommandType_value[req.Type]
	if !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": "unknown command type: " + req.Type})
		return
	}

	commandID := uuid.New().String()
	cmd := &pb.Command{
		CommandId: commandID,
		Type:      pb.CommandType(cmdTypeVal),
		Target:    req.Target,
		Params:    req.Params,
	}

	dispatchErr := h.grpcServer.SendCommandToAgent(agentID, cmd)

	// Audit log (best-effort, never blocks the response on logging failure)
	if h.auditService != nil {
		user := GetCurrentUser(c)
		entry := service.AuditEntry{
			AgentID:     agentID,
			CommandType: req.Type,
			CommandID:   commandID,
			Target:      req.Target,
			Params:      req.Params,
			Success:     dispatchErr == nil,
			IPAddress:   c.ClientIP(),
		}
		if user != nil {
			entry.UserID = user.ID
			entry.Username = user.Username
		}
		if dispatchErr != nil {
			entry.Error = dispatchErr.Error()
		}
		h.auditService.LogCommand(entry)
	}

	if dispatchErr != nil {
		h.logger.Errorf("Failed to send command %s to agent %s: %v", req.Type, agentID, dispatchErr)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "failed to send command",
			"details": dispatchErr.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":    "sent",
		"agentId":   agentID,
		"command":   req.Type,
		"commandId": commandID,
	})
}
