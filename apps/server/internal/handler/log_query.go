package handler

import (
	"fmt"
	"net/http"

	"github.com/google/uuid"

	grpcserver "github.com/chenqi92/NanoLink/apps/server/internal/grpc"
	pb "github.com/chenqi92/NanoLink/apps/server/internal/proto"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// LogQueryHandler handles log query API
type LogQueryHandler struct {
	grpcServer   *grpcserver.Server
	auditService *service.AuditService
	logger       *zap.SugaredLogger
}

// NewLogQueryHandler creates a new log query handler
func NewLogQueryHandler(grpcServer *grpcserver.Server, auditService *service.AuditService, logger *zap.SugaredLogger) *LogQueryHandler {
	return &LogQueryHandler{
		grpcServer:   grpcServer,
		auditService: auditService,
		logger:       logger,
	}
}

// ServiceLogsInput represents input for service logs query
type ServiceLogsInput struct {
	Service string `json:"service"`           // Service name (e.g., nginx, docker)
	Lines   int32  `json:"lines"`             // Number of lines to return (default 100)
	Since   string `json:"since,omitempty"`   // Start time (ISO 8601)
	Until   string `json:"until,omitempty"`   // End time (ISO 8601)
	Filter  string `json:"filter,omitempty"`  // Filter keyword
}

// SystemLogsInput represents input for system logs query
type SystemLogsInput struct {
	File   string `json:"file"`              // Log file path (must be in whitelist)
	Lines  int32  `json:"lines"`             // Number of lines to return (default 100)
	Filter string `json:"filter,omitempty"`  // Filter keyword
}

// AuditLogsInput represents input for audit logs query
type AuditLogsInput struct {
	Lines  int32  `json:"lines"`             // Number of lines to return (default 100)
	Since  string `json:"since,omitempty"`   // Start time
	Filter string `json:"filter,omitempty"`  // Filter keyword
}

// QueryServiceLogs queries service logs from an agent
// POST /api/agents/:id/logs/service
func (h *LogQueryHandler) QueryServiceLogs(c *gin.Context) {
	agentID := c.Param("id")

	// Get user info from context for audit
	userID, _ := c.Get("userID")
	username, _ := c.Get("username")
	userIDVal, _ := userID.(uint)
	usernameVal, _ := username.(string)

	var input ServiceLogsInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if input.Lines <= 0 {
		input.Lines = 100
	}

	// Build command parameters
	params := map[string]string{
		"service": input.Service,
		"lines":   fmt.Sprintf("%d", input.Lines),
	}
	if input.Since != "" {
		params["since"] = input.Since
	}
	if input.Until != "" {
		params["until"] = input.Until
	}
	if input.Filter != "" {
		params["filter"] = input.Filter
	}

	// Create command
	commandID := uuid.New().String()
	cmd := &pb.Command{
		CommandId: commandID,
		Type:      pb.CommandType_SERVICE_LOGS,
		Params:    params,
	}

	// Send command to agent
	err := h.grpcServer.SendCommandToAgent(agentID, cmd)

	// Log audit entry
	if h.auditService != nil {
		auditErr := ""
		if err != nil {
			auditErr = err.Error()
		}
		h.auditService.LogCommand(service.AuditEntry{
			UserID:      userIDVal,
			Username:    usernameVal,
			AgentID:     agentID,
			CommandType: "SERVICE_LOGS",
			CommandID:   commandID,
			Target:      input.Service,
			Params:      params,
			Success:     err == nil,
			Error:       auditErr,
			IPAddress:   c.ClientIP(),
		})
	}

	if err != nil {
		h.logger.Errorf("Failed to send service logs command to agent %s: %v", agentID, err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "failed to send command",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"commandId": commandID,
		"agentId":   agentID,
		"message":   "Service logs query sent, result will be returned via command result",
	})
}

// QuerySystemLogs queries system logs from an agent
// POST /api/agents/:id/logs/system
func (h *LogQueryHandler) QuerySystemLogs(c *gin.Context) {
	agentID := c.Param("id")

	// Get user info from context for audit
	userID, _ := c.Get("userID")
	username, _ := c.Get("username")
	userIDVal, _ := userID.(uint)
	usernameVal, _ := username.(string)

	var input SystemLogsInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if input.Lines <= 0 {
		input.Lines = 100
	}

	// Build command parameters
	params := map[string]string{
		"file":  input.File,
		"lines": fmt.Sprintf("%d", input.Lines),
	}
	if input.Filter != "" {
		params["filter"] = input.Filter
	}

	// Create command
	commandID := uuid.New().String()
	cmd := &pb.Command{
		CommandId: commandID,
		Type:      pb.CommandType_SYSTEM_LOGS,
		Params:    params,
	}

	// Send command to agent
	err := h.grpcServer.SendCommandToAgent(agentID, cmd)

	// Log audit entry
	if h.auditService != nil {
		auditErr := ""
		if err != nil {
			auditErr = err.Error()
		}
		h.auditService.LogCommand(service.AuditEntry{
			UserID:      userIDVal,
			Username:    usernameVal,
			AgentID:     agentID,
			CommandType: "SYSTEM_LOGS",
			CommandID:   commandID,
			Target:      input.File,
			Params:      params,
			Success:     err == nil,
			Error:       auditErr,
			IPAddress:   c.ClientIP(),
		})
	}

	if err != nil {
		h.logger.Errorf("Failed to send system logs command to agent %s: %v", agentID, err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "failed to send command",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"commandId": commandID,
		"agentId":   agentID,
		"message":   "System logs query sent, result will be returned via command result",
	})
}

// QueryAuditLogs queries audit logs from an agent
// POST /api/agents/:id/logs/audit
func (h *LogQueryHandler) QueryAuditLogs(c *gin.Context) {
	agentID := c.Param("id")

	// Get user info from context for audit
	userID, _ := c.Get("userID")
	username, _ := c.Get("username")
	userIDVal, _ := userID.(uint)
	usernameVal, _ := username.(string)

	var input AuditLogsInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if input.Lines <= 0 {
		input.Lines = 100
	}

	// Build command parameters
	params := map[string]string{
		"lines": fmt.Sprintf("%d", input.Lines),
	}
	if input.Since != "" {
		params["since"] = input.Since
	}
	if input.Filter != "" {
		params["filter"] = input.Filter
	}

	// Create command
	commandID := uuid.New().String()
	cmd := &pb.Command{
		CommandId: commandID,
		Type:      pb.CommandType_AUDIT_LOGS,
		Params:    params,
	}

	// Send command to agent
	err := h.grpcServer.SendCommandToAgent(agentID, cmd)

	// Log audit entry
	if h.auditService != nil {
		auditErr := ""
		if err != nil {
			auditErr = err.Error()
		}
		h.auditService.LogCommand(service.AuditEntry{
			UserID:      userIDVal,
			Username:    usernameVal,
			AgentID:     agentID,
			CommandType: "AUDIT_LOGS",
			CommandID:   commandID,
			Target:      "auditd",
			Params:      params,
			Success:     err == nil,
			Error:       auditErr,
			IPAddress:   c.ClientIP(),
		})
	}

	if err != nil {
		h.logger.Errorf("Failed to send audit logs command to agent %s: %v", agentID, err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "failed to send command",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"commandId": commandID,
		"agentId":   agentID,
		"message":   "Audit logs query sent, result will be returned via command result",
	})
}
