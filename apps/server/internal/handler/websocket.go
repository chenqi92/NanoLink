package handler

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/config"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gorilla/websocket"
	"go.uber.org/zap"
)

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = (pongWait * 9) / 10
	maxMessageSize = 512 * 1024 // 512KB
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	// CheckOrigin is set dynamically in ServeHTTP using CheckOriginWithConfig
}

// CheckOriginWithConfig creates a CheckOrigin function using the provided config.
//
// It delegates to IsOriginAllowed so the agent WebSocket endpoint enforces the
// same hardened policy as the REST/dashboard layer: an empty Origin (the agent
// is a native client, not a browser) is allowed, same-origin is allowed, and
// only exact allowlist entries match. Crucially this drops the previous
// fail-open behavior (empty allowlist => allow any browser origin) and the
// honoring of "*", which reintroduced the credentialed-wildcard footgun.
func CheckOriginWithConfig(cfg *config.Config) func(r *http.Request) bool {
	return func(r *http.Request) bool {
		return IsOriginAllowed(r, cfg.Server.AllowedOrigins)
	}
}

// WebSocketHandler handles WebSocket connections from agents
type WebSocketHandler struct {
	agentService      *service.AgentService
	agentTokenService *service.AgentTokenService
	metricsService    *service.MetricsService
	config            *config.Config
	logger            *zap.SugaredLogger
}

// NewWebSocketHandler creates a new WebSocket handler
func NewWebSocketHandler(as *service.AgentService, ats *service.AgentTokenService, ms *service.MetricsService, cfg *config.Config, logger *zap.SugaredLogger) *WebSocketHandler {
	return &WebSocketHandler{
		agentService:      as,
		agentTokenService: ats,
		metricsService:    ms,
		config:            cfg,
		logger:            logger,
	}
}

