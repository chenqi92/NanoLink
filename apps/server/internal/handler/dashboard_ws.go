package handler

import (
	"encoding/json"
	"net/http"
	"sync"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"go.uber.org/zap"
)

// DashboardWSHandler handles WebSocket connections from dashboard clients.
type DashboardWSHandler struct {
	logger         *zap.SugaredLogger
	permService    *service.PermissionService
	agentService   *service.AgentService
	metricsService *service.MetricsService
	allowedOrigins []string

	clients   map[*dashboardClient]bool
	clientsMu sync.RWMutex
	broadcast chan *BroadcastMessage
	upgrader  websocket.Upgrader

	// activeAlertCountFn returns the number of unresolved alert instances. It is
	// optional; when nil the summary reports 0 alerts. Wired in main.go because
	// the alert service is not available to this package at construction time.
	// Guarded by alertFnMu (a dedicated mutex, NOT clientsMu) because it is read
	// from sendSummary while the broadcast loop already holds clientsMu.RLock().
	activeAlertCountFn func() int
	alertFnMu          sync.RWMutex
}

// SetActiveAlertCountFn sets the provider used to populate Summary.totalAlerts.
// Guarded by alertFnMu so the broadcast loop's reads in activeAlertCount never
// race the wiring done from main.go.
func (h *DashboardWSHandler) SetActiveAlertCountFn(fn func() int) {
	h.alertFnMu.Lock()
	h.activeAlertCountFn = fn
	h.alertFnMu.Unlock()
}

func (h *DashboardWSHandler) activeAlertCount() int {
	h.alertFnMu.RLock()
	fn := h.activeAlertCountFn
	h.alertFnMu.RUnlock()
	if fn == nil {
		return 0
	}
	return fn()
}

type dashboardClient struct {
	conn          *websocket.Conn
	userID        uint
	username      string
	isSuperAdmin  bool
	permissionCap int
	visibleAgents map[string]struct{}
	send          chan []byte
	done          chan struct{}
	subscriptions map[string]bool
	closed        bool
	mu            sync.Mutex
}

// DashboardMessage types.
type DashboardMsgType string

const (
	MsgTypeWelcome      DashboardMsgType = "welcome"
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

// ServerVersion is the current server version.
const ServerVersion = "0.3.3"

// WelcomeData contains server information sent on connection.
type WelcomeData struct {
	Version    string   `json:"version"`
	MinVersion string   `json:"minVersion"`
	ServerTime int64    `json:"serverTime"`
	Features   []string `json:"features"`
}

// DashboardMessage is the WebSocket message format.
type DashboardMessage struct {
	Type      DashboardMsgType `json:"type"`
	Timestamp int64            `json:"timestamp"`
	Data      interface{}      `json:"data,omitempty"`
}

// BroadcastMessage for internal broadcast.
type BroadcastMessage struct {
	Type    DashboardMsgType
	AgentID string
	Data    interface{}
}

// NewDashboardWSHandler creates a new dashboard WebSocket handler.
func NewDashboardWSHandler(
	logger *zap.SugaredLogger,
	permService *service.PermissionService,
	agentService *service.AgentService,
	metricsService *service.MetricsService,
	allowedOrigins []string,
) *DashboardWSHandler {
	h := &DashboardWSHandler{
		logger:         logger,
		permService:    permService,
		agentService:   agentService,
		metricsService: metricsService,
		allowedOrigins: allowedOrigins,
		clients:        make(map[*dashboardClient]bool),
		broadcast:      make(chan *BroadcastMessage, 256),
		upgrader: websocket.Upgrader{
			ReadBufferSize:  4096,
			WriteBufferSize: 4096,
			CheckOrigin: func(r *http.Request) bool {
				return IsOriginAllowed(r, allowedOrigins)
			},
		},
	}

	go h.broadcastLoop()
	return h
}

// HandleDashboardWS handles WebSocket connection upgrade.
func (h *DashboardWSHandler) HandleDashboardWS(c *gin.Context) {
	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}

	visibleAgents, err := h.resolveVisibleAgents(user.ID, user.IsSuperAdmin)
	if err != nil {
		h.logger.Errorf("Dashboard WS permission lookup failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to resolve permissions"})
		return
	}

	conn, err := h.upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		h.logger.Errorf("Dashboard WebSocket upgrade failed: %v", err)
		return
	}

	client := &dashboardClient{
		conn:          conn,
		userID:        user.ID,
		username:      user.Username,
		isSuperAdmin:  user.IsSuperAdmin,
		permissionCap: database.PermissionSystemAdmin,
		visibleAgents: visibleAgents,
		send:          make(chan []byte, 256),
		done:          make(chan struct{}),
		subscriptions: make(map[string]bool),
	}
	if deviceLevel, isDevice := GetCurrentDevicePermission(c); isDevice {
		client.permissionCap = deviceLevel
	}

	h.registerClient(client)
	h.logger.Infof("Dashboard client connected: user=%s", user.Username)

	go h.writePump(client)
	go h.sendInitialData(client)
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
		client.close()
	}
	h.clientsMu.Unlock()
}

