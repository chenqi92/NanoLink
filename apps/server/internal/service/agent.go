package service

import (
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"go.uber.org/zap"
)

// Agent represents a connected monitoring agent
type Agent struct {
	ID              string    `json:"id"`
	Hostname        string    `json:"hostname"`
	OS              string    `json:"os"`
	Arch            string    `json:"arch"`
	Version         string    `json:"version"`
	PermissionLevel int       `json:"permissionLevel"`
	ConnectedAt     time.Time `json:"connectedAt"`
	LastHeartbeat   time.Time `json:"lastHeartbeat"`

	conn   *websocket.Conn
	send   chan []byte
	closed bool
	mu     sync.Mutex
}

// AgentService manages agent connections
type AgentService struct {
	agents         map[string]*Agent
	mu             sync.RWMutex
	logger         *zap.SugaredLogger
	metricsService *MetricsService

	// Lifecycle callbacks for real-time push to dashboard clients. They are
	// invoked outside the agents lock. The handler package cannot be imported
	// here (it imports this package), so these hooks are wired in main.go.
	onAgentUpdate  func(agent *Agent)
	onAgentOffline func(agentID string)
}

// NewAgentService creates a new agent service
func NewAgentService(logger *zap.SugaredLogger, ms *MetricsService) *AgentService {
	return &AgentService{
		agents:         make(map[string]*Agent),
		logger:         logger,
		metricsService: ms,
	}
}

// SetOnAgentUpdate sets the callback invoked when an agent registers or its
// info changes, for broadcasting agent_update events to dashboard clients.
func (s *AgentService) SetOnAgentUpdate(fn func(agent *Agent)) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.onAgentUpdate = fn
}

// SetOnAgentOffline sets the callback invoked when an agent is unregistered,
// for broadcasting agent_offline events to dashboard clients.
func (s *AgentService) SetOnAgentOffline(fn func(agentID string)) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.onAgentOffline = fn
}

func (s *AgentService) notifyAgentUpdate(agent *Agent) {
	s.mu.RLock()
	fn := s.onAgentUpdate
	s.mu.RUnlock()
	if fn != nil {
		fn(agent)
	}
}

func (s *AgentService) notifyAgentOffline(agentID string) {
	s.mu.RLock()
	fn := s.onAgentOffline
	s.mu.RUnlock()
	if fn != nil {
		fn(agentID)
	}
}

// RegisterAgent registers a new agent connection
func (s *AgentService) RegisterAgent(conn *websocket.Conn, info AgentInfo, permission int) *Agent {
	agent := &Agent{
		ID:              uuid.New().String(),
		Hostname:        info.Hostname,
		OS:              info.OS,
		Arch:            info.Arch,
		Version:         info.Version,
		PermissionLevel: permission,
		ConnectedAt:     time.Now(),
		LastHeartbeat:   time.Now(),
		conn:            conn,
		send:            make(chan []byte, 256),
	}

	s.mu.Lock()
	s.agents[agent.ID] = agent
	s.mu.Unlock()

	s.logger.Infof("Agent registered: %s (%s) - %s/%s", agent.Hostname, agent.ID, agent.OS, agent.Arch)

	s.notifyAgentUpdate(agent)

	return agent
}

// RegisterGrpcAgent registers a gRPC agent (without WebSocket connection)
func (s *AgentService) RegisterGrpcAgent(agentID string, info AgentInfo, permission int) *Agent {
	agent := &Agent{
		ID:              agentID,
		Hostname:        info.Hostname,
		OS:              info.OS,
		Arch:            info.Arch,
		Version:         info.Version,
		PermissionLevel: permission,
		ConnectedAt:     time.Now(),
		LastHeartbeat:   time.Now(),
		conn:            nil, // gRPC agents don't have WebSocket connection
		send:            nil, // gRPC agents don't use this channel
	}

	s.mu.Lock()
	s.agents[agentID] = agent
	s.mu.Unlock()

	s.logger.Infof("gRPC Agent registered: %s (%s) - %s/%s", agent.Hostname, agentID, agent.OS, agent.Arch)

	s.notifyAgentUpdate(agent)

	return agent
}

// UpdateAgent updates an existing agent's info
func (s *AgentService) UpdateAgent(agentID string, info AgentInfo) {
	s.mu.RLock()
	agent, exists := s.agents[agentID]
	s.mu.RUnlock()

	if exists {
		// Mutate the agent's mutable fields under agent.mu so concurrent
		// readers (e.g. Snapshot from the dashboard hub) never observe a torn
		// write. Mirrors UpdateHeartbeat's locking.
		agent.mu.Lock()
		if info.Hostname != "" {
			agent.Hostname = info.Hostname
		}
		if info.OS != "" {
			agent.OS = info.OS
		}
		if info.Arch != "" {
			agent.Arch = info.Arch
		}
		if info.Version != "" {
			agent.Version = info.Version
		}
		agent.LastHeartbeat = time.Now()
		agent.mu.Unlock()
	}
}

