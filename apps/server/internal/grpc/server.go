package grpc

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"strings"
	"sync"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/config"
	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	pb "github.com/chenqi92/NanoLink/apps/server/internal/proto"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/google/uuid"
	"go.uber.org/zap"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/keepalive"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/peer"
	"google.golang.org/grpc/status"
)

// GrpcAgent represents a connected agent via gRPC
type GrpcAgent struct {
	AgentID         string
	Hostname        string
	OS              string
	Arch            string
	Version         string
	RemoteIP        string
	PermissionLevel int32
	ConnectedAt     time.Time
	LastMetricsAt   time.Time
	stream          pb.NanoLinkService_StreamMetricsServer
	commandChan     chan *pb.Command
	mu              sync.Mutex
	closed          bool // guarded by mu; true once commandChan is closed on disconnect
}

// sendCommand delivers cmd to the agent's command channel without racing the
// disconnect path that closes the channel. Sending on a closed channel panics,
// so the closed flag and the (non-blocking) send are both serialized by mu.
func (a *GrpcAgent) sendCommand(cmd *pb.Command) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.closed {
		return fmt.Errorf("agent disconnected")
	}
	select {
	case a.commandChan <- cmd:
		return nil
	default:
		return fmt.Errorf("command channel full")
	}
}

// markClosed marks the agent as disconnected and closes its command channel
// under mu so concurrent senders observe closed instead of panicking.
func (a *GrpcAgent) markClosed() {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.closed {
		return
	}
	a.closed = true
	close(a.commandChan)
}

// The mutable identity/heartbeat fields below (Hostname, OS, LastMetricsAt) are
// written by the single per-agent stream goroutine after the agent is published
// into s.agents, and read concurrently by dashboard goroutines (agentToProto /
// GetAgentInfo). All such post-registration access goes through mu to avoid a
// data race / torn read.

func (a *GrpcAgent) touchMetrics() {
	a.mu.Lock()
	a.LastMetricsAt = time.Now()
	a.mu.Unlock()
}

// setHostnameIfEmpty sets Hostname when it is currently empty; returns true if
// it changed (so the caller can propagate to AgentService outside the lock).
func (a *GrpcAgent) setHostnameIfEmpty(hostname string) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.Hostname == "" && hostname != "" {
		a.Hostname = hostname
		return true
	}
	return false
}

func (a *GrpcAgent) setOS(os string) {
	a.mu.Lock()
	a.OS = os
	a.mu.Unlock()
}

// identity returns a consistent snapshot of the mutable identity fields.
func (a *GrpcAgent) identity() (hostname, os string) {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.Hostname, a.OS
}

// snapshot returns a consistent copy of all fields used to build an
// AgentInfoResponse, read under mu.
func (a *GrpcAgent) snapshot() (agentID, hostname, os, arch, version string, perm int32, connectedAt, lastMetricsAt time.Time) {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.AgentID, a.Hostname, a.OS, a.Arch, a.Version, a.PermissionLevel, a.ConnectedAt, a.LastMetricsAt
}

// Server implements the gRPC NanoLinkService
type Server struct {
	pb.UnimplementedNanoLinkServiceServer
	pb.UnimplementedDashboardServiceServer

	config            *config.Config
	agentService      *service.AgentService
	agentTokenService *service.AgentTokenService
	metricsService    *service.MetricsService
	logger            *zap.SugaredLogger

	grpcServer      *grpc.Server
	authInterceptor *AuthInterceptor
	agents          map[string]*GrpcAgent
	agentsMu        sync.RWMutex

	// Event subscribers for dashboard
	agentEventSubscribers []chan *pb.AgentEvent
	metricsSubscribers    map[string][]chan *pb.Metrics
	subscribersMu         sync.RWMutex

	// Command result handler for shell sessions
	commandResultHandler func(agentID, commandID, output string, success bool)

	// Recent command results keyed by commandId, for dashboard polling
	commandResults    sync.Map // commandId -> *commandResultEntry
	commandDispatches sync.Map // commandId -> *commandDispatchEntry
	lastResultSweep   time.Time
	resultSweepMu     sync.Mutex
}

type commandResultEntry struct {
	result      *pb.CommandResult
	at          time.Time
	agentID     string
	ownerUserID uint
	ownerUser   string
	commandType string
	registered  bool
}

type commandDispatchEntry struct {
	agentID     string
	userID      uint
	username    string
	commandType string
	at          time.Time
}

const commandResultTTL = 2 * time.Minute
const commandDispatchTTL = 10 * time.Minute

// ErrCommandResultAccessDenied means the command result exists, but does not
// belong to the requested agent/user.
var ErrCommandResultAccessDenied = errors.New("command result access denied")

// NewServer creates a new gRPC server (without auth interceptor for backward compatibility)
func NewServer(
	cfg *config.Config,
	agentService *service.AgentService,
	agentTokenService *service.AgentTokenService,
	metricsService *service.MetricsService,
	logger *zap.SugaredLogger,
) *Server {
	return &Server{
		config:             cfg,
		agentService:       agentService,
		agentTokenService:  agentTokenService,
		metricsService:     metricsService,
		logger:             logger,
		agents:             make(map[string]*GrpcAgent),
		metricsSubscribers: make(map[string][]chan *pb.Metrics),
	}
}

// NewServerWithAuth creates a new gRPC server with JWT authentication interceptor
func NewServerWithAuth(
	cfg *config.Config,
	agentService *service.AgentService,
	agentTokenService *service.AgentTokenService,
	metricsService *service.MetricsService,
	authInterceptor *AuthInterceptor,
	logger *zap.SugaredLogger,
) *Server {
	return &Server{
		config:             cfg,
		agentService:       agentService,
		agentTokenService:  agentTokenService,
		metricsService:     metricsService,
		logger:             logger,
		authInterceptor:    authInterceptor,
		agents:             make(map[string]*GrpcAgent),
		metricsSubscribers: make(map[string][]chan *pb.Metrics),
	}
}

// Start starts the gRPC server
func (s *Server) Start(port int, tlsCert, tlsKey string) error {
	lis, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
	if err != nil {
		return fmt.Errorf("failed to listen: %w", err)
	}

	var opts []grpc.ServerOption

	// Configure TLS if provided
	if tlsCert != "" && tlsKey != "" {
		creds, err := credentials.NewServerTLSFromFile(tlsCert, tlsKey)
		if err != nil {
			return fmt.Errorf("failed to load TLS credentials: %w", err)
		}
		opts = append(opts, grpc.Creds(creds))
	}

	// Configure keepalive
	opts = append(opts, grpc.KeepaliveParams(keepalive.ServerParameters{
		MaxConnectionIdle:     5 * time.Minute,
		MaxConnectionAge:      30 * time.Minute,
		MaxConnectionAgeGrace: 5 * time.Second,
		Time:                  30 * time.Second,
		Timeout:               10 * time.Second,
	}))

	opts = append(opts, grpc.KeepaliveEnforcementPolicy(keepalive.EnforcementPolicy{
		MinTime:             10 * time.Second,
		PermitWithoutStream: true,
	}))

	// Add auth interceptors if available
	if s.authInterceptor != nil {
		opts = append(opts, grpc.UnaryInterceptor(s.authInterceptor.UnaryInterceptor()))
		opts = append(opts, grpc.StreamInterceptor(s.authInterceptor.StreamInterceptor()))
	}

	s.grpcServer = grpc.NewServer(opts...)
	pb.RegisterNanoLinkServiceServer(s.grpcServer, s)
	pb.RegisterDashboardServiceServer(s.grpcServer, s)

	s.logger.Infof("gRPC server starting on port %d", port)

	return s.grpcServer.Serve(lis)
}

// Stop stops the gRPC server gracefully
func (s *Server) Stop() {
	if s.grpcServer != nil {
		s.grpcServer.GracefulStop()
	}
}