func (h *DashboardWSHandler) sendInitialData(client *dashboardClient) {
	h.sendToClient(client, &DashboardMessage{
		Type:      MsgTypeWelcome,
		Timestamp: time.Now().UnixMilli(),
		Data: WelcomeData{
			Version:    ServerVersion,
			MinVersion: "0.3.0",
			ServerTime: time.Now().UnixMilli(),
			Features:   []string{"websocket", "metrics", "agents", "commands", "layered_metrics"},
		},
	})

	agents := h.filterAgentsForClient(client, h.agentService.GetAllAgents())
	h.sendToClient(client, &DashboardMessage{
		Type:      MsgTypeAgents,
		Timestamp: time.Now().UnixMilli(),
		Data:      agents,
	})

	metrics := h.filterMetricsForClient(client, h.metricsService.GetAllCurrentMetrics())
	h.sendToClient(client, &DashboardMessage{
		Type:      MsgTypeMetrics,
		Timestamp: time.Now().UnixMilli(),
		Data:      metrics,
	})

	h.sendSummary(client)
}

func (h *DashboardWSHandler) sendSummary(client *dashboardClient) {
	metrics := h.filterMetricsForClient(client, h.metricsService.GetAllCurrentMetrics())
	agents := h.filterAgentsForClient(client, h.agentService.GetAllAgents())
	h.sendToClient(client, &DashboardMessage{
		Type:      MsgTypeSummary,
		Timestamp: time.Now().UnixMilli(),
		Data:      buildSummary(metrics, len(agents), h.activeAlertCount()),
	})
}