// UnregisterAgent removes an agent
func (s *AgentService) UnregisterAgent(agentID string) {
	s.mu.Lock()
	agent, exists := s.agents[agentID]
	if exists {
		delete(s.agents, agentID)
	}
	s.mu.Unlock()

	if exists {
		agent.mu.Lock()
		agent.closed = true
		if agent.send != nil {
			close(agent.send)
		}
		agent.mu.Unlock()
		s.logger.Infof("Agent unregistered: %s (%s)", agent.Hostname, agent.ID)

		// Purge stale metrics so the dashboard summary and metrics map drop the
		// disconnected agent instead of keeping its last-seen values forever.
		if s.metricsService != nil {
			s.metricsService.RemoveAgent(agentID)
		}

		s.notifyAgentOffline(agentID)
	}
}

// GetAgent returns an agent by ID
func (s *AgentService) GetAgent(agentID string) *Agent {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.agents[agentID]
}

// GetAgentByHostname returns an agent by hostname
func (s *AgentService) GetAgentByHostname(hostname string) *Agent {
	s.mu.RLock()
	defer s.mu.RUnlock()

	for _, agent := range s.agents {
		if agent.Hostname == hostname {
			return agent
		}
	}
	return nil
}

// GetAllAgents returns all connected agents
func (s *AgentService) GetAllAgents() []*Agent {
	s.mu.RLock()
	defer s.mu.RUnlock()

	agents := make([]*Agent, 0, len(s.agents))
	for _, agent := range s.agents {
		agents = append(agents, agent)
	}
	return agents
}

// GetAgentCount returns the number of connected agents
func (s *AgentService) GetAgentCount() int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return len(s.agents)
}

// UpdateHeartbeat updates agent's last heartbeat time
func (s *AgentService) UpdateHeartbeat(agentID string) {
	s.mu.RLock()
	agent, exists := s.agents[agentID]
	s.mu.RUnlock()

	if exists {
		agent.mu.Lock()
		agent.LastHeartbeat = time.Now()
		agent.mu.Unlock()
	}
}

// SendToAgent sends a message to a specific agent
func (s *AgentService) SendToAgent(agentID string, message []byte) error {
	s.mu.RLock()
	agent, exists := s.agents[agentID]
	s.mu.RUnlock()

	if !exists {
		return ErrAgentNotFound
	}

	agent.mu.Lock()
	defer agent.mu.Unlock()

	if agent.closed {
		return ErrAgentDisconnected
	}

	select {
	case agent.send <- message:
		return nil
	default:
		return ErrAgentBufferFull
	}
}

// BroadcastToAgents sends a message to all agents
func (s *AgentService) BroadcastToAgents(message []byte) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	for _, agent := range s.agents {
		agent.mu.Lock()
		if !agent.closed {
			select {
			case agent.send <- message:
			default:
			}
		}
		agent.mu.Unlock()
	}
}

// AgentInfo holds agent registration information
type AgentInfo struct {
	Hostname string `json:"hostname"`
	OS       string `json:"os"`
	Arch     string `json:"arch"`
	Version  string `json:"agentVersion"`
}

// Errors
var (
	ErrAgentNotFound     = &AgentError{"agent not found"}
	ErrAgentDisconnected = &AgentError{"agent disconnected"}
	ErrAgentBufferFull   = &AgentError{"agent send buffer full"}
)

type AgentError struct {
	msg string
}

func (e *AgentError) Error() string {
	return e.msg
}

// GetSendChannel returns the agent's send channel
func (a *Agent) GetSendChannel() <-chan []byte {
	return a.send
}

// Snapshot returns a copy of the agent's mutable fields read under agent.mu so
// callers in other packages (e.g. the dashboard hub) can build a map without
// racing UpdateAgent/UpdateHeartbeat. ID/OS/Arch are effectively immutable after
// registration but are copied here too for a single consistent view.
func (a *Agent) Snapshot() Agent {
	a.mu.Lock()
	defer a.mu.Unlock()
	return Agent{
		ID:              a.ID,
		Hostname:        a.Hostname,
		OS:              a.OS,
		Arch:            a.Arch,
		Version:         a.Version,
		PermissionLevel: a.PermissionLevel,
		ConnectedAt:     a.ConnectedAt,
		LastHeartbeat:   a.LastHeartbeat,
	}
}