// SetCommandResultHandler sets the callback for handling command results from agents
func (s *Server) SetCommandResultHandler(handler func(agentID, commandID, output string, success bool)) {
	s.commandResultHandler = handler
}

// ============== NanoLinkService Implementation ==============

// Authenticate handles agent authentication
func (s *Server) Authenticate(ctx context.Context, req *pb.AuthRequest) (*pb.AuthResponse, error) {
	s.logger.Infof("gRPC authentication request from %s", req.Hostname)

	permissionLevel, err := s.validateAgentTokenString(req.Token, "", req.Hostname, req.Os, req.Arch, req.AgentVersion)
	if err != nil {
		s.logger.Warnf("Authentication failed for %s: invalid token", req.Hostname)
		return &pb.AuthResponse{
			Success:      false,
			ErrorMessage: "Invalid authentication token",
		}, nil
	}

	s.logger.Infof("Agent %s authenticated with permission level %d", req.Hostname, permissionLevel)

	return &pb.AuthResponse{
		Success:         true,
		PermissionLevel: int32(permissionLevel),
	}, nil
}

// StreamMetrics handles bidirectional streaming for metrics and commands
func (s *Server) StreamMetrics(stream pb.NanoLinkService_StreamMetricsServer) error {
	s.logger.Info("StreamMetrics: New connection started")

	// Get client IP from stream context
	var remoteIP string
	if p, ok := peer.FromContext(stream.Context()); ok && p.Addr != nil {
		addr := p.Addr.String()
		// Extract IP without port (format: "ip:port" or "[ipv6]:port")
		if idx := strings.LastIndex(addr, ":"); idx != -1 {
			remoteIP = addr[:idx]
			// Remove brackets for IPv6
			remoteIP = strings.TrimPrefix(remoteIP, "[")
			remoteIP = strings.TrimSuffix(remoteIP, "]")
		} else {
			remoteIP = addr
		}
		s.logger.Infof("StreamMetrics: Client connected from IP: %s", remoteIP)
	}

	// Will be populated from AgentInit or generated if old agent
	var agentID string

	agent := &GrpcAgent{
		ConnectedAt: time.Now(),
		stream:      stream,
		commandChan: make(chan *pb.Command, 10),
		RemoteIP:    remoteIP,
	}

	// Wait for first message to get agent info
	s.logger.Info("StreamMetrics: Waiting for first message...")
	firstMsg, err := stream.Recv()
	if err != nil {
		s.logger.Errorf("StreamMetrics: Error receiving first message: %v", err)
		return err
	}
	s.logger.Infof("StreamMetrics: Received first message type: %T", firstMsg.GetRequest())

	// Extract agent info from first message
	// AgentInit is the preferred first message (contains persistent agent_id)
	persistentAgentID := false
	switch req := firstMsg.GetRequest().(type) {
	case *pb.MetricsStreamRequest_AgentInit:
		// New agent protocol: use the persistent agent_id from config
		if req.AgentInit.AgentId != "" {
			agentID = req.AgentInit.AgentId
			persistentAgentID = true
			s.logger.Infof("StreamMetrics: Using agent's persistent ID: %s", agentID)
		} else {
			// Agent sent empty ID, generate a new one (shouldn't happen normally)
			agentID = uuid.New().String()
			s.logger.Warnf("StreamMetrics: Agent sent empty agent_id, generated new: %s", agentID)
		}
		agent.Hostname = req.AgentInit.Hostname
		agent.OS = req.AgentInit.Os
		agent.Arch = req.AgentInit.Arch
		agent.Version = req.AgentInit.AgentVersion
	case *pb.MetricsStreamRequest_Metrics:
		// Legacy: old agent without AgentInit support
		agentID = uuid.New().String()
		s.logger.Infof("StreamMetrics: Legacy agent, generated new ID: %s", agentID)
		agent.Hostname = req.Metrics.Hostname
		if req.Metrics.SystemInfo != nil {
			agent.OS = req.Metrics.SystemInfo.OsName
		}
	case *pb.MetricsStreamRequest_StaticInfo:
		// Legacy: old agent sending StaticInfo first
		agentID = uuid.New().String()
		s.logger.Infof("StreamMetrics: Legacy agent (StaticInfo), generated new ID: %s", agentID)
		if req.StaticInfo.SystemInfo != nil {
			agent.Hostname = req.StaticInfo.SystemInfo.Hostname
			agent.OS = req.StaticInfo.SystemInfo.OsName
		}
	case *pb.MetricsStreamRequest_Realtime:
		// Legacy: old agent sending Realtime first
		agentID = uuid.New().String()
		s.logger.Infof("StreamMetrics: Legacy agent (Realtime), generated new ID: %s", agentID)
		// Realtime doesn't contain hostname, will be filled in later
	default:
		// Unknown first message type, generate ID anyway
		agentID = uuid.New().String()
		s.logger.Warnf("StreamMetrics: Unknown first message type, generated new ID: %s", agentID)
	}

	agent.AgentID = agentID
	authAgentID := ""
	if persistentAgentID {
		authAgentID = agentID
	}

	permissionLevel, err := s.validateAgentTokenFromContext(
		stream.Context(),
		authAgentID,
		agent.Hostname,
		agent.OS,
		agent.Arch,
		agent.Version,
	)
	if err != nil {
		s.logger.Warnf("StreamMetrics: authentication failed for agent %s (%s): %v", agent.Hostname, agentID, err)
		return err
	}
	agent.PermissionLevel = int32(permissionLevel)

	// Send immediate HeartbeatAck after authentication to prevent client-side timeout
	// (Some clients have RPC timeout that kills the stream if no response is received)
	initAck := &pb.MetricsStreamResponse{
		Response: &pb.MetricsStreamResponse_HeartbeatAck{
			HeartbeatAck: &pb.HeartbeatAck{
				Timestamp: uint64(time.Now().UnixMilli()),
			},
		},
	}
	if err := stream.Send(initAck); err != nil {
		s.logger.Errorf("StreamMetrics: Failed to send initial ack: %v", err)
		return err
	}
	s.logger.Info("StreamMetrics: Sent initial heartbeat ack")

	// Register agent in gRPC server's internal map
	s.agentsMu.Lock()
	s.agents[agentID] = agent
	s.agentsMu.Unlock()

	// Also register to AgentService so it appears in dashboard API
	s.agentService.RegisterGrpcAgent(agentID, service.AgentInfo{
		Hostname: agent.Hostname,
		OS:       agent.OS,
		Arch:     agent.Arch,
		Version:  agent.Version,
	}, int(agent.PermissionLevel))

	// Auto-sync agent to database for persistence
	if s.agentTokenService != nil {
		if _, err := s.agentTokenService.EnsureAgentExists(
			agentID, agent.Hostname, agent.OS, agent.Arch, agent.Version, int(agent.PermissionLevel),
		); err != nil {
			s.logger.Warnf("Failed to sync agent to database: %v", err)
		}
	}

	s.logger.Infof("gRPC agent connected: %s (%s)", agent.Hostname, agentID)

	// Notify subscribers
	s.notifyAgentEvent(pb.AgentEvent_CONNECTED, agent)

	// Handle disconnection
	defer func() {
		s.agentsMu.Lock()
		delete(s.agents, agentID)
		s.agentsMu.Unlock()

		// Unregister from AgentService
		s.agentService.UnregisterAgent(agentID)

		// Clean up metrics data to prevent accumulation on reconnect with new ID
		s.metricsService.RemoveAgent(agentID)

		agent.markClosed()

		s.logger.Infof("gRPC agent disconnected: %s (%s)", agent.Hostname, agentID)
		s.notifyAgentEvent(pb.AgentEvent_DISCONNECTED, agent)
	}()

	// Process first message
	s.processStreamMessage(agent, firstMsg)

	// Start goroutine to send commands
	go func() {
		for cmd := range agent.commandChan {
			resp := &pb.MetricsStreamResponse{
				Response: &pb.MetricsStreamResponse_Command{
					Command: cmd,
				},
			}
			if err := stream.Send(resp); err != nil {
				hostname, _ := agent.identity()
				s.logger.Errorf("Failed to send command to %s: %v", hostname, err)
				return
			}
		}
	}()

	// Receive messages from agent
	for {
		msg, err := stream.Recv()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			s.logger.Errorf("Stream error from %s: %v", agent.Hostname, err)
			return err
		}

		s.processStreamMessage(agent, msg)
	}
}

