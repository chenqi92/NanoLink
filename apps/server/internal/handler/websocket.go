package handler

import (
	"encoding/json"
	"net/http"
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
	CheckOrigin: func(r *http.Request) bool {
		return true // Allow all origins for now
	},
}

// WebSocketHandler handles WebSocket connections from agents
type WebSocketHandler struct {
	agentService   *service.AgentService
	metricsService *service.MetricsService
	config         *config.Config
	logger         *zap.SugaredLogger
}

// NewWebSocketHandler creates a new WebSocket handler
func NewWebSocketHandler(as *service.AgentService, ms *service.MetricsService, cfg *config.Config, logger *zap.SugaredLogger) *WebSocketHandler {
	return &WebSocketHandler{
		agentService:   as,
		metricsService: ms,
		config:         cfg,
		logger:         logger,
	}
}

// ServeHTTP implements http.Handler
func (h *WebSocketHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// Get token from query or header
	token := r.URL.Query().Get("token")
	if token == "" {
		token = r.Header.Get("Authorization")
	}

	// Validate token
	valid, permission := h.config.ValidateToken(token)
	if !valid {
		h.logger.Warnf("Invalid token from %s", r.RemoteAddr)
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Upgrade to WebSocket
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		h.logger.Errorf("WebSocket upgrade failed: %v", err)
		return
	}

	// Handle the connection
	h.handleConnection(conn, permission)
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
	Token   string `json:"token"`
	service.AgentInfo
}

// MetricsPayload represents metrics data
type MetricsPayload struct {
	CPU      service.CPUData    `json:"cpu"`
	Memory   service.MemData    `json:"memory"`
	Disks    []service.DiskData `json:"disks"`
	Networks []service.NetData  `json:"networks"`
	GPU      *service.GPUData   `json:"gpu,omitempty"`
}

func (h *WebSocketHandler) handleConnection(conn *websocket.Conn, permission int) {
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
			GPU:      payload.GPU,
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
