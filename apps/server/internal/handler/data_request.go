package handler

import (
	"net/http"

	grpcserver "github.com/chenqi92/NanoLink/apps/server/internal/grpc"
	pb "github.com/chenqi92/NanoLink/apps/server/internal/proto"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// DataRequestHandler handles data request API
type DataRequestHandler struct {
	grpcServer *grpcserver.Server
	logger     *zap.SugaredLogger
}

// NewDataRequestHandler creates a new data request handler
func NewDataRequestHandler(grpcServer *grpcserver.Server, logger *zap.SugaredLogger) *DataRequestHandler {
	return &DataRequestHandler{
		grpcServer: grpcServer,
		logger:     logger,
	}
}

// DataRequestInput represents the input for data request API
type DataRequestInput struct {
	// RequestType: full, static, disk_usage, network_info, user_sessions, gpu_info, health
	RequestType string `json:"requestType" binding:"required"`
	// Target is optional, used for specific queries (e.g., device name for disk_usage)
	Target string `json:"target"`
}

// mapRequestType converts string request type to proto enum
func mapRequestType(reqType string) pb.DataRequestType {
	switch reqType {
	case "full":
		return pb.DataRequestType_DATA_REQUEST_FULL
	case "static":
		return pb.DataRequestType_DATA_REQUEST_STATIC
	case "disk_usage":
		return pb.DataRequestType_DATA_REQUEST_DISK_USAGE
	case "network_info":
		return pb.DataRequestType_DATA_REQUEST_NETWORK_INFO
	case "user_sessions":
		return pb.DataRequestType_DATA_REQUEST_USER_SESSIONS
	case "gpu_info":
		return pb.DataRequestType_DATA_REQUEST_GPU_INFO
	case "health":
		return pb.DataRequestType_DATA_REQUEST_HEALTH
	default:
		return pb.DataRequestType_DATA_REQUEST_FULL
	}
}

// RequestData sends a data request to a specific agent
// POST /api/agents/:id/data-request
func (h *DataRequestHandler) RequestData(c *gin.Context) {
	agentID := c.Param("id")

	var input DataRequestInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	reqType := mapRequestType(input.RequestType)

	err := h.grpcServer.RequestDataFromAgent(agentID, reqType, input.Target)
	if err != nil {
		h.logger.Errorf("Failed to send data request to agent %s: %v", agentID, err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "failed to send data request",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success":     true,
		"agentId":     agentID,
		"requestType": input.RequestType,
		"message":     "Data request sent to agent, data will be available shortly via metrics endpoint",
	})
}

// RequestDataFromAll sends a data request to all connected agents
// POST /api/agents/data-request
func (h *DataRequestHandler) RequestDataFromAll(c *gin.Context) {
	var input DataRequestInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	reqType := mapRequestType(input.RequestType)

	results := h.grpcServer.RequestDataFromAllAgents(reqType, input.Target)

	// Count successes and failures
	successCount := 0
	failedAgents := make([]string, 0)
	for agentID, err := range results {
		if err != nil {
			failedAgents = append(failedAgents, agentID)
			h.logger.Warnf("Failed to send data request to agent %s: %v", agentID, err)
		} else {
			successCount++
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"success":      successCount > 0,
		"totalAgents":  len(results),
		"successCount": successCount,
		"failedAgents": failedAgents,
		"requestType":  input.RequestType,
		"message":      "Data request sent to agents",
	})
}