// processStreamMessage processes a message from the stream
func (s *Server) processStreamMessage(agent *GrpcAgent, msg *pb.MetricsStreamRequest) {
	// Any message from the agent means it is alive — refresh both the in-memory
	// agent registry heartbeat (drives the dashboard / agent-list online status)
	// and the DB token last_seen. The layered stream sends Realtime/Periodic
	// (not full Metrics) and the Heartbeat case only sends an ack, so updating
	// these only in specific branches left a streaming agent showing offline.
	s.agentService.UpdateHeartbeat(agent.AgentID)
	if s.agentTokenService != nil {
		s.agentTokenService.UpdateLastSeen(agent.AgentID, agent.RemoteIP)
	}

	switch req := msg.GetRequest().(type) {
	case *pb.MetricsStreamRequest_Metrics:
		agent.touchMetrics()

		// Update hostname if not set
		if agent.setHostnameIfEmpty(req.Metrics.Hostname) {
			osName := ""
			if req.Metrics.SystemInfo != nil {
				osName = req.Metrics.SystemInfo.OsName
			}
			hostname, _ := agent.identity()
			// Also update AgentService entry so dashboard shows correct info
			s.agentService.UpdateAgent(agent.AgentID, service.AgentInfo{
				Hostname: hostname,
				OS:       osName,
			})
		}

		// Forward to metrics service (convert proto to service format)
		s.metricsService.StoreMetrics(agent.AgentID, convertProtoMetrics(req.Metrics))

		// Notify metrics subscribers
		s.notifyMetrics(agent.AgentID, req.Metrics)

	case *pb.MetricsStreamRequest_Realtime:
		agent.touchMetrics()
		// Merge realtime data into current metrics
		s.metricsService.MergeRealtimeMetrics(agent.AgentID, convertRealtimeMetrics(req.Realtime))
		// Notify subscribers with updated metrics
		if current := s.metricsService.GetCurrentMetrics(agent.AgentID); current != nil {
			s.notifyMetrics(agent.AgentID, convertServiceMetrics(current))
		}

	case *pb.MetricsStreamRequest_StaticInfo:
		// Debug log to investigate memory display issue
		if req.StaticInfo.Memory != nil {
			s.logger.Infof("StaticInfo received from %s: Memory.Total=%d bytes (%.2f GB), SwapTotal=%d bytes",
				agent.AgentID,
				req.StaticInfo.Memory.Total,
				float64(req.StaticInfo.Memory.Total)/(1024*1024*1024),
				req.StaticInfo.Memory.SwapTotal)
		}
		// Merge static info into current metrics
		s.metricsService.MergeStaticInfo(agent.AgentID, convertStaticInfo(req.StaticInfo))
		// Update agent info from static info
		if req.StaticInfo.SystemInfo != nil {
			agent.setHostnameIfEmpty(req.StaticInfo.SystemInfo.Hostname)
			agent.setOS(req.StaticInfo.SystemInfo.OsName)
			hostname, os := agent.identity()

			// Also update AgentService entry so dashboard shows correct info
			s.agentService.UpdateAgent(agent.AgentID, service.AgentInfo{
				Hostname: hostname,
				OS:       os,
			})
		}

	case *pb.MetricsStreamRequest_Periodic:
		// Merge periodic data into current metrics
		s.metricsService.MergePeriodicData(agent.AgentID, convertPeriodicData(req.Periodic))

	case *pb.MetricsStreamRequest_Heartbeat:
		// Send heartbeat acknowledgment
		ack := &pb.MetricsStreamResponse{
			Response: &pb.MetricsStreamResponse_HeartbeatAck{
				HeartbeatAck: &pb.HeartbeatAck{
					Timestamp: uint64(time.Now().UnixMilli()),
				},
			},
		}
		if err := agent.stream.Send(ack); err != nil {
			s.logger.Errorf("Failed to send heartbeat ack to %s: %v", agent.Hostname, err)
		}

	case *pb.MetricsStreamRequest_CommandResult:
		s.logger.Infof("Command result from %s: %s (success=%v)",
			agent.Hostname, req.CommandResult.CommandId, req.CommandResult.Success)
		// Forward command result to shell session handler
		if s.commandResultHandler != nil {
			output := req.CommandResult.Output
			if !req.CommandResult.Success && req.CommandResult.Error != "" {
				output = req.CommandResult.Error
			}
			s.commandResultHandler(agent.AgentID, req.CommandResult.CommandId, output, req.CommandResult.Success)
		}
		// Cache the full structured result for dashboard polling
		s.storeCommandResult(agent.AgentID, req.CommandResult)
	}
}

// RegisterDispatchedCommand records ownership metadata before a command is sent
// to an agent. The HTTP result-polling endpoint uses this to prevent users who
// merely know a commandId from reading another user's command output.
func (s *Server) RegisterDispatchedCommand(commandID, agentID string, userID uint, username, commandType string) {
	commandID = strings.TrimSpace(commandID)
	agentID = strings.TrimSpace(agentID)
	if commandID == "" || agentID == "" {
		return
	}
	s.commandDispatches.Store(commandID, &commandDispatchEntry{
		agentID:     agentID,
		userID:      userID,
		username:    username,
		commandType: commandType,
		at:          time.Now(),
	})
	s.sweepCommandResults()
}

// storeCommandResult caches a command result so the dashboard can poll for it.
func (s *Server) storeCommandResult(agentID string, res *pb.CommandResult) {
	if res == nil || res.CommandId == "" {
		return
	}
	entry := &commandResultEntry{
		result:  res,
		at:      time.Now(),
		agentID: agentID,
	}
	if v, ok := s.commandDispatches.Load(res.CommandId); ok {
		meta := v.(*commandDispatchEntry)
		if meta.agentID == agentID {
			entry.ownerUserID = meta.userID
			entry.ownerUser = meta.username
			entry.commandType = meta.commandType
			entry.registered = true
		} else if s.logger != nil {
			s.logger.Warnf("Command result agent mismatch: command=%s dispatchedAgent=%s resultAgent=%s",
				res.CommandId, meta.agentID, agentID)
		}
	}
	s.commandResults.Store(res.CommandId, entry)
	s.sweepCommandResults()
}

// GetCommandResultForUser returns a cached command result only when the caller
// is the command owner, or is a super admin, and the URL's agent matches the
// agent that produced the result.
func (s *Server) GetCommandResultForUser(commandID, agentID string, userID uint, isSuperAdmin bool) (*pb.CommandResult, bool, error) {
	v, ok := s.commandResults.Load(commandID)
	if !ok {
		return nil, false, nil
	}
	entry := v.(*commandResultEntry)
	if time.Since(entry.at) > commandResultTTL {
		s.commandResults.Delete(commandID)
		return nil, false, nil
	}
	if entry.agentID != agentID || !entry.registered {
		return nil, true, ErrCommandResultAccessDenied
	}
	if !isSuperAdmin && entry.ownerUserID != userID {
		return nil, true, ErrCommandResultAccessDenied
	}
	return entry.result, true, nil
}

