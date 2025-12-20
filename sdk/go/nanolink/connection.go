package nanolink

import (
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
)

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = (pongWait * 9) / 10
	maxMessageSize = 65536
)

// AgentConnection represents a connection to a monitoring agent
type AgentConnection struct {
	AgentID         string
	Hostname        string
	OS              string
	Arch            string
	Version         string
	PermissionLevel int
	ConnectedAt     time.Time
	LastHeartbeat   time.Time
	LastMetrics     *Metrics

	conn     *websocket.Conn
	server   *Server
	send     chan []byte
	done     chan struct{}
	mu       sync.Mutex
	authenticated bool
	pendingCmds   map[string]chan *CommandResult
	pendingMu     sync.Mutex
}

// NewAgentConnection creates a new agent connection
func NewAgentConnection(conn *websocket.Conn, server *Server) *AgentConnection {
	return &AgentConnection{
		AgentID:     uuid.New().String(),
		conn:        conn,
		server:      server,
		send:        make(chan []byte, 256),
		done:        make(chan struct{}),
		ConnectedAt: time.Now(),
		LastHeartbeat: time.Now(),
		pendingCmds: make(map[string]chan *CommandResult),
	}
}

// readPump pumps messages from the websocket connection to the server
func (c *AgentConnection) readPump() {
	defer func() {
		if c.authenticated {
			c.server.unregisterAgent(c)
		}
		c.conn.Close()
		close(c.done)
	}()

	c.conn.SetReadLimit(maxMessageSize)
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, message, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("WebSocket error: %v", err)
			}
			break
		}

		c.handleMessage(message)
	}
}

// writePump pumps messages from the server to the websocket connection
func (c *AgentConnection) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			if err := c.conn.WriteMessage(websocket.BinaryMessage, message); err != nil {
				return
			}

		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}

		case <-c.done:
			return
		}
	}
}

// handleMessage handles incoming messages
func (c *AgentConnection) handleMessage(data []byte) {
	// Parse protobuf envelope (simplified)
	// In production, use generated protobuf code

	if len(data) < 4 {
		return
	}

	// Detect message type from protobuf field numbers
	msgType := c.detectMessageType(data)

	switch msgType {
	case 10: // AuthRequest
		c.handleAuthRequest(data)
	case 20: // Metrics
		c.handleMetrics(data)
	case 21: // MetricsSync
		c.handleMetricsSync(data)
	case 22: // RealtimeMetrics
		c.handleRealtimeMetrics(data)
	case 23: // StaticInfo
		c.handleStaticInfo(data)
	case 24: // PeriodicData
		c.handlePeriodicData(data)
	case 31: // CommandResult
		c.handleCommandResult(data)
	case 40: // Heartbeat
		c.handleHeartbeat(data)
	}
}

func (c *AgentConnection) detectMessageType(data []byte) int {
	// Simplified detection
	for i := 0; i < min(len(data), 20); i++ {
		fieldTag := int(data[i])
		fieldNumber := fieldTag >> 3
		if fieldNumber >= 10 && fieldNumber <= 50 {
			return fieldNumber
		}
	}
	return 0
}

func (c *AgentConnection) handleAuthRequest(data []byte) {
	// Parse auth request (simplified)
	// In production, properly parse protobuf

	token := "demo_token" // Extract from protobuf
	hostname := "unknown"
	version := "0.1.0"
	os := "unknown"
	arch := "unknown"

	// Validate token
	result := c.server.config.TokenValidator(token)

	if result.Valid {
		c.authenticated = true
		c.Hostname = hostname
		c.Version = version
		c.OS = os
		c.Arch = arch
		c.PermissionLevel = result.PermissionLevel

		c.server.registerAgent(c)
		c.sendAuthResponse(true, result.PermissionLevel, "")
		log.Printf("Agent authenticated: %s (permission: %d)", hostname, result.PermissionLevel)
	} else {
		c.sendAuthResponse(false, 0, result.ErrorMessage)
		c.Close()
		log.Printf("Agent authentication failed: %s", result.ErrorMessage)
	}
}

func (c *AgentConnection) sendAuthResponse(success bool, permissionLevel int, errorMsg string) {
	// Build and send auth response protobuf
	// Simplified - in production use generated protobuf
	response := []byte{} // Build proper protobuf
	c.send <- response
}

