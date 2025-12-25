package nanolink

import (
	"fmt"
	"log"
	"net"
	"sync"
	"time"

	"google.golang.org/grpc"

	pb "github.com/chenqi92/NanoLink/sdk/go/nanolink/proto"
)

// Default timeouts
const (
	DefaultHeartbeatTimeout  = 90 * time.Second  // Agent considered dead after this
	DefaultHeartbeatInterval = 30 * time.Second  // Check interval
)

// Default ports
const (
	DefaultGrpcPort = 39100
)

// Server configuration
type Config struct {
	GrpcPort       int // gRPC port for agents (default: 39100)
	TLSCert        string
	TLSKey         string
	TokenValidator TokenValidator

	// Security options
	// RequireAuthentication if true, rejects unauthenticated agent connections
	// When false (default), agents can connect via metrics stream without explicit auth
	// but will have ReadOnly permission level
	RequireAuthentication bool

	// Heartbeat timeout settings
	// HeartbeatTimeout is the duration after which an agent is considered dead (default: 90s)
	HeartbeatTimeout time.Duration
	// HeartbeatCheckInterval is the interval for checking heartbeat timeouts (default: 30s)
	HeartbeatCheckInterval time.Duration

	// AsyncCallbacks if true, callbacks are executed in separate goroutines (default: false)
	// This prevents slow callbacks from blocking message processing
	AsyncCallbacks bool
}

// Token validation result
type ValidationResult struct {
	Valid           bool
	PermissionLevel int
	ErrorMessage    string
}

// Token validator function type
type TokenValidator func(token string) ValidationResult

// Default token validator (accepts all)
func DefaultTokenValidator(token string) ValidationResult {
	return ValidationResult{Valid: true, PermissionLevel: 0}
}

// Permission levels
const (
	PermissionReadOnly       = 0
	PermissionBasicWrite     = 1
	PermissionServiceControl = 2
	PermissionSystemAdmin    = 3
)

// Server is the NanoLink gRPC server
type Server struct {
	config            Config
	agents            map[string]*AgentConnection
	agentsMu          sync.RWMutex
	onAgentConnect    func(*AgentConnection)
	onAgentDisconnect func(*AgentConnection)
	onMetrics         func(*Metrics)
	onRealtimeMetrics func(*RealtimeMetrics)
	onStaticInfo      func(*StaticInfo)
	onPeriodicData    func(*PeriodicData)
	grpcServer        *grpc.Server
	grpcServicer      *NanoLinkServicer
	heartbeatStop     chan struct{} // Channel to stop heartbeat checker
}

// NewServer creates a new NanoLink gRPC server
func NewServer(config Config) *Server {
	if config.GrpcPort == 0 {
		config.GrpcPort = DefaultGrpcPort
	}
	if config.TokenValidator == nil {
		config.TokenValidator = DefaultTokenValidator
	}
	if config.HeartbeatTimeout == 0 {
		config.HeartbeatTimeout = DefaultHeartbeatTimeout
	}
	if config.HeartbeatCheckInterval == 0 {
		config.HeartbeatCheckInterval = DefaultHeartbeatInterval
	}

	return &Server{
		config:        config,
		agents:        make(map[string]*AgentConnection),
		heartbeatStop: make(chan struct{}),
	}
}

// OnAgentConnect sets the callback for when an agent connects
func (s *Server) OnAgentConnect(callback func(*AgentConnection)) {
	s.onAgentConnect = callback
}

// OnAgentDisconnect sets the callback for when an agent disconnects
func (s *Server) OnAgentDisconnect(callback func(*AgentConnection)) {
	s.onAgentDisconnect = callback
}

// OnMetrics sets the callback for receiving metrics
func (s *Server) OnMetrics(callback func(*Metrics)) {
	s.onMetrics = callback
}

// OnRealtimeMetrics sets the callback for receiving realtime metrics
func (s *Server) OnRealtimeMetrics(callback func(*RealtimeMetrics)) {
	s.onRealtimeMetrics = callback
}

// OnStaticInfo sets the callback for receiving static hardware info
func (s *Server) OnStaticInfo(callback func(*StaticInfo)) {
	s.onStaticInfo = callback
}

// OnPeriodicData sets the callback for receiving periodic data
func (s *Server) OnPeriodicData(callback func(*PeriodicData)) {
	s.onPeriodicData = callback
}

// Start starts the gRPC server for agent connections
func (s *Server) Start() error {
	if err := s.startGRPC(); err != nil {
		return fmt.Errorf("failed to start gRPC server: %w", err)
	}

	// Start heartbeat checker
	s.startHeartbeatChecker()

	log.Printf("NanoLink gRPC Server started on port %d", s.config.GrpcPort)
	return nil
}

// startHeartbeatChecker starts a goroutine that periodically checks for dead agents
func (s *Server) startHeartbeatChecker() {
	go func() {
		ticker := time.NewTicker(s.config.HeartbeatCheckInterval)
		defer ticker.Stop()

		for {
			select {
			case <-ticker.C:
				s.checkHeartbeatTimeouts()
			case <-s.heartbeatStop:
				return
			}
		}
	}()
	log.Printf("Heartbeat checker started (timeout: %v, interval: %v)",
		s.config.HeartbeatTimeout, s.config.HeartbeatCheckInterval)
}

// checkHeartbeatTimeouts checks for agents that have timed out
func (s *Server) checkHeartbeatTimeouts() {
	var deadAgents []*AgentConnection

	s.agentsMu.RLock()
	for _, agent := range s.agents {
		if agent.HeartbeatAge() > s.config.HeartbeatTimeout {
			deadAgents = append(deadAgents, agent)
		}
	}
	s.agentsMu.RUnlock()

	// Unregister dead agents outside of the lock
	for _, agent := range deadAgents {
		log.Printf("Agent %s (%s) heartbeat timeout, disconnecting", agent.Hostname, agent.AgentID)
		agent.Close()
		s.unregisterAgent(agent)
	}
}