func (s *Server) sweepCommandResults() {
	s.resultSweepMu.Lock()
	defer s.resultSweepMu.Unlock()
	if time.Since(s.lastResultSweep) < time.Minute {
		return
	}
	s.lastResultSweep = time.Now()
	s.commandResults.Range(func(k, v any) bool {
		if time.Since(v.(*commandResultEntry).at) > commandResultTTL {
			s.commandResults.Delete(k)
		}
		return true
	})
	s.commandDispatches.Range(func(k, v any) bool {
		if time.Since(v.(*commandDispatchEntry).at) > commandDispatchTTL {
			s.commandDispatches.Delete(k)
		}
		return true
	})
}

// ReportMetrics handles one-time metrics report
func (s *Server) ReportMetrics(ctx context.Context, metrics *pb.Metrics) (*pb.MetricsAck, error) {
	// Use hostname as agent ID for unary RPC
	agentID := metrics.Hostname
	if agentID == "" {
		agentID = "unknown-" + uuid.New().String()[:8]
	}

	permissionLevel, err := s.validateAgentTokenFromContext(ctx, "", metrics.Hostname, "", "", "")
	if err != nil {
		return nil, err
	}

	// Register/update agent in AgentService so it shows in dashboard
	if existing := s.agentService.GetAgent(agentID); existing == nil {
		// Register new agent
		osName := ""
		arch := ""
		if metrics.SystemInfo != nil {
			osName = metrics.SystemInfo.OsName
		}
		s.agentService.RegisterGrpcAgent(agentID, service.AgentInfo{
			Hostname: metrics.Hostname,
			OS:       osName,
			Arch:     arch,
		}, permissionLevel)
		s.logger.Infof("Agent registered via ReportMetrics: %s", metrics.Hostname)
	} else {
		// Update heartbeat for existing agent
		s.agentService.UpdateHeartbeat(agentID)
	}

	// Record metrics
	s.metricsService.StoreMetrics(agentID, convertProtoMetrics(metrics))

	return &pb.MetricsAck{
		Success:   true,
		Timestamp: uint64(time.Now().UnixMilli()),
	}, nil
}

// ExecuteCommand sends a command to an agent (used for testing)
func (s *Server) ExecuteCommand(ctx context.Context, cmd *pb.Command) (*pb.CommandResult, error) {
	if _, err := s.validateAgentTokenFromContext(ctx, "", "", "", "", ""); err != nil {
		return nil, err
	}

	// This is typically used for direct command execution
	// For streaming agents, use the stream to send commands
	return &pb.CommandResult{
		CommandId: cmd.CommandId,
		Success:   false,
		Error:     "Use StreamMetrics for command execution with connected agents",
	}, nil
}

// Heartbeat handles heartbeat requests
func (s *Server) Heartbeat(ctx context.Context, req *pb.HeartbeatRequest) (*pb.HeartbeatResponse, error) {
	if _, err := s.validateAgentTokenFromContext(ctx, req.AgentId, "", "", "", ""); err != nil {
		return nil, err
	}

	return &pb.HeartbeatResponse{
		ServerTimestamp: uint64(time.Now().UnixMilli()),
		ConfigChanged:   false,
	}, nil
}

// SyncMetrics handles metrics synchronization after reconnection
func (s *Server) SyncMetrics(ctx context.Context, req *pb.MetricsSyncRequest) (*pb.MetricsSyncResponse, error) {
	if _, err := s.validateAgentTokenFromContext(ctx, req.AgentId, "", "", "", ""); err != nil {
		return nil, err
	}

	// Get buffered metrics from service
	// For now, return empty (metrics are not persisted in current implementation)
	return &pb.MetricsSyncResponse{
		Success:         true,
		Metrics:         []*pb.Metrics{},
		ServerTimestamp: uint64(time.Now().UnixMilli()),
	}, nil
}

// GetAgentInfo returns agent information
func (s *Server) GetAgentInfo(ctx context.Context, req *pb.AgentInfoRequest) (*pb.AgentInfoResponse, error) {
	if _, err := s.validateAgentTokenFromContext(ctx, req.AgentId, "", "", "", ""); err != nil {
		return nil, err
	}

	s.agentsMu.RLock()
	agent, exists := s.agents[req.AgentId]
	s.agentsMu.RUnlock()

	if !exists {
		return nil, fmt.Errorf("agent not found: %s", req.AgentId)
	}

	id, hostname, os, arch, version, perm, connectedAt, lastMetricsAt := agent.snapshot()
	return &pb.AgentInfoResponse{
		AgentId:         id,
		Hostname:        hostname,
		Os:              os,
		Arch:            arch,
		Version:         version,
		PermissionLevel: perm,
		ConnectedAt:     uint64(connectedAt.UnixMilli()),
		LastMetricsAt:   uint64(lastMetricsAt.UnixMilli()),
	}, nil
}

// ============== DashboardService Implementation ==============

// WatchAgents streams agent events to dashboard
func (s *Server) WatchAgents(req *pb.WatchAgentsRequest, stream pb.DashboardService_WatchAgentsServer) error {
	visible, filter := s.visibleAgentFilter(stream.Context())

	eventChan := make(chan *pb.AgentEvent, 100)

	// Register subscriber
	s.subscribersMu.Lock()
	s.agentEventSubscribers = append(s.agentEventSubscribers, eventChan)
	s.subscribersMu.Unlock()

	// Unregister on exit
	defer func() {
		s.subscribersMu.Lock()
		for i, ch := range s.agentEventSubscribers {
			if ch == eventChan {
				s.agentEventSubscribers = append(s.agentEventSubscribers[:i], s.agentEventSubscribers[i+1:]...)
				break
			}
		}
		s.subscribersMu.Unlock()
		close(eventChan)
	}()

	// Send initial agents if requested
	if req.IncludeInitial {
		s.agentsMu.RLock()
		for id, agent := range s.agents {
			if filter && !visible[id] {
				continue
			}
			event := &pb.AgentEvent{
				EventType: pb.AgentEvent_CONNECTED,
				Agent:     s.agentToProto(agent),
				Timestamp: uint64(time.Now().UnixMilli()),
			}
			if err := stream.Send(event); err != nil {
				s.agentsMu.RUnlock()
				return err
			}
		}
		s.agentsMu.RUnlock()
	}

	// Stream events
	for event := range eventChan {
		if filter {
			if a := event.GetAgent(); a == nil || !visible[a.GetAgentId()] {
				continue
			}
		}
		if err := stream.Send(event); err != nil {
			return err
		}
	}

	return nil
}

// WatchMetrics streams metrics to dashboard
func (s *Server) WatchMetrics(req *pb.WatchMetricsRequest, stream pb.DashboardService_WatchMetricsServer) error {
	visible, filter := s.visibleAgentFilter(stream.Context())

	// Resolve the concrete set of agent IDs this caller is allowed to watch.
	// pb.Metrics carries no agent ID, so authorization must happen at subscribe
	// time: a non-super-admin can never subscribe to the "*" wildcard.
	agentIDs := req.AgentIds
	if filter {
		if len(agentIDs) == 0 {
			agentIDs = make([]string, 0, len(visible))
			for id := range visible {
				agentIDs = append(agentIDs, id)
			}
		} else {
			allowed := agentIDs[:0:0]
			for _, id := range agentIDs {
				if visible[id] {
					allowed = append(allowed, id)
				}
			}
			agentIDs = allowed
		}
	}

	metricsChan := make(chan *pb.Metrics, 100)

	// Register subscriber for all requested agents (or all if empty)
	s.subscribersMu.Lock()
	if len(agentIDs) == 0 && !filter {
		// Subscribe to all (super admin / no-auth mode only)
		s.metricsSubscribers["*"] = append(s.metricsSubscribers["*"], metricsChan)
	} else {
		for _, agentID := range agentIDs {
			s.metricsSubscribers[agentID] = append(s.metricsSubscribers[agentID], metricsChan)
		}
	}
	s.subscribersMu.Unlock()

	// Unregister on exit
	defer func() {
		s.subscribersMu.Lock()
		// Remove from all subscriber lists
		for key, subs := range s.metricsSubscribers {
			for i, ch := range subs {
				if ch == metricsChan {
					s.metricsSubscribers[key] = append(subs[:i], subs[i+1:]...)
					break
				}
			}
		}
		s.subscribersMu.Unlock()
		close(metricsChan)
	}()

	// Stream metrics
	for metrics := range metricsChan {
		if err := stream.Send(metrics); err != nil {
			return err
		}
	}

	return nil
}

