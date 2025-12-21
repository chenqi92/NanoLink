package handler

import (
	"encoding/json"
	"net/http"
	"sync"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"go.uber.org/zap"
)

// DashboardWSHandler handles WebSocket connections from dashboard clients
type DashboardWSHandler struct {
	logger         *zap.SugaredLogger
	authService    AuthServiceInterface
	agentService   *service.AgentService
	metricsService *service.MetricsService

	// Client management
	clients   map[*dashboardClient]bool
	clientsMu sync.RWMutex

	// Broadcast channel
	broadcast chan *BroadcastMessage

	upgrader websocket.Upgrader
}

// AuthServiceInterface for JWT verification
type AuthServiceInterface interface {
	VerifyToken(tokenString string) (*service.JWTClaims, error)
}

type dashboardClient struct {
	conn          *websocket.Conn
	userID        uint
	username      string
	send          chan []byte
	subscriptions map[string]bool // agentIDs subscribed to
	closed        bool            // true if channel is closed
	mu            sync.Mutex
}

// DashboardMessage types
type DashboardMsgType string

const (
	MsgTypeAgents       DashboardMsgType = "agents"
	MsgTypeMetrics      DashboardMsgType = "metrics"
	MsgTypeAgentUpdate  DashboardMsgType = "agent_update"
	MsgTypeAgentOffline DashboardMsgType = "agent_offline"
	MsgTypeSummary      DashboardMsgType = "summary"
	MsgTypeSubscribe    DashboardMsgType = "subscribe"
	MsgTypeUnsubscribe  DashboardMsgType = "unsubscribe"
	MsgTypePing         DashboardMsgType = "ping"
	MsgTypePong         DashboardMsgType = "pong"
)

// DashboardMessage is the WebSocket message format
type DashboardMessage struct {
	Type      DashboardMsgType `json:"type"`
	Timestamp int64            `json:"timestamp"`
	Data      interface{}      `json:"data,omitempty"`
}

// BroadcastMessage for internal broadcast
type BroadcastMessage struct {
	Type    DashboardMsgType
	AgentID string // optional, for agent-specific updates
	Data    interface{}
}

// NewDashboardWSHandler creates a new dashboard WebSocket handler
func NewDashboardWSHandler(
	logger *zap.SugaredLogger,
	authService AuthServiceInterface,
	agentService *service.AgentService,
	metricsService *service.MetricsService,
) *DashboardWSHandler {
	h := &DashboardWSHandler{
		logger:         logger,
		authService:    authService,
		agentService:   agentService,
		metricsService: metricsService,
		clients:        make(map[*dashboardClient]bool),
		broadcast:      make(chan *BroadcastMessage, 256),
		upgrader: websocket.Upgrader{
			ReadBufferSize:  4096,
			WriteBufferSize: 4096,
			CheckOrigin: func(r *http.Request) bool {
				return true
			},
		},
	}

	// Start broadcast loop
	go h.broadcastLoop()

	return h
}

// HandleDashboardWS handles WebSocket connection upgrade
func (h *DashboardWSHandler) HandleDashboardWS(c *gin.Context) {
	token := c.Query("token")
	if token == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "token required"})
		return
	}

	claims, err := h.authService.VerifyToken(token)
	if err != nil {
		h.logger.Warnf("Dashboard WS auth failed: %v", err)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
		return
	}

	conn, err := h.upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		h.logger.Errorf("WebSocket upgrade failed: %v", err)
		return
	}

	client := &dashboardClient{
		conn:          conn,
		userID:        claims.UserID,
		username:      claims.Username,
		send:          make(chan []byte, 256),
		subscriptions: make(map[string]bool),
	}

	h.registerClient(client)
	h.logger.Infof("Dashboard client connected: user=%s", claims.Username)

	// Send initial data
	go h.sendInitialData(client)

	// Start read/write goroutines
	go h.writePump(client)
	h.readPump(client)
}

func (h *DashboardWSHandler) registerClient(client *dashboardClient) {
	h.clientsMu.Lock()
	h.clients[client] = true
	h.clientsMu.Unlock()
}

func (h *DashboardWSHandler) unregisterClient(client *dashboardClient) {
	h.clientsMu.Lock()
	if _, ok := h.clients[client]; ok {
		delete(h.clients, client)
		// Set closed flag before closing channel to prevent panic
		client.mu.Lock()
		client.closed = true
		client.mu.Unlock()
		close(client.send)
	}
	h.clientsMu.Unlock()
}

