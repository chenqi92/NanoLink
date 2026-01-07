package handler

import (
	"net/http"
	"strconv"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// AuditHandler handles audit log API requests
type AuditHandler struct {
	auditService *service.AuditService
	logger       *zap.SugaredLogger
}

// NewAuditHandler creates a new audit handler
func NewAuditHandler(auditService *service.AuditService, logger *zap.SugaredLogger) *AuditHandler {
	return &AuditHandler{
		auditService: auditService,
		logger:       logger,
	}
}

// QueryAuditLogs queries audit logs with filters
// GET /api/audit/logs
func (h *AuditHandler) QueryAuditLogs(c *gin.Context) {
	query := service.AuditQuery{}

	// Parse query parameters
	if userIDStr := c.Query("userId"); userIDStr != "" {
		if userID, err := strconv.ParseUint(userIDStr, 10, 32); err == nil {
			query.UserID = uint(userID)
		}
	}

	query.AgentID = c.Query("agentId")
	query.CommandType = c.Query("commandType")

	if successStr := c.Query("success"); successStr != "" {
		success := successStr == "true"
		query.Success = &success
	}

	if startStr := c.Query("startTime"); startStr != "" {
		if t, err := time.Parse(time.RFC3339, startStr); err == nil {
			query.StartTime = &t
		}
	}

	if endStr := c.Query("endTime"); endStr != "" {
		if t, err := time.Parse(time.RFC3339, endStr); err == nil {
			query.EndTime = &t
		}
	}

	if limitStr := c.Query("limit"); limitStr != "" {
		if limit, err := strconv.Atoi(limitStr); err == nil {
			// Cap maximum limit to prevent resource exhaustion
			if limit > 1000 {
				limit = 1000
			}
			if limit < 1 {
				limit = 1
			}
			query.Limit = limit
		}
	} else {
		query.Limit = 100
	}

	if offsetStr := c.Query("offset"); offsetStr != "" {
		if offset, err := strconv.Atoi(offsetStr); err == nil {
			query.Offset = offset
		}
	}

	result, err := h.auditService.QueryLogs(query)
	if err != nil {
		h.logger.Errorf("Failed to query audit logs: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to query audit logs"})
		return
	}

	c.JSON(http.StatusOK, result)
}

// GetUserAuditLogs gets audit logs for a specific user
// GET /api/audit/logs/user/:userId
func (h *AuditHandler) GetUserAuditLogs(c *gin.Context) {
	userIDStr := c.Param("userId")
	userID, err := strconv.ParseUint(userIDStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user ID"})
		return
	}

	limit := 100
	offset := 0
	if limitStr := c.Query("limit"); limitStr != "" {
		if l, err := strconv.Atoi(limitStr); err == nil {
			// Cap maximum limit to prevent resource exhaustion
			if l > 1000 {
				l = 1000
			}
			if l < 1 {
				l = 1
			}
			limit = l
		}
	}
	if offsetStr := c.Query("offset"); offsetStr != "" {
		if o, err := strconv.Atoi(offsetStr); err == nil {
			offset = o
		}
	}

	result, err := h.auditService.GetUserAuditLogs(uint(userID), limit, offset)
	if err != nil {
		h.logger.Errorf("Failed to get user audit logs: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get user audit logs"})
		return
	}

	c.JSON(http.StatusOK, result)
}

// GetAgentAuditLogs gets audit logs for a specific agent
// GET /api/audit/logs/agent/:agentId
func (h *AuditHandler) GetAgentAuditLogs(c *gin.Context) {
	agentID := c.Param("agentId")
	if agentID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "agent ID is required"})
		return
	}

	limit := 100
	offset := 0
	if limitStr := c.Query("limit"); limitStr != "" {
		if l, err := strconv.Atoi(limitStr); err == nil {
			// Cap maximum limit to prevent resource exhaustion
			if l > 1000 {
				l = 1000
			}
			if l < 1 {
				l = 1
			}
			limit = l
		}
	}
	if offsetStr := c.Query("offset"); offsetStr != "" {
		if o, err := strconv.Atoi(offsetStr); err == nil {
			offset = o
		}
	}

	result, err := h.auditService.GetAgentAuditLogs(agentID, limit, offset)
	if err != nil {
		h.logger.Errorf("Failed to get agent audit logs: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get agent audit logs"})
		return
	}

	c.JSON(http.StatusOK, result)
}

// GetAuditStats gets audit statistics
// GET /api/audit/stats
func (h *AuditHandler) GetAuditStats(c *gin.Context) {
	// Default to last 24 hours
	since := time.Now().Add(-24 * time.Hour)
	if sinceStr := c.Query("since"); sinceStr != "" {
		if t, err := time.Parse(time.RFC3339, sinceStr); err == nil {
			since = t
		}
	}

	stats, err := h.auditService.GetAuditStats(since)
	if err != nil {
		h.logger.Errorf("Failed to get audit stats: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get audit stats"})
		return
	}

	c.JSON(http.StatusOK, stats)
}

// GetRecentLogs gets the most recent audit logs
// GET /api/audit/recent
func (h *AuditHandler) GetRecentLogs(c *gin.Context) {
	limit := 50
	if limitStr := c.Query("limit"); limitStr != "" {
		if l, err := strconv.Atoi(limitStr); err == nil {
			// Cap maximum limit to prevent resource exhaustion
			if l > 500 {
				l = 500
			}
			if l < 1 {
				l = 1
			}
			limit = l
		}
	}

	logs, err := h.auditService.GetRecentLogs(limit)
	if err != nil {
		h.logger.Errorf("Failed to get recent audit logs: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get recent audit logs"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"logs": logs})
}