// visibleAgentFilter returns the set of agent IDs the caller may see and whether
// filtering should be applied. Filtering is skipped for super admins and when no
// auth interceptor is configured (backward-compatible no-auth mode). On any
// uncertainty (missing identity or lookup failure) it fails closed.
func (s *Server) visibleAgentFilter(ctx context.Context) (map[string]bool, bool) {
	if s.authInterceptor == nil {
		return nil, false
	}
	userID, _, isSuperAdmin, ok := GetUserFromContext(ctx)
	if !ok {
		return map[string]bool{}, true
	}
	if isSuperAdmin {
		return nil, false
	}
	ids, err := s.authInterceptor.permService.GetVisibleAgents(userID)
	if err != nil {
		s.logger.Errorf("Failed to resolve visible agents: %v", err)
		return map[string]bool{}, true
	}
	if ids == nil { // nil means all agents are visible
		return nil, false
	}
	set := make(map[string]bool, len(ids))
	for _, id := range ids {
		set[id] = true
	}
	return set, true
}

// GetAgents returns list of connected agents (filtered by caller permission)
func (s *Server) GetAgents(ctx context.Context, req *pb.GetAgentsRequest) (*pb.GetAgentsResponse, error) {
	visible, filter := s.visibleAgentFilter(ctx)

	s.agentsMu.RLock()
	defer s.agentsMu.RUnlock()

	agents := make([]*pb.AgentInfoResponse, 0, len(s.agents))
	for id, agent := range s.agents {
		if filter && !visible[id] {
			continue
		}
		agents = append(agents, s.agentToProto(agent))
	}

	return &pb.GetAgentsResponse{
		Agents: agents,
	}, nil
}

// GetAgentMetrics returns current metrics for an agent
func (s *Server) GetAgentMetrics(ctx context.Context, req *pb.GetAgentMetricsRequest) (*pb.Metrics, error) {
	if s.authInterceptor != nil {
		if err := s.authInterceptor.CheckAgentPermission(ctx, req.AgentId, database.PermissionReadOnly); err != nil {
			return nil, err
		}
	}

	metrics := s.metricsService.GetCurrentMetrics(req.AgentId)
	if metrics == nil {
		return nil, fmt.Errorf("no metrics available for agent: %s", req.AgentId)
	}

	return convertServiceMetrics(metrics), nil
}

// SendCommand sends a command to an agent from dashboard
func (s *Server) SendCommand(ctx context.Context, req *pb.DashboardCommandRequest) (*pb.CommandResult, error) {
	if req.Command == nil {
		return nil, status.Error(codes.InvalidArgument, "command is required")
	}

	if s.authInterceptor != nil {
		if err := s.authInterceptor.CheckAgentPermission(ctx, req.AgentId, requiredPermissionForCommand(req.Command.Type)); err != nil {
			return nil, err
		}
	}

	s.agentsMu.RLock()
	agent, exists := s.agents[req.AgentId]
	s.agentsMu.RUnlock()

	if !exists {
		return &pb.CommandResult{
			CommandId: req.Command.CommandId,
			Success:   false,
			Error:     fmt.Sprintf("agent not found: %s", req.AgentId),
		}, nil
	}

	userID, username, _, _ := GetUserFromContext(ctx)
	s.RegisterDispatchedCommand(req.Command.CommandId, req.AgentId, userID, username, req.Command.Type.String())

	// Send command to agent via stream
	if err := agent.sendCommand(req.Command); err != nil {
		return &pb.CommandResult{
			CommandId: req.Command.CommandId,
			Success:   false,
			Error:     err.Error(),
		}, nil
	}
	return &pb.CommandResult{
		CommandId: req.Command.CommandId,
		Success:   true,
		Output:    "Command sent to agent",
	}, nil
}

// ============== Helper Functions ==============

func (s *Server) agentToProto(agent *GrpcAgent) *pb.AgentInfoResponse {
	id, hostname, os, arch, version, perm, connectedAt, lastMetricsAt := agent.snapshot()
	return &pb.AgentInfoResponse{
		AgentId:         id,
		Hostname:        hostname,
		Os:              os,
		Arch:            arch,
		Version:         version,
		PermissionLevel: perm,
		ConnectedAt:     uint64(connectedAt.UnixMilli()),
		LastMetricsAt:   uint64(lastMetricsAt.UnixMilli()),
	}
}

func (s *Server) notifyAgentEvent(eventType pb.AgentEvent_EventType, agent *GrpcAgent) {
	event := &pb.AgentEvent{
		EventType: eventType,
		Agent:     s.agentToProto(agent),
		Timestamp: uint64(time.Now().UnixMilli()),
	}

	s.subscribersMu.RLock()
	defer s.subscribersMu.RUnlock()

	for _, ch := range s.agentEventSubscribers {
		select {
		case ch <- event:
		default:
			// Channel full, skip
		}
	}
}

func (s *Server) notifyMetrics(agentID string, metrics *pb.Metrics) {
	s.subscribersMu.RLock()
	defer s.subscribersMu.RUnlock()

	// Notify specific agent subscribers
	for _, ch := range s.metricsSubscribers[agentID] {
		select {
		case ch <- metrics:
		default:
		}
	}

	// Notify wildcard subscribers
	for _, ch := range s.metricsSubscribers["*"] {
		select {
		case ch <- metrics:
		default:
		}
	}
}

func (s *Server) validateAgentTokenFromContext(ctx context.Context, agentID, hostname, osName, arch, version string) (int, error) {
	token, ok := agentTokenFromContext(ctx)
	if !ok {
		return 0, status.Error(codes.Unauthenticated, "agent token not provided")
	}
	return s.validateAgentTokenString(token, agentID, hostname, osName, arch, version)
}

func (s *Server) validateAgentTokenString(token, agentID, hostname, osName, arch, version string) (int, error) {
	token = strings.TrimSpace(token)
	if token == "" {
		return 0, status.Error(codes.Unauthenticated, "agent token not provided")
	}

	if s.agentTokenService != nil {
		if agentToken, valid := s.agentTokenService.ValidateAndUpdateToken(token, agentID, hostname, osName, arch, version); valid {
			return agentToken.Permission, nil
		}
	}

	if valid, permission := s.config.ValidateToken(token); valid {
		return permission, nil
	}

	return 0, status.Error(codes.Unauthenticated, "invalid agent token")
}

func agentTokenFromContext(ctx context.Context) (string, bool) {
	md, ok := metadata.FromIncomingContext(ctx)
	if !ok {
		return "", false
	}

	for _, key := range []string{"authorization", "x-agent-token"} {
		values := md.Get(key)
		if len(values) == 0 {
			continue
		}

		token := strings.TrimSpace(values[0])
		if strings.HasPrefix(strings.ToLower(token), "bearer ") {
			token = strings.TrimSpace(token[7:])
		}
		if token != "" {
			return token, true
		}
	}

	return "", false
}