func (h *DashboardWSHandler) sendInitialData(client *dashboardClient) {
	// Send all agents
	agents := h.agentService.GetAllAgents()
	h.sendToClient(client, &DashboardMessage{
		Type:      MsgTypeAgents,
		Timestamp: time.Now().UnixMilli(),
		Data:      agents,
	})

	// Send all metrics
	metrics := h.metricsService.GetAllCurrentMetrics()
	h.sendToClient(client, &DashboardMessage{
		Type:      MsgTypeMetrics,
		Timestamp: time.Now().UnixMilli(),
		Data:      metrics,
	})

	// Send summary
	summary := h.metricsService.GetSummary()
	h.sendToClient(client, &DashboardMessage{
		Type:      MsgTypeSummary,
		Timestamp: time.Now().UnixMilli(),
		Data:      summary,
	})
}

func (h *DashboardWSHandler) sendToClient(client *dashboardClient, msg *DashboardMessage) {
	data, err := json.Marshal(msg)
	if err != nil {
		h.logger.Errorf("Failed to marshal message: %v", err)
		return
	}

	client.mu.Lock()
	if client.closed {
		client.mu.Unlock()
		return
	}
	client.mu.Unlock()

	select {
	case client.send <- data:
	default:
		h.logger.Warnf("Client send buffer full, dropping message")
	}
}

func (h *DashboardWSHandler) readPump(client *dashboardClient) {
	defer func() {
		h.unregisterClient(client)
		client.conn.Close()
		h.logger.Infof("Dashboard client disconnected: user=%s", client.username)
	}()

	client.conn.SetReadLimit(64 * 1024)
	client.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	client.conn.SetPongHandler(func(string) error {
		client.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})

	for {
		_, message, err := client.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				h.logger.Warnf("Dashboard WS read error: %v", err)
			}
			return
		}

		var msg DashboardMessage
		if err := json.Unmarshal(message, &msg); err != nil {
			continue
		}

		switch msg.Type {
		case MsgTypePing:
			h.sendToClient(client, &DashboardMessage{
				Type:      MsgTypePong,
				Timestamp: time.Now().UnixMilli(),
			})

		case MsgTypeSubscribe:
			if agentID, ok := msg.Data.(string); ok {
				client.mu.Lock()
				client.subscriptions[agentID] = true
				client.mu.Unlock()
			}

		case MsgTypeUnsubscribe:
			if agentID, ok := msg.Data.(string); ok {
				client.mu.Lock()
				delete(client.subscriptions, agentID)
				client.mu.Unlock()
			}
		}
	}
}

func (h *DashboardWSHandler) writePump(client *dashboardClient) {
	ticker := time.NewTicker(45 * time.Second)
	defer func() {
		ticker.Stop()
		client.conn.Close()
	}()

	for {
		select {
		case message, ok := <-client.send:
			client.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if !ok {
				client.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			if err := client.conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}

		case <-ticker.C:
			client.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := client.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func (h *DashboardWSHandler) broadcastLoop() {
	for msg := range h.broadcast {
		data, err := json.Marshal(&DashboardMessage{
			Type:      msg.Type,
			Timestamp: time.Now().UnixMilli(),
			Data:      msg.Data,
		})
		if err != nil {
			continue
		}

		h.clientsMu.RLock()
		for client := range h.clients {
			select {
			case client.send <- data:
			default:
				// Buffer full, skip this client
			}
		}
		h.clientsMu.RUnlock()
	}
}

// BroadcastAgentUpdate broadcasts agent update to all connected clients
func (h *DashboardWSHandler) BroadcastAgentUpdate(agentID string, agent interface{}) {
	h.broadcast <- &BroadcastMessage{
		Type:    MsgTypeAgentUpdate,
		AgentID: agentID,
		Data:    agent,
	}
}

// BroadcastMetrics broadcasts metrics to all connected clients
func (h *DashboardWSHandler) BroadcastMetrics(agentID string, metrics interface{}) {
	h.broadcast <- &BroadcastMessage{
		Type:    MsgTypeMetrics,
		AgentID: agentID,
		Data: map[string]interface{}{
			"agentId": agentID,
			"metrics": metrics,
		},
	}
}

// BroadcastAgentOffline broadcasts agent offline event
func (h *DashboardWSHandler) BroadcastAgentOffline(agentID string) {
	h.broadcast <- &BroadcastMessage{
		Type:    MsgTypeAgentOffline,
		AgentID: agentID,
		Data:    agentID,
	}
}

// BroadcastSummary broadcasts summary update
func (h *DashboardWSHandler) BroadcastSummary(summary interface{}) {
	h.broadcast <- &BroadcastMessage{
		Type: MsgTypeSummary,
		Data: summary,
	}
}

// ClientCount returns the number of connected clients
func (h *DashboardWSHandler) ClientCount() int {
	h.clientsMu.RLock()
	defer h.clientsMu.RUnlock()
	return len(h.clients)
}