func (h *DashboardWSHandler) sendToClient(client *dashboardClient, msg *DashboardMessage) {
	data, err := json.Marshal(msg)
	if err != nil {
		h.logger.Errorf("Failed to marshal dashboard message: %v", err)
		return
	}

	if !client.trySend(data) {
		h.logger.Warnf("Dashboard client send buffer full, dropping message")
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
			if agentID, ok := msg.Data.(string); ok && client.canAccessAgent(agentID) {
				client.setSubscription(agentID, true)
			}

		case MsgTypeUnsubscribe:
			if agentID, ok := msg.Data.(string); ok {
				client.setSubscription(agentID, false)
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
		case <-client.done:
			client.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			_ = client.conn.WriteMessage(websocket.CloseMessage, []byte{})
			return

		case message := <-client.send:
			client.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
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
		h.clientsMu.RLock()
		for client := range h.clients {
			if msg.AgentID != "" && !client.canAccessAgent(msg.AgentID) {
				continue
			}

			data := msg.Data
			if msg.Type == MsgTypeAgentUpdate && msg.AgentID != "" {
				if agent := h.agentService.GetAgent(msg.AgentID); agent != nil {
					data = h.agentToMapForClient(client, agent)
				}
			}

			h.sendToClient(client, &DashboardMessage{
				Type:      msg.Type,
				Timestamp: time.Now().UnixMilli(),
				Data:      data,
			})

			if shouldRefreshSummary(msg.Type) {
				h.sendSummary(client)
			}
		}
		h.clientsMu.RUnlock()
	}
}

// BroadcastAgentUpdate broadcasts agent update to connected clients that can access the agent.
func (h *DashboardWSHandler) BroadcastAgentUpdate(agentID string, agent interface{}) {
	h.broadcast <- &BroadcastMessage{
		Type:    MsgTypeAgentUpdate,
		AgentID: agentID,
		Data:    agent,
	}
}

// BroadcastAgentRegistered broadcasts an agent_update event for a connected
// agent, rendering it in the same shape as the agents list. Wired in main.go to
// AgentService.SetOnAgentUpdate so register/reconnect events reach dashboards live.
func (h *DashboardWSHandler) BroadcastAgentRegistered(agent *service.Agent) {
	if agent == nil {
		return
	}
	h.BroadcastAgentUpdate(agent.ID, agentToMap(agent))
}

// BroadcastMetrics broadcasts metrics to connected clients that can access the agent.
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

// BroadcastAgentOffline broadcasts agent offline events.
func (h *DashboardWSHandler) BroadcastAgentOffline(agentID string) {
	h.broadcast <- &BroadcastMessage{
		Type:    MsgTypeAgentOffline,
		AgentID: agentID,
		Data:    agentID,
	}
}

// BroadcastSummary broadcasts a summary refresh to all connected clients.
func (h *DashboardWSHandler) BroadcastSummary(summary interface{}) {
	h.broadcast <- &BroadcastMessage{
		Type: MsgTypeSummary,
		Data: summary,
	}
}

// ClientCount returns the number of connected clients.
func (h *DashboardWSHandler) ClientCount() int {
	h.clientsMu.RLock()
	defer h.clientsMu.RUnlock()
	return len(h.clients)
}

func (h *DashboardWSHandler) resolveVisibleAgents(userID uint, isSuperAdmin bool) (map[string]struct{}, error) {
	if h.permService == nil || isSuperAdmin {
		return nil, nil
	}

	visibleAgents, err := h.permService.GetVisibleAgents(userID)
	if err != nil {
		return nil, err
	}

	if visibleAgents == nil {
		return nil, nil
	}

	visibleSet := make(map[string]struct{}, len(visibleAgents))
	for _, agentID := range visibleAgents {
		visibleSet[agentID] = struct{}{}
	}

	return visibleSet, nil
}

func (h *DashboardWSHandler) filterAgentsForClient(client *dashboardClient, agents []*service.Agent) []gin.H {
	result := make([]gin.H, 0, len(agents))
	for _, agent := range agents {
		if !client.canAccessAgent(agent.ID) {
			continue
		}

		result = append(result, h.agentToMapForClient(client, agent))
	}
	return result
}

// agentToMap renders a single agent in the same shape as the agents list so
// agent_update events and the initial agents snapshot stay consistent. The
// mutable fields are read via Snapshot under agent.mu so concurrent
// UpdateAgent/UpdateHeartbeat writes are not observed mid-update.
func agentToMap(agent *service.Agent) gin.H {
	s := agent.Snapshot()
	return gin.H{
		"id":              s.ID,
		"hostname":        s.Hostname,
		"os":              s.OS,
		"arch":            s.Arch,
		"version":         s.Version,
		"permissionLevel": s.PermissionLevel,
		"connectedAt":     s.ConnectedAt,
		"lastHeartbeat":   s.LastHeartbeat,
	}
}

func capPermissionLevel(granted, agentMaximum int) int {
	if granted < 0 {
		return 0
	}
	if granted > agentMaximum {
		return agentMaximum
	}
	return granted
}

func (h *DashboardWSHandler) agentToMapForClient(client *dashboardClient, agent *service.Agent) gin.H {
	result := agentToMap(agent)
	maximum, _ := result["permissionLevel"].(int)
	if h.permService != nil && !client.isSuperAdmin {
		granted, err := h.permService.GetUserAgentPermission(client.userID, agent.ID)
		if err != nil {
			h.logger.Warnf("Dashboard permission lookup failed for user %d on agent %s: %v", client.userID, agent.ID, err)
			result["permissionLevel"] = 0
			return result
		}
		maximum = capPermissionLevel(granted, maximum)
	}
	result["permissionLevel"] = capPermissionLevel(client.permissionCap, maximum)
	return result
}

func (h *DashboardWSHandler) filterMetricsForClient(client *dashboardClient, metrics map[string]*service.MetricsData) map[string]*service.MetricsData {
	filtered := make(map[string]*service.MetricsData)
	for agentID, data := range metrics {
		if client.canAccessAgent(agentID) {
			filtered[agentID] = data
		}
	}
	return filtered
}

func buildSummary(metrics map[string]*service.MetricsData, connectedAgents, totalAlerts int) map[string]interface{} {
	totalCPU := 0.0
	totalMem := uint64(0)
	usedMem := uint64(0)
	totalDisk := uint64(0)
	usedDisk := uint64(0)
	metricCount := len(metrics)

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
	if metricCount > 0 {
		avgCPU = totalCPU / float64(metricCount)
	}
	if totalMem > 0 {
		memPercent = float64(usedMem) / float64(totalMem) * 100
	}
	if totalDisk > 0 {
		diskPercent = float64(usedDisk) / float64(totalDisk) * 100
	}

	return map[string]interface{}{
		"connectedAgents": connectedAgents,
		"avgCpuPercent":   avgCPU,
		"totalMemory":     totalMem,
		"usedMemory":      usedMem,
		"memoryPercent":   memPercent,
		"totalDisk":       totalDisk,
		"usedDisk":        usedDisk,
		"diskPercent":     diskPercent,
		"totalAlerts":     totalAlerts,
	}
}

func shouldRefreshSummary(msgType DashboardMsgType) bool {
	switch msgType {
	case MsgTypeMetrics, MsgTypeAgentUpdate, MsgTypeAgentOffline, MsgTypeSummary:
		return true
	default:
		return false
	}
}

func (c *dashboardClient) canAccessAgent(agentID string) bool {
	if c.visibleAgents != nil {
		if _, ok := c.visibleAgents[agentID]; !ok {
			return false
		}
	}

	c.mu.Lock()
	defer c.mu.Unlock()

	if len(c.subscriptions) == 0 {
		return true
	}

	return c.subscriptions[agentID]
}

func (c *dashboardClient) setSubscription(agentID string, subscribed bool) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if subscribed {
		c.subscriptions[agentID] = true
		return
	}

	delete(c.subscriptions, agentID)
}

func (c *dashboardClient) trySend(data []byte) bool {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.closed {
		return false
	}

	select {
	case c.send <- data:
		return true
	default:
		return false
	}
}

func (c *dashboardClient) close() {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.closed {
		return
	}

	c.closed = true
	close(c.done)
}