func requiredPermissionForCommand(cmdType pb.CommandType) int {
	switch cmdType {
	case pb.CommandType_PROCESS_LIST,
		pb.CommandType_SERVICE_STATUS,
		pb.CommandType_DOCKER_LIST,
		pb.CommandType_FILE_TAIL,
		pb.CommandType_AGENT_GET_VERSION,
		pb.CommandType_SERVICE_LOGS,
		pb.CommandType_PACKAGE_LIST,
		pb.CommandType_PACKAGE_CHECK_UPDATES,
		pb.CommandType_SCRIPT_LIST,
		pb.CommandType_CONFIG_READ,
		pb.CommandType_CONFIG_VALIDATE,
		pb.CommandType_CONFIG_LIST_BACKUPS,
		pb.CommandType_HEALTH_CHECK,
		pb.CommandType_CONNECTIVITY_TEST:
		return database.PermissionReadOnly
	case pb.CommandType_FILE_DOWNLOAD,
		pb.CommandType_FILE_TRUNCATE,
		pb.CommandType_DOCKER_LOGS,
		pb.CommandType_SYSTEM_LOGS,
		pb.CommandType_LOG_STREAM:
		return database.PermissionBasicWrite
	case pb.CommandType_PROCESS_KILL,
		pb.CommandType_SERVICE_START,
		pb.CommandType_SERVICE_STOP,
		pb.CommandType_SERVICE_RESTART,
		pb.CommandType_DOCKER_START,
		pb.CommandType_DOCKER_STOP,
		pb.CommandType_DOCKER_RESTART,
		pb.CommandType_FILE_UPLOAD,
		pb.CommandType_AUDIT_LOGS,
		pb.CommandType_SCRIPT_EXECUTE,
		pb.CommandType_CONFIG_WRITE,
		pb.CommandType_CONFIG_ROLLBACK:
		return database.PermissionServiceControl
	default:
		return database.PermissionSystemAdmin
	}
}

// GetAgent returns an agent by ID
func (s *Server) GetAgent(agentID string) *GrpcAgent {
	s.agentsMu.RLock()
	defer s.agentsMu.RUnlock()
	return s.agents[agentID]
}

// GetAllAgents returns all connected agents
func (s *Server) GetAllAgents() map[string]*GrpcAgent {
	s.agentsMu.RLock()
	defer s.agentsMu.RUnlock()

	result := make(map[string]*GrpcAgent)
	for k, v := range s.agents {
		result[k] = v
	}
	return result
}

// SendCommandToAgent sends a command to a specific agent
func (s *Server) SendCommandToAgent(agentID string, cmd *pb.Command) error {
	s.agentsMu.RLock()
	agent, exists := s.agents[agentID]
	s.agentsMu.RUnlock()

	if !exists {
		return fmt.Errorf("agent not found: %s", agentID)
	}

	if err := agent.sendCommand(cmd); err != nil {
		return fmt.Errorf("%w: %s", err, agentID)
	}
	return nil
}

// RequestDataFromAgent sends a data request to a specific agent
// This allows the server to request specific data types on demand
func (s *Server) RequestDataFromAgent(agentID string, requestType pb.DataRequestType, target string) error {
	s.agentsMu.RLock()
	agent, exists := s.agents[agentID]
	s.agentsMu.RUnlock()

	if !exists {
		return fmt.Errorf("agent not found: %s", agentID)
	}

	// Create data request message
	dataReq := &pb.DataRequest{
		RequestType: requestType,
		Target:      target,
	}

	resp := &pb.MetricsStreamResponse{
		Response: &pb.MetricsStreamResponse_DataRequest{
			DataRequest: dataReq,
		},
	}

	// Send via stream
	agent.mu.Lock()
	defer agent.mu.Unlock()

	if agent.stream == nil {
		return fmt.Errorf("agent stream not available: %s", agentID)
	}

	if err := agent.stream.Send(resp); err != nil {
		s.logger.Errorf("Failed to send data request to %s: %v", agent.Hostname, err)
		return err
	}

	s.logger.Infof("Sent data request (type=%v) to agent %s", requestType, agent.Hostname)
	return nil
}

// RequestDataFromAllAgents sends a data request to all connected agents
func (s *Server) RequestDataFromAllAgents(requestType pb.DataRequestType, target string) map[string]error {
	s.agentsMu.RLock()
	agentIDs := make([]string, 0, len(s.agents))
	for id := range s.agents {
		agentIDs = append(agentIDs, id)
	}
	s.agentsMu.RUnlock()

	results := make(map[string]error)
	for _, agentID := range agentIDs {
		results[agentID] = s.RequestDataFromAgent(agentID, requestType, target)
	}
	return results
}

// Conversion functions between proto and service types

func convertProtoMetrics(m *pb.Metrics) *service.MetricsData {
	if m == nil {
		return nil
	}

	metrics := &service.MetricsData{
		LoadAverage: m.LoadAverage,
	}

	if m.Cpu != nil {
		metrics.CPU = service.CPUData{
			UsagePercent:  m.Cpu.UsagePercent,
			CoreCount:     int(m.Cpu.CoreCount),
			PerCoreUsage:  m.Cpu.PerCoreUsage,
			LoadAverage:   m.LoadAverage,
			Model:         m.Cpu.Model,
			Vendor:        m.Cpu.Vendor,
			FrequencyMhz:  m.Cpu.FrequencyMhz,
			FrequencyMax:  m.Cpu.FrequencyMaxMhz,
			PhysicalCores: int(m.Cpu.PhysicalCores),
			LogicalCores:  int(m.Cpu.LogicalCores),
			Architecture:  m.Cpu.Architecture,
			Temperature:   m.Cpu.Temperature,
		}
	}

	if m.Memory != nil {
		metrics.Memory = service.MemData{
			Total:          m.Memory.Total,
			Used:           m.Memory.Used,
			Available:      m.Memory.Available,
			SwapTotal:      m.Memory.SwapTotal,
			SwapUsed:       m.Memory.SwapUsed,
			Cached:         m.Memory.Cached,
			Buffers:        m.Memory.Buffers,
			MemoryType:     m.Memory.MemoryType,
			MemorySpeedMhz: m.Memory.MemorySpeedMhz,
		}
	}

	for _, d := range m.Disks {
		usagePercent := 0.0
		if d.Total > 0 {
			usagePercent = float64(d.Used) / float64(d.Total) * 100
		}
		metrics.Disks = append(metrics.Disks, service.DiskData{
			MountPoint:   d.MountPoint,
			Device:       d.Device,
			FsType:       d.FsType,
			Total:        d.Total,
			Used:         d.Used,
			Available:    d.Available,
			UsagePercent: usagePercent,
			ReadBytesPS:  d.ReadBytesSec,
			WriteBytesPS: d.WriteBytesSec,
			Model:        d.Model,
			Serial:       d.Serial,
			DiskType:     d.DiskType,
			ReadIops:     d.ReadIops,
			WriteIops:    d.WriteIops,
			Temperature:  d.Temperature,
			HealthStatus: d.HealthStatus,
		})
	}

	for _, n := range m.Networks {
		metrics.Networks = append(metrics.Networks, service.NetData{
			Interface:     n.Interface,
			RxBytesPS:     n.RxBytesSec,
			TxBytesPS:     n.TxBytesSec,
			RxPacketsPS:   n.RxPacketsSec,
			TxPacketsPS:   n.TxPacketsSec,
			IsUp:          n.IsUp,
			MacAddress:    n.MacAddress,
			IpAddresses:   n.IpAddresses,
			SpeedMbps:     n.SpeedMbps,
			InterfaceType: n.InterfaceType,
		})
	}

	for _, g := range m.Gpus {
		metrics.GPUs = append(metrics.GPUs, service.GPUData{
			Index:           int(g.Index),
			Name:            g.Name,
			Vendor:          g.Vendor,
			UsagePercent:    g.UsagePercent,
			MemoryTotal:     g.MemoryTotal,
			MemoryUsed:      g.MemoryUsed,
			Temperature:     g.Temperature,
			FanSpeedPercent: int(g.FanSpeedPercent),
			PowerWatts:      int(g.PowerWatts),
			PowerLimitWatts: int(g.PowerLimitWatts),
			ClockCoreMhz:    g.ClockCoreMhz,
			ClockMemoryMhz:  g.ClockMemoryMhz,
			DriverVersion:   g.DriverVersion,
			PcieGeneration:  g.PcieGeneration,
			EncoderUsage:    g.EncoderUsage,
			DecoderUsage:    g.DecoderUsage,
		})
	}

	for _, n := range m.Npus {
		metrics.NPUs = append(metrics.NPUs, service.NPUData{
			Index:         int(n.Index),
			Name:          n.Name,
			Vendor:        n.Vendor,
			UsagePercent:  n.UsagePercent,
			MemoryTotal:   n.MemoryTotal,
			MemoryUsed:    n.MemoryUsed,
			Temperature:   n.Temperature,
			PowerWatts:    int(n.PowerWatts),
			DriverVersion: n.DriverVersion,
		})
	}

	for _, u := range m.UserSessions {
		metrics.UserSessions = append(metrics.UserSessions, service.UserSession{
			Username:    u.Username,
			Tty:         u.Tty,
			LoginTime:   int64(u.LoginTime),
			RemoteHost:  u.RemoteHost,
			IdleSeconds: int64(u.IdleSeconds),
			SessionType: u.SessionType,
		})
	}

	if m.SystemInfo != nil {
		metrics.SystemInfo = &service.SystemInfo{
			OsName:            m.SystemInfo.OsName,
			OsVersion:         m.SystemInfo.OsVersion,
			KernelVersion:     m.SystemInfo.KernelVersion,
			Hostname:          m.SystemInfo.Hostname,
			BootTime:          int64(m.SystemInfo.BootTime),
			UptimeSeconds:     int64(m.SystemInfo.UptimeSeconds),
			MotherboardModel:  m.SystemInfo.MotherboardModel,
			MotherboardVendor: m.SystemInfo.MotherboardVendor,
			BiosVersion:       m.SystemInfo.BiosVersion,
			SystemModel:       m.SystemInfo.SystemModel,
			SystemVendor:      m.SystemInfo.SystemVendor,
		}
	}

	return metrics
}

