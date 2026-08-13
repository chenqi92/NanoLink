package handler

import (
	"net/http"

	"github.com/chenqi92/NanoLink/apps/server/internal/mcp"
	"github.com/gin-gonic/gin"
)

// MCPStatusHandler exposes a sanitized read-only MCP capability overview.
type MCPStatusHandler struct {
	server *mcp.Server
}

func NewMCPStatusHandler(server *mcp.Server) *MCPStatusHandler {
	return &MCPStatusHandler{server: server}
}

func (h *MCPStatusHandler) Overview(c *gin.Context) {
	if h.server == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "MCP overview unavailable"})
		return
	}
	c.JSON(http.StatusOK, h.server.Snapshot())
}