func (c *AgentConnection) handleMetrics(data []byte) {
	if !c.authenticated {
		return
	}

	// Parse metrics from protobuf (simplified)
	metrics := &Metrics{
		Timestamp: time.Now().UnixMilli(),
		Hostname:  c.Hostname,
	}

	c.LastMetrics = metrics
	c.server.handleMetrics(metrics)
}

func (c *AgentConnection) handleMetricsSync(data []byte) {
	if !c.authenticated {
		return
	}
	log.Printf("Received metrics sync from %s", c.Hostname)
}

func (c *AgentConnection) handleRealtimeMetrics(data []byte) {
	if !c.authenticated {
		return
	}

	// Parse realtime metrics from protobuf (simplified)
	realtime := &RealtimeMetrics{
		Timestamp: time.Now().UnixMilli(),
		Hostname:  c.Hostname,
	}

	c.server.handleRealtimeMetrics(realtime)
}

func (c *AgentConnection) handleStaticInfo(data []byte) {
	if !c.authenticated {
		return
	}

	// Parse static info from protobuf (simplified)
	staticInfo := &StaticInfo{
		Timestamp: time.Now().UnixMilli(),
		Hostname:  c.Hostname,
	}

	c.server.handleStaticInfo(staticInfo)
}

func (c *AgentConnection) handlePeriodicData(data []byte) {
	if !c.authenticated {
		return
	}

	// Parse periodic data from protobuf (simplified)
	periodic := &PeriodicData{
		Timestamp: time.Now().UnixMilli(),
		Hostname:  c.Hostname,
	}

	c.server.handlePeriodicData(periodic)
}

func (c *AgentConnection) handleCommandResult(data []byte) {
	if !c.authenticated {
		return
	}

	// Parse command result (simplified)
	commandID := "" // Extract from protobuf
	result := &CommandResult{}

	c.pendingMu.Lock()
	ch, ok := c.pendingCmds[commandID]
	if ok {
		delete(c.pendingCmds, commandID)
	}
	c.pendingMu.Unlock()

	if ok {
		ch <- result
		close(ch)
	}
}

func (c *AgentConnection) handleHeartbeat(data []byte) {
	if !c.authenticated {
		return
	}

	c.LastHeartbeat = time.Now()

	// Send heartbeat ack
	ack := []byte{} // Build proper protobuf
	c.send <- ack
}

// SendCommand sends a command to the agent
func (c *AgentConnection) SendCommand(cmd *Command) (*CommandResult, error) {
	if !c.authenticated {
		return nil, fmt.Errorf("agent not authenticated")
	}

	// Check permission
	if cmd.RequiredPermission() > c.PermissionLevel {
		return nil, fmt.Errorf("insufficient permission: required %d, have %d",
			cmd.RequiredPermission(), c.PermissionLevel)
	}

	// Generate command ID
	cmd.CommandID = uuid.New().String()

	// Create response channel
	ch := make(chan *CommandResult, 1)
	c.pendingMu.Lock()
	c.pendingCmds[cmd.CommandID] = ch
	c.pendingMu.Unlock()

	// Send command
	data := cmd.ToProtobuf()
	c.send <- data

	// Wait for response with timeout
	select {
	case result := <-ch:
		return result, nil
	case <-time.After(30 * time.Second):
		c.pendingMu.Lock()
		delete(c.pendingCmds, cmd.CommandID)
		c.pendingMu.Unlock()
		return nil, fmt.Errorf("command timeout")
	}
}

// Close closes the connection
func (c *AgentConnection) Close() {
	c.mu.Lock()
	defer c.mu.Unlock()

	select {
	case <-c.done:
		return
	default:
		close(c.send)
	}
}

// Convenience methods

// ListProcesses lists processes on the agent
func (c *AgentConnection) ListProcesses() (*CommandResult, error) {
	return c.SendCommand(NewProcessListCommand())
}

// KillProcess kills a process
func (c *AgentConnection) KillProcess(target string) (*CommandResult, error) {
	return c.SendCommand(NewProcessKillCommand(target))
}

// RestartService restarts a service
func (c *AgentConnection) RestartService(serviceName string) (*CommandResult, error) {
	return c.SendCommand(NewServiceRestartCommand(serviceName))
}

// RestartContainer restarts a Docker container
func (c *AgentConnection) RestartContainer(containerName string) (*CommandResult, error) {
	return c.SendCommand(NewDockerRestartCommand(containerName))
}

// TailFile reads the tail of a file
func (c *AgentConnection) TailFile(path string, lines int) (*CommandResult, error) {
	return c.SendCommand(NewFileTailCommand(path, lines))
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