func convertServiceMetrics(m *service.MetricsData) *pb.Metrics {
	if m == nil {
		return nil
	}

	metrics := &pb.Metrics{
		Timestamp:   uint64(m.Timestamp.UnixMilli()),
		Hostname:    m.AgentID,
		LoadAverage: m.LoadAverage,
	}

	metrics.Cpu = &pb.CpuMetrics{
		UsagePercent:    m.CPU.UsagePercent,
		CoreCount:       uint32(m.CPU.CoreCount),
		PerCoreUsage:    m.CPU.PerCoreUsage,
		Model:           m.CPU.Model,
		Vendor:          m.CPU.Vendor,
		FrequencyMhz:    m.CPU.FrequencyMhz,
		FrequencyMaxMhz: m.CPU.FrequencyMax,
		PhysicalCores:   uint32(m.CPU.PhysicalCores),
		LogicalCores:    uint32(m.CPU.LogicalCores),
		Architecture:    m.CPU.Architecture,
		Temperature:     m.CPU.Temperature,
	}

	metrics.Memory = &pb.MemoryMetrics{
		Total:          m.Memory.Total,
		Used:           m.Memory.Used,
		Available:      m.Memory.Available,
		SwapTotal:      m.Memory.SwapTotal,
		SwapUsed:       m.Memory.SwapUsed,
		Cached:         m.Memory.Cached,
		Buffers:        m.Memory.Buffers,
		MemoryType:     m.Memory.MemoryType,
		MemorySpeedMhz: m.Memory.MemorySpeedMhz,
	}

	for _, d := range m.Disks {
		metrics.Disks = append(metrics.Disks, &pb.DiskMetrics{
			MountPoint:    d.MountPoint,
			Device:        d.Device,
			FsType:        d.FsType,
			Total:         d.Total,
			Used:          d.Used,
			Available:     d.Available,
			ReadBytesSec:  d.ReadBytesPS,
			WriteBytesSec: d.WriteBytesPS,
			Model:         d.Model,
			Serial:        d.Serial,
			DiskType:      d.DiskType,
			ReadIops:      d.ReadIops,
			WriteIops:     d.WriteIops,
			Temperature:   d.Temperature,
			HealthStatus:  d.HealthStatus,
		})
	}

	for _, n := range m.Networks {
		metrics.Networks = append(metrics.Networks, &pb.NetworkMetrics{
			Interface:     n.Interface,
			RxBytesSec:    n.RxBytesPS,
			TxBytesSec:    n.TxBytesPS,
			RxPacketsSec:  n.RxPacketsPS,
			TxPacketsSec:  n.TxPacketsPS,
			IsUp:          n.IsUp,
			MacAddress:    n.MacAddress,
			IpAddresses:   n.IpAddresses,
			SpeedMbps:     n.SpeedMbps,
			InterfaceType: n.InterfaceType,
		})
	}

	for _, g := range m.GPUs {
		metrics.Gpus = append(metrics.Gpus, &pb.GpuMetrics{
			Index:           uint32(g.Index),
			Name:            g.Name,
			Vendor:          g.Vendor,
			UsagePercent:    g.UsagePercent,
			MemoryTotal:     g.MemoryTotal,
			MemoryUsed:      g.MemoryUsed,
			Temperature:     g.Temperature,
			FanSpeedPercent: uint32(g.FanSpeedPercent),
			PowerWatts:      uint32(g.PowerWatts),
			PowerLimitWatts: uint32(g.PowerLimitWatts),
			ClockCoreMhz:    g.ClockCoreMhz,
			ClockMemoryMhz:  g.ClockMemoryMhz,
			DriverVersion:   g.DriverVersion,
			PcieGeneration:  g.PcieGeneration,
			EncoderUsage:    g.EncoderUsage,
			DecoderUsage:    g.DecoderUsage,
		})
	}

	for _, n := range m.NPUs {
		metrics.Npus = append(metrics.Npus, &pb.NpuMetrics{
			Index:         uint32(n.Index),
			Name:          n.Name,
			Vendor:        n.Vendor,
			UsagePercent:  n.UsagePercent,
			MemoryTotal:   n.MemoryTotal,
			MemoryUsed:    n.MemoryUsed,
			Temperature:   n.Temperature,
			PowerWatts:    uint32(n.PowerWatts),
			DriverVersion: n.DriverVersion,
		})
	}

	for _, u := range m.UserSessions {
		metrics.UserSessions = append(metrics.UserSessions, &pb.UserSession{
			Username:    u.Username,
			Tty:         u.Tty,
			LoginTime:   uint64(u.LoginTime),
			RemoteHost:  u.RemoteHost,
			IdleSeconds: uint64(u.IdleSeconds),
			SessionType: u.SessionType,
		})
	}

	if m.SystemInfo != nil {
		metrics.SystemInfo = &pb.SystemInfo{
			OsName:            m.SystemInfo.OsName,
			OsVersion:         m.SystemInfo.OsVersion,
			KernelVersion:     m.SystemInfo.KernelVersion,
			Hostname:          m.SystemInfo.Hostname,
			BootTime:          uint64(m.SystemInfo.BootTime),
			UptimeSeconds:     uint64(m.SystemInfo.UptimeSeconds),
			MotherboardModel:  m.SystemInfo.MotherboardModel,
			MotherboardVendor: m.SystemInfo.MotherboardVendor,
			BiosVersion:       m.SystemInfo.BiosVersion,
			SystemModel:       m.SystemInfo.SystemModel,
			SystemVendor:      m.SystemInfo.SystemVendor,
		}
	}

	return metrics
}