// startGRPC starts the gRPC server
func (s *Server) startGRPC() error {
	lis, err := net.Listen("tcp", fmt.Sprintf(":%d", s.config.GrpcPort))
	if err != nil {
		return err
	}

	s.grpcServicer = NewNanoLinkServicer(s)
	s.grpcServer = CreateGRPCServer(s.grpcServicer)

	go func() {
		log.Printf("gRPC Server started on port %d (Agent connections)", s.config.GrpcPort)
		if err := s.grpcServer.Serve(lis); err != nil {
			log.Printf("gRPC server error: %v", err)
		}
	}()

	return nil
}

// Stop stops the server
func (s *Server) Stop() error {
	// Stop heartbeat checker
	select {
	case <-s.heartbeatStop:
		// Already closed
	default:
		close(s.heartbeatStop)
	}

	// Stop gRPC server
	if s.grpcServer != nil {
		s.grpcServer.GracefulStop()
		log.Printf("gRPC server stopped")
	}

	// Close all agent connections
	s.agentsMu.Lock()
	for _, agent := range s.agents {
		agent.Close()
	}
	s.agents = make(map[string]*AgentConnection)
	s.agentsMu.Unlock()

	return nil
}

// GetAgent returns an agent by ID
func (s *Server) GetAgent(agentID string) *AgentConnection {
	s.agentsMu.RLock()
	defer s.agentsMu.RUnlock()
	return s.agents[agentID]
}

// GetAgentByHostname returns an agent by hostname
func (s *Server) GetAgentByHostname(hostname string) *AgentConnection {
	s.agentsMu.RLock()
	defer s.agentsMu.RUnlock()
	for _, agent := range s.agents {
		if agent.Hostname == hostname {
			return agent
		}
	}
	return nil
}

// GetAgents returns all connected agents
func (s *Server) GetAgents() map[string]*AgentConnection {
	s.agentsMu.RLock()
	defer s.agentsMu.RUnlock()
	result := make(map[string]*AgentConnection)
	for k, v := range s.agents {
		result[k] = v
	}
	return result
}

// registerAgent registers a new agent
func (s *Server) registerAgent(agent *AgentConnection) {
	s.agentsMu.Lock()
	s.agents[agent.AgentID] = agent
	s.agentsMu.Unlock()

	log.Printf("Agent registered: %s (%s)", agent.Hostname, agent.AgentID)

	if s.onAgentConnect != nil {
		s.onAgentConnect(agent)
	}
}

// unregisterAgent unregisters an agent
func (s *Server) unregisterAgent(agent *AgentConnection) {
	s.agentsMu.Lock()
	delete(s.agents, agent.AgentID)
	s.agentsMu.Unlock()

	log.Printf("Agent unregistered: %s (%s)", agent.Hostname, agent.AgentID)

	if s.onAgentDisconnect != nil {
		s.onAgentDisconnect(agent)
	}
}

// handleMetrics handles incoming metrics
func (s *Server) handleMetrics(metrics *Metrics) {
	if s.onMetrics != nil {
		if s.config.AsyncCallbacks {
			go s.onMetrics(metrics)
		} else {
			s.onMetrics(metrics)
		}
	}
}

// handleRealtimeMetrics handles incoming realtime metrics
func (s *Server) handleRealtimeMetrics(realtime *RealtimeMetrics) {
	if s.onRealtimeMetrics != nil {
		if s.config.AsyncCallbacks {
			go s.onRealtimeMetrics(realtime)
		} else {
			s.onRealtimeMetrics(realtime)
		}
	}
}

// handleStaticInfo handles incoming static hardware info
func (s *Server) handleStaticInfo(staticInfo *StaticInfo) {
	if s.onStaticInfo != nil {
		if s.config.AsyncCallbacks {
			go s.onStaticInfo(staticInfo)
		} else {
			s.onStaticInfo(staticInfo)
		}
	}
}

// handlePeriodicData handles incoming periodic data
func (s *Server) handlePeriodicData(periodic *PeriodicData) {
	if s.onPeriodicData != nil {
		if s.config.AsyncCallbacks {
			go s.onPeriodicData(periodic)
		} else {
			s.onPeriodicData(periodic)
		}
	}
}

// RequestData sends a data request to a specific agent.
// Use this to fetch static info, disk usage, network info etc. on demand.
// requestType should be one of the DataRequestType constants from the proto package.
func (s *Server) RequestData(agentID string, requestType int32) bool {
	if s.grpcServicer != nil {
		return s.grpcServicer.SendDataRequest(agentID, pb.DataRequestType(requestType), "")
	}
	log.Printf("Cannot send data request - gRPC service not available")
	return false
}

// RequestDataWithTarget sends a data request with a target parameter to a specific agent.
func (s *Server) RequestDataWithTarget(agentID string, requestType int32, target string) bool {
	if s.grpcServicer != nil {
		return s.grpcServicer.SendDataRequest(agentID, pb.DataRequestType(requestType), target)
	}
	log.Printf("Cannot send data request - gRPC service not available")
	return false
}

// BroadcastDataRequest sends a data request to all connected agents.
func (s *Server) BroadcastDataRequest(requestType int32) {
	if s.grpcServicer != nil {
		s.grpcServicer.BroadcastDataRequest(pb.DataRequestType(requestType))
	} else {
		log.Printf("Cannot broadcast data request - gRPC service not available")
	}
}