// ServeHTTP implements http.Handler
func (h *WebSocketHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// Get token from Header first (preferred), then fallback to query
	token := ""
	authHeader := r.Header.Get("Authorization")
	if authHeader != "" {
		// Support "Bearer <token>" format
		if strings.HasPrefix(authHeader, "Bearer ") {
			token = strings.TrimPrefix(authHeader, "Bearer ")
		} else {
			token = authHeader
		}
	}
	// Fallback to query parameter (less secure, for backward compatibility)
	if token == "" {
		token = r.URL.Query().Get("token")
		if token != "" {
			h.logger.Warn("Token passed via URL query - use Authorization header for better security")
		}
	}

	permission, valid := h.validateAgentToken(token, service.AgentInfo{})
	if !valid {
		h.logger.Warnf("Invalid token from %s", r.RemoteAddr)
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Upgrade to WebSocket with config-based CORS checking
	wsUpgrader := websocket.Upgrader{
		ReadBufferSize:  1024,
		WriteBufferSize: 1024,
		CheckOrigin:     CheckOriginWithConfig(h.config),
	}
	conn, err := wsUpgrader.Upgrade(w, r, nil)
	if err != nil {
		h.logger.Errorf("WebSocket upgrade failed: %v", err)
		return
	}

	// Handle the connection
	h.handleConnection(conn, token, permission)
}

// Message types
type MessageType string

const (
	MsgAuth      MessageType = "auth"
	MsgMetrics   MessageType = "metrics"
	MsgHeartbeat MessageType = "heartbeat"
	MsgCommand   MessageType = "command"
	MsgResult    MessageType = "result"
)

// Message represents a WebSocket message
type Message struct {
	Type      MessageType     `json:"type"`
	Timestamp int64           `json:"timestamp"`
	Payload   json.RawMessage `json:"payload"`
}

// AuthPayload represents authentication data
type AuthPayload struct {
	Token string `json:"token"`
	service.AgentInfo
}

// MetricsPayload represents metrics data
type MetricsPayload struct {
	CPU      service.CPUData    `json:"cpu"`
	Memory   service.MemData    `json:"memory"`
	Disks    []service.DiskData `json:"disks"`
	Networks []service.NetData  `json:"networks"`
	GPUs     []service.GPUData  `json:"gpus,omitempty"`
	NPUs     []service.NPUData  `json:"npus,omitempty"`
}

func (h *WebSocketHandler) handleConnection(conn *websocket.Conn, token string, permission int) {
	defer conn.Close()

	// Wait for auth message
	conn.SetReadLimit(maxMessageSize)
	conn.SetReadDeadline(time.Now().Add(pongWait))
	conn.SetPongHandler(func(string) error {
		conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	// Read first message (should be auth)
	_, msgBytes, err := conn.ReadMessage()
	if err != nil {
		h.logger.Errorf("Failed to read auth message: %v", err)
		return
	}

	var msg Message
	if err := json.Unmarshal(msgBytes, &msg); err != nil {
		h.logger.Errorf("Failed to parse auth message: %v", err)
		return
	}

	if msg.Type != MsgAuth {
		h.logger.Errorf("Expected auth message, got: %s", msg.Type)
		return
	}

	var authPayload AuthPayload
	if err := json.Unmarshal(msg.Payload, &authPayload); err != nil {
		h.logger.Errorf("Failed to parse auth payload: %v", err)
		return
	}

	if payloadToken := strings.TrimSpace(authPayload.Token); payloadToken != "" && payloadToken != token {
		h.logger.Warnf("WebSocket auth payload token mismatch for host %s", authPayload.Hostname)
		return
	}

	refreshedPermission, valid := h.validateAgentToken(token, authPayload.AgentInfo)
	if !valid {
		h.logger.Warnf("WebSocket token rejected after auth payload for host %s", authPayload.Hostname)
		return
	}
	permission = refreshedPermission

	// Register agent
	agent := h.agentService.RegisterAgent(conn, authPayload.AgentInfo, permission)
	defer h.agentService.UnregisterAgent(agent.ID)

	// Start writer goroutine
	go h.writePump(agent, conn)

	// Read messages
	for {
		_, msgBytes, err := conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				h.logger.Errorf("WebSocket error: %v", err)
			}
			break
		}

		var msg Message
		if err := json.Unmarshal(msgBytes, &msg); err != nil {
			h.logger.Warnf("Failed to parse message: %v", err)
			continue
		}

		h.handleMessage(agent, msg)
	}
}

func (h *WebSocketHandler) validateAgentToken(token string, info service.AgentInfo) (int, bool) {
	token = strings.TrimSpace(token)
	if token == "" {
		return 0, false
	}

	if h.agentTokenService != nil {
		if agentToken, valid := h.agentTokenService.ValidateAndUpdateToken(
			token,
			"",
			info.Hostname,
			info.OS,
			info.Arch,
			info.Version,
		); valid {
			return agentToken.Permission, true
		}
	}

	valid, permission := h.config.ValidateToken(token)
	return permission, valid
}

func (h *WebSocketHandler) handleMessage(agent *service.Agent, msg Message) {
	switch msg.Type {
	case MsgMetrics:
		var payload MetricsPayload
		if err := json.Unmarshal(msg.Payload, &payload); err != nil {
			h.logger.Warnf("Failed to parse metrics: %v", err)
			return
		}

		metrics := &service.MetricsData{
			CPU:      payload.CPU,
			Memory:   payload.Memory,
			Disks:    payload.Disks,
			Networks: payload.Networks,
			GPUs:     payload.GPUs,
			NPUs:     payload.NPUs,
		}
		h.metricsService.StoreMetrics(agent.ID, metrics)

	case MsgHeartbeat:
		h.agentService.UpdateHeartbeat(agent.ID)

	case MsgResult:
		// Handle command result
		h.logger.Infof("Received command result from agent %s", agent.ID)

	default:
		h.logger.Warnf("Unknown message type: %s", msg.Type)
	}
}

func (h *WebSocketHandler) writePump(agent *service.Agent, conn *websocket.Conn) {
	ticker := time.NewTicker(pingPeriod)
	defer ticker.Stop()

	for {
		select {
		case message, ok := <-agent.GetSendChannel():
			conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			if err := conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}

		case <-ticker.C:
			conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
