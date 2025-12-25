package nanolink

import (
	"fmt"
	"sync"
	"time"

	"github.com/google/uuid"
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

	// For gRPC stream management
	streamSend func(interface{}) error

	mu          sync.Mutex
	done        chan struct{}
	pendingCmds map[string]chan *CommandResult
	pendingMu   sync.Mutex
}

// NewAgentConnectionFromGRPC creates a new agent connection from gRPC stream
func NewAgentConnectionFromGRPC(hostname, os, arch, version string, permissionLevel int) *AgentConnection {
	return &AgentConnection{
		AgentID:         uuid.New().String(),
		Hostname:        hostname,
		OS:              os,
		Arch:            arch,
		Version:         version,
		PermissionLevel: permissionLevel,
		ConnectedAt:     time.Now(),
		LastHeartbeat:   time.Now(),
		done:            make(chan struct{}),
		pendingCmds:     make(map[string]chan *CommandResult),
	}
}

// SetStreamSend sets the function to send messages to the agent via gRPC stream
func (c *AgentConnection) SetStreamSend(send func(interface{}) error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.streamSend = send
}

// HandleCommandResult processes a command result from the agent
func (c *AgentConnection) HandleCommandResult(commandID string, result *CommandResult) {
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

// SendCommand sends a command to the agent
func (c *AgentConnection) SendCommand(cmd *Command) (*CommandResult, error) {
	c.mu.Lock()
	send := c.streamSend
	c.mu.Unlock()

	if send == nil {
		return nil, fmt.Errorf("agent stream not available")
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

	// Send command via gRPC stream
	data := cmd.ToProtobuf()
	if err := send(data); err != nil {
		c.pendingMu.Lock()
		delete(c.pendingCmds, cmd.CommandID)
		c.pendingMu.Unlock()
		return nil, fmt.Errorf("failed to send command: %w", err)
	}

	// Wait for response with timeout
	select {
	case result := <-ch:
		return result, nil
	case <-time.After(30 * time.Second):
		c.pendingMu.Lock()
		delete(c.pendingCmds, cmd.CommandID)
		c.pendingMu.Unlock()
		return nil, fmt.Errorf("command timeout")
	case <-c.done:
		return nil, fmt.Errorf("connection closed")
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
		close(c.done)
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