// RealtimeData holds realtime metrics for merging
type RealtimeData struct {
	CPUUsage     float64
	CPUPerCore   []float64
	CPUTemp      float64
	CPUFrequency uint64
	MemoryUsed   uint64
	MemoryCached uint64
	SwapUsed     uint64
	DiskIO       []service.DiskData
	NetworkIO    []service.NetData
	LoadAverage  []float64
	GPUUsage     []service.GPUData
	NPUUsage     []service.NPUData
}

func convertRealtimeMetrics(r *pb.RealtimeMetrics) *service.RealtimeUpdate {
	if r == nil {
		return nil
	}

	data := &service.RealtimeUpdate{
		CPUUsage:     r.CpuUsagePercent,
		CPUPerCore:   r.CpuPerCore,
		CPUTemp:      r.CpuTemperature,
		CPUFrequency: r.CpuFrequencyMhz,
		MemoryUsed:   r.MemoryUsed,
		MemoryCached: r.MemoryCached,
		SwapUsed:     r.SwapUsed,
		LoadAverage:  r.LoadAverage,
	}

	for _, d := range r.DiskIo {
		data.DiskIO = append(data.DiskIO, service.DiskData{
			Device:       d.Device,
			ReadBytesPS:  d.ReadBytesSec,
			WriteBytesPS: d.WriteBytesSec,
			ReadIops:     d.ReadIops,
			WriteIops:    d.WriteIops,
		})
	}

	for _, n := range r.NetworkIo {
		data.NetworkIO = append(data.NetworkIO, service.NetData{
			Interface:   n.Interface,
			RxBytesPS:   n.RxBytesSec,
			TxBytesPS:   n.TxBytesSec,
			RxPacketsPS: n.RxPacketsSec,
			TxPacketsPS: n.TxPacketsSec,
			IsUp:        n.IsUp,
		})
	}

	for _, g := range r.GpuUsage {
		data.GPUUsage = append(data.GPUUsage, service.GPUData{
			Index:        int(g.Index),
			UsagePercent: g.UsagePercent,
			MemoryUsed:   g.MemoryUsed,
			Temperature:  g.Temperature,
			PowerWatts:   int(g.PowerWatts),
			ClockCoreMhz: g.ClockCoreMhz,
			EncoderUsage: g.EncoderUsage,
			DecoderUsage: g.DecoderUsage,
		})
	}

	for _, n := range r.NpuUsage {
		data.NPUUsage = append(data.NPUUsage, service.NPUData{
			Index:        int(n.Index),
			UsagePercent: n.UsagePercent,
			MemoryUsed:   n.MemoryUsed,
			Temperature:  n.Temperature,
			PowerWatts:   int(n.PowerWatts),
		})
	}

	return data
}

// StaticData holds static hardware info for merging
type StaticData struct {
	CPU        *service.CPUData
	Memory     *service.MemData
	Disks      []service.DiskData
	Networks   []service.NetData
	GPUs       []service.GPUData
	NPUs       []service.NPUData
	SystemInfo *service.SystemInfo
}

func convertStaticInfo(s *pb.StaticInfo) *StaticData {
	if s == nil {
		return nil
	}

	data := &StaticData{}

	if s.Cpu != nil {
		data.CPU = &service.CPUData{
			Model:         s.Cpu.Model,
			Vendor:        s.Cpu.Vendor,
			PhysicalCores: int(s.Cpu.PhysicalCores),
			LogicalCores:  int(s.Cpu.LogicalCores),
			Architecture:  s.Cpu.Architecture,
			FrequencyMax:  s.Cpu.FrequencyMaxMhz,
		}
	}

	if s.Memory != nil {
		data.Memory = &service.MemData{
			Total:          s.Memory.Total,
			SwapTotal:      s.Memory.SwapTotal,
			MemoryType:     s.Memory.MemoryType,
			MemorySpeedMhz: s.Memory.MemorySpeedMhz,
		}
	}

	for _, d := range s.Disks {
		data.Disks = append(data.Disks, service.DiskData{
			Device:       d.Device,
			MountPoint:   d.MountPoint,
			FsType:       d.FsType,
			Model:        d.Model,
			Serial:       d.Serial,
			DiskType:     d.DiskType,
			Total:        d.TotalBytes,
			HealthStatus: d.HealthStatus,
		})
	}

	for _, n := range s.Networks {
		data.Networks = append(data.Networks, service.NetData{
			Interface:     n.Interface,
			MacAddress:    n.MacAddress,
			IpAddresses:   n.IpAddresses,
			SpeedMbps:     n.SpeedMbps,
			InterfaceType: n.InterfaceType,
		})
	}

	for _, g := range s.Gpus {
		data.GPUs = append(data.GPUs, service.GPUData{
			Index:           int(g.Index),
			Name:            g.Name,
			Vendor:          g.Vendor,
			MemoryTotal:     g.MemoryTotal,
			DriverVersion:   g.DriverVersion,
			PcieGeneration:  g.PcieGeneration,
			PowerLimitWatts: int(g.PowerLimitWatts),
		})
	}

	for _, n := range s.Npus {
		data.NPUs = append(data.NPUs, service.NPUData{
			Index:         int(n.Index),
			Name:          n.Name,
			Vendor:        n.Vendor,
			MemoryTotal:   n.MemoryTotal,
			DriverVersion: n.DriverVersion,
		})
	}

	if s.SystemInfo != nil {
		data.SystemInfo = &service.SystemInfo{
			OsName:            s.SystemInfo.OsName,
			OsVersion:         s.SystemInfo.OsVersion,
			KernelVersion:     s.SystemInfo.KernelVersion,
			Hostname:          s.SystemInfo.Hostname,
			BootTime:          int64(s.SystemInfo.BootTime),
			UptimeSeconds:     int64(s.SystemInfo.UptimeSeconds),
			MotherboardModel:  s.SystemInfo.MotherboardModel,
			MotherboardVendor: s.SystemInfo.MotherboardVendor,
			BiosVersion:       s.SystemInfo.BiosVersion,
			SystemModel:       s.SystemInfo.SystemModel,
			SystemVendor:      s.SystemInfo.SystemVendor,
		}
	}

	return data
}

func convertPeriodicData(p *pb.PeriodicData) *service.PeriodicUpdate {
	if p == nil {
		return nil
	}

	data := &service.PeriodicUpdate{}

	for _, d := range p.DiskUsage {
		usagePercent := 0.0
		if d.Total > 0 {
			usagePercent = float64(d.Used) / float64(d.Total) * 100
		}
		data.DiskUsage = append(data.DiskUsage, service.DiskData{
			Device:       d.Device,
			MountPoint:   d.MountPoint,
			Total:        d.Total,
			Used:         d.Used,
			Available:    d.Available,
			UsagePercent: usagePercent,
			Temperature:  d.Temperature,
		})
	}

	for _, u := range p.UserSessions {
		data.UserSessions = append(data.UserSessions, service.UserSession{
			Username:    u.Username,
			Tty:         u.Tty,
			LoginTime:   int64(u.LoginTime),
			RemoteHost:  u.RemoteHost,
			IdleSeconds: int64(u.IdleSeconds),
			SessionType: u.SessionType,
		})
	}

	for _, n := range p.NetworkUpdates {
		data.NetworkUpdates = append(data.NetworkUpdates, service.NetData{
			Interface:   n.Interface,
			IpAddresses: n.IpAddresses,
			IsUp:        n.IsUp,
		})
	}

	// Per-core CPU (sent at lower frequency than realtime)
	if len(p.CpuPerCore) > 0 {
		data.CpuPerCore = p.CpuPerCore
	}

	return data
}
