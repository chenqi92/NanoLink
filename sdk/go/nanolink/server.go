package nanolink

import (
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"google.golang.org/grpc"

	pb "github.com/chenqi92/NanoLink/sdk/go/nanolink/proto"
)

// Default ports
const (
	DefaultGrpcPort = 39100
	DefaultWsPort   = 9100
)

// Server configuration
type Config struct {
	WsPort          int // WebSocket/HTTP port for agent connections and API (default: 9100)
	GrpcPort        int // gRPC port for agents (default: 39100)
	TLSCert         string
	TLSKey          string
	StaticFilesPath string // Optional path to dashboard static files
	TokenValidator  TokenValidator

	// Security options
	// RequireAuthentication if true, rejects unauthenticated agent connections
	// When false (default), agents can connect via metrics stream without explicit auth
	// but will have ReadOnly permission level
	RequireAuthentication bool
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

// Server is the NanoLink server
type Server struct {
	config            Config
	agents            map[string]*AgentConnection
	agentsMu          sync.RWMutex
	upgrader          websocket.Upgrader
	onAgentConnect    func(*AgentConnection)
	onAgentDisconnect func(*AgentConnection)
	onMetrics         func(*Metrics)
	onRealtimeMetrics func(*RealtimeMetrics)
	onStaticInfo      func(*StaticInfo)
	onPeriodicData    func(*PeriodicData)
	httpServer        *http.Server
	grpcServer        *grpc.Server
	grpcServicer      *NanoLinkServicer
}

// NewServer creates a new NanoLink server
func NewServer(config Config) *Server {
	if config.WsPort == 0 {
		config.WsPort = DefaultWsPort
	}
	if config.GrpcPort == 0 {
		config.GrpcPort = DefaultGrpcPort
	}
	if config.TokenValidator == nil {
		config.TokenValidator = DefaultTokenValidator
	}

	return &Server{
		config: config,
		agents: make(map[string]*AgentConnection),
		upgrader: websocket.Upgrader{
			CheckOrigin: func(r *http.Request) bool {
				return true // Allow all origins for dashboard
			},
			ReadBufferSize:  1024,
			WriteBufferSize: 1024,
		},
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

// Start starts the server (WebSocket for agents + gRPC for agents + HTTP API)
func (s *Server) Start() error {
	// Start gRPC server for agent connections
	if err := s.startGRPC(); err != nil {
		return fmt.Errorf("failed to start gRPC server: %w", err)
	}

	mux := http.NewServeMux()

	// WebSocket endpoint for agent connections (protobuf protocol)
	mux.HandleFunc("/ws", s.handleWebSocket)

	// API endpoints
	mux.HandleFunc("/api/agents", s.handleAPIAgents)
	mux.HandleFunc("/api/health", s.handleAPIHealth)

	// Static files or info page
	if s.config.StaticFilesPath != "" {
		fs := http.FileServer(http.Dir(s.config.StaticFilesPath))
		mux.Handle("/", fs)
	} else {
		mux.HandleFunc("/", s.handleInfoPage)
	}

	addr := fmt.Sprintf(":%d", s.config.WsPort)
	s.httpServer = &http.Server{
		Addr:    addr,
		Handler: mux,
	}

	log.Printf("NanoLink Server started on port %d (WebSocket for Agent + HTTP API)", s.config.WsPort)
	if s.config.StaticFilesPath != "" {
		log.Printf("Dashboard available at http://localhost:%d/", s.config.WsPort)
	}

	if s.config.TLSCert != "" && s.config.TLSKey != "" {
		return s.httpServer.ListenAndServeTLS(s.config.TLSCert, s.config.TLSKey)
	}
	return s.httpServer.ListenAndServe()
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
	// Stop gRPC server first
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

	if s.httpServer != nil {
		return s.httpServer.Close()
	}
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
		s.onMetrics(metrics)
	}
}

// handleRealtimeMetrics handles incoming realtime metrics
func (s *Server) handleRealtimeMetrics(realtime *RealtimeMetrics) {
	if s.onRealtimeMetrics != nil {
		s.onRealtimeMetrics(realtime)
	}
}

// handleStaticInfo handles incoming static hardware info
func (s *Server) handleStaticInfo(staticInfo *StaticInfo) {
	if s.onStaticInfo != nil {
		s.onStaticInfo(staticInfo)
	}
}

// handlePeriodicData handles incoming periodic data
func (s *Server) handlePeriodicData(periodic *PeriodicData) {
	if s.onPeriodicData != nil {
		s.onPeriodicData(periodic)
	}
}

// handleWebSocket handles WebSocket connections
func (s *Server) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := s.upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("WebSocket upgrade error: %v", err)
		return
	}

	agent := NewAgentConnection(conn, s)
	go agent.readPump()
	go agent.writePump()
}

// handleAPIAgents handles the /api/agents endpoint
func (s *Server) handleAPIAgents(w http.ResponseWriter, r *http.Request) {
	agents := s.GetAgents()

	type AgentInfo struct {
		AgentID       string    `json:"agentId"`
		Hostname      string    `json:"hostname"`
		OS            string    `json:"os"`
		Arch          string    `json:"arch"`
		Version       string    `json:"version"`
		ConnectedAt   time.Time `json:"connectedAt"`
		LastHeartbeat time.Time `json:"lastHeartbeat"`
	}

	result := make([]AgentInfo, 0, len(agents))
	for _, agent := range agents {
		result = append(result, AgentInfo{
			AgentID:       agent.AgentID,
			Hostname:      agent.Hostname,
			OS:            agent.OS,
			Arch:          agent.Arch,
			Version:       agent.Version,
			ConnectedAt:   agent.ConnectedAt,
			LastHeartbeat: agent.LastHeartbeat,
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"agents": result,
	})
}

// handleAPIHealth handles the /api/health endpoint
func (s *Server) handleAPIHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status": "ok",
	})
}

// handleInfoPage serves a simple info page when no static files are configured
func (s *Server) handleInfoPage(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html")
	fmt.Fprintf(w, `<!DOCTYPE html>
<html>
<head><title>NanoLink Server</title></head>
<body style="font-family:sans-serif;padding:40px;background:#0f172a;color:#e2e8f0">
<h1>NanoLink Server</h1>
<p>The server is running.</p>
<p><b>Agent Endpoints:</b></p>
<ul>
<li>WebSocket: <code>/ws</code> (protobuf protocol for agent connections)</li>
<li>gRPC: port %d</li>
</ul>
<p><b>API Endpoints:</b></p>
<ul>
<li><a href="/api/health" style="color:#3b82f6">Health Check</a></li>
<li><a href="/api/agents" style="color:#3b82f6">Connected Agents</a></li>
</ul>
<p><i>For dashboard, use the demo projects or implement your own frontend.</i></p>
</body>
</html>`, s.config.GrpcPort)
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
