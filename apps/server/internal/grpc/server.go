package grpc

import (
	"context"
	"fmt"
	"io"
	"net"
	"sync"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/config"
	pb "github.com/chenqi92/NanoLink/apps/server/internal/proto"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/google/uuid"
	"go.uber.org/zap"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/keepalive"
)

// GrpcAgent represents a connected agent via gRPC
type GrpcAgent struct {
	AgentID         string
	Hostname        string
	OS              string
	Arch            string
	Version         string
	PermissionLevel int32
	ConnectedAt     time.Time
	LastMetricsAt   time.Time
	stream          pb.NanoLinkService_StreamMetricsServer
	commandChan     chan *pb.Command
	mu              sync.Mutex
}

// Server implements the gRPC NanoLinkService
type Server struct {
	pb.UnimplementedNanoLinkServiceServer
	pb.UnimplementedDashboardServiceServer

	config         *config.Config
	agentService   *service.AgentService
	metricsService *service.MetricsService
	logger         *zap.SugaredLogger

	grpcServer      *grpc.Server
	authInterceptor *AuthInterceptor
	agents          map[string]*GrpcAgent
	agentsMu        sync.RWMutex

	// Event subscribers for dashboard
	agentEventSubscribers []chan *pb.AgentEvent
	metricsSubscribers    map[string][]chan *pb.Metrics
	subscribersMu         sync.RWMutex
}

// NewServer creates a new gRPC server (without auth interceptor for backward compatibility)
func NewServer(
	cfg *config.Config,
	agentService *service.AgentService,
	metricsService *service.MetricsService,
	logger *zap.SugaredLogger,
) *Server {
	return &Server{
		config:             cfg,
		agentService:       agentService,
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
	metricsService *service.MetricsService,
	authInterceptor *AuthInterceptor,
	logger *zap.SugaredLogger,
) *Server {
	return &Server{
		config:             cfg,
		agentService:       agentService,
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

// ============== NanoLinkService Implementation ==============

// Authenticate handles agent authentication
func (s *Server) Authenticate(ctx context.Context, req *pb.AuthRequest) (*pb.AuthResponse, error) {
	s.logger.Infof("gRPC authentication request from %s", req.Hostname)

	// Validate token
	valid, permissionLevel := s.config.ValidateToken(req.Token)
	if !valid {
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
	// Generate agent ID for this connection
	agentID := uuid.New().String()

	agent := &GrpcAgent{
		AgentID:     agentID,
		ConnectedAt: time.Now(),
		stream:      stream,
		commandChan: make(chan *pb.Command, 10),
	}

	// Wait for first message to get agent info
	firstMsg, err := stream.Recv()
	if err != nil {
		return err
	}

	// Extract hostname from first metrics message
	if metrics := firstMsg.GetMetrics(); metrics != nil {
		agent.Hostname = metrics.Hostname
		if metrics.SystemInfo != nil {
			agent.OS = metrics.SystemInfo.OsName
		}
	}

	// Register agent
	s.agentsMu.Lock()
	s.agents[agentID] = agent
	s.agentsMu.Unlock()

	s.logger.Infof("gRPC agent connected: %s (%s)", agent.Hostname, agentID)

	// Notify subscribers
	s.notifyAgentEvent(pb.AgentEvent_CONNECTED, agent)

	// Handle disconnection
	defer func() {
		s.agentsMu.Lock()
		delete(s.agents, agentID)
		s.agentsMu.Unlock()

		close(agent.commandChan)

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
				s.logger.Errorf("Failed to send command to %s: %v", agent.Hostname, err)
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
	switch req := msg.GetRequest().(type) {
	case *pb.MetricsStreamRequest_Metrics:
		agent.LastMetricsAt = time.Now()

		// Update hostname if not set
		if agent.Hostname == "" {
			agent.Hostname = req.Metrics.Hostname
		}

		// Forward to metrics service (convert proto to service format)
		s.metricsService.StoreMetrics(agent.AgentID, convertProtoMetrics(req.Metrics))

		// Notify metrics subscribers
		s.notifyMetrics(agent.AgentID, req.Metrics)

	case *pb.MetricsStreamRequest_Realtime:
		agent.LastMetricsAt = time.Now()
		// Merge realtime data into current metrics
		s.metricsService.MergeRealtimeMetrics(agent.AgentID, convertRealtimeMetrics(req.Realtime))
		// Notify subscribers with updated metrics
		if current := s.metricsService.GetCurrentMetrics(agent.AgentID); current != nil {
			s.notifyMetrics(agent.AgentID, convertServiceMetrics(current))
		}

	case *pb.MetricsStreamRequest_StaticInfo:
		// Merge static info into current metrics
		s.metricsService.MergeStaticInfo(agent.AgentID, convertStaticInfo(req.StaticInfo))
		// Update agent info from static info
		if req.StaticInfo.SystemInfo != nil {
			if agent.Hostname == "" {
				agent.Hostname = req.StaticInfo.SystemInfo.Hostname
			}
			agent.OS = req.StaticInfo.SystemInfo.OsName
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
		// TODO: Handle command result (store or forward to waiting clients)
	}
}

// ReportMetrics handles one-time metrics report
func (s *Server) ReportMetrics(ctx context.Context, metrics *pb.Metrics) (*pb.MetricsAck, error) {
	// Record metrics
	s.metricsService.StoreMetrics(metrics.Hostname, convertProtoMetrics(metrics))

	return &pb.MetricsAck{
		Success:   true,
		Timestamp: uint64(time.Now().UnixMilli()),
	}, nil
}

// ExecuteCommand sends a command to an agent (used for testing)
func (s *Server) ExecuteCommand(ctx context.Context, cmd *pb.Command) (*pb.CommandResult, error) {
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
	return &pb.HeartbeatResponse{
		ServerTimestamp: uint64(time.Now().UnixMilli()),
		ConfigChanged:   false,
	}, nil
}

// SyncMetrics handles metrics synchronization after reconnection
func (s *Server) SyncMetrics(ctx context.Context, req *pb.MetricsSyncRequest) (*pb.MetricsSyncResponse, error) {
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
	s.agentsMu.RLock()
	agent, exists := s.agents[req.AgentId]
	s.agentsMu.RUnlock()

	if !exists {
		return nil, fmt.Errorf("agent not found: %s", req.AgentId)
	}

	return &pb.AgentInfoResponse{
		AgentId:         agent.AgentID,
		Hostname:        agent.Hostname,
		Os:              agent.OS,
		Arch:            agent.Arch,
		Version:         agent.Version,
		PermissionLevel: agent.PermissionLevel,
		ConnectedAt:     uint64(agent.ConnectedAt.UnixMilli()),
		LastMetricsAt:   uint64(agent.LastMetricsAt.UnixMilli()),
	}, nil
}

// ============== DashboardService Implementation ==============

// WatchAgents streams agent events to dashboard
func (s *Server) WatchAgents(req *pb.WatchAgentsRequest, stream pb.DashboardService_WatchAgentsServer) error {
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
		for _, agent := range s.agents {
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
		if err := stream.Send(event); err != nil {
			return err
		}
	}

	return nil
}

// WatchMetrics streams metrics to dashboard
func (s *Server) WatchMetrics(req *pb.WatchMetricsRequest, stream pb.DashboardService_WatchMetricsServer) error {
	metricsChan := make(chan *pb.Metrics, 100)

	// Register subscriber for all requested agents (or all if empty)
	s.subscribersMu.Lock()
	if len(req.AgentIds) == 0 {
		// Subscribe to all
		s.metricsSubscribers["*"] = append(s.metricsSubscribers["*"], metricsChan)
	} else {
		for _, agentID := range req.AgentIds {
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

// GetAgents returns list of connected agents
func (s *Server) GetAgents(ctx context.Context, req *pb.GetAgentsRequest) (*pb.GetAgentsResponse, error) {
	s.agentsMu.RLock()
	defer s.agentsMu.RUnlock()

	agents := make([]*pb.AgentInfoResponse, 0, len(s.agents))
	for _, agent := range s.agents {
		agents = append(agents, s.agentToProto(agent))
	}

	return &pb.GetAgentsResponse{
		Agents: agents,
	}, nil
}

// GetAgentMetrics returns current metrics for an agent
func (s *Server) GetAgentMetrics(ctx context.Context, req *pb.GetAgentMetricsRequest) (*pb.Metrics, error) {
	metrics := s.metricsService.GetCurrentMetrics(req.AgentId)
	if metrics == nil {
		return nil, fmt.Errorf("no metrics available for agent: %s", req.AgentId)
	}

	return convertServiceMetrics(metrics), nil
}

// SendCommand sends a command to an agent from dashboard
func (s *Server) SendCommand(ctx context.Context, req *pb.DashboardCommandRequest) (*pb.CommandResult, error) {
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

	// Send command to agent via stream
	select {
	case agent.commandChan <- req.Command:
		return &pb.CommandResult{
			CommandId: req.Command.CommandId,
			Success:   true,
			Output:    "Command sent to agent",
		}, nil
	default:
		return &pb.CommandResult{
			CommandId: req.Command.CommandId,
			Success:   false,
			Error:     "Command channel full",
		}, nil
	}
}

// ============== Helper Functions ==============

func (s *Server) agentToProto(agent *GrpcAgent) *pb.AgentInfoResponse {
	return &pb.AgentInfoResponse{
		AgentId:         agent.AgentID,
		Hostname:        agent.Hostname,
		Os:              agent.OS,
		Arch:            agent.Arch,
		Version:         agent.Version,
		PermissionLevel: agent.PermissionLevel,
		ConnectedAt:     uint64(agent.ConnectedAt.UnixMilli()),
		LastMetricsAt:   uint64(agent.LastMetricsAt.UnixMilli()),
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

	select {
	case agent.commandChan <- cmd:
		return nil
	default:
		return fmt.Errorf("command channel full for agent: %s", agentID)
	}
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

func convertRealtimeMetrics(r *pb.RealtimeMetrics) *RealtimeData {
	if r == nil {
		return nil
	}

	data := &RealtimeData{
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

// PeriodicData holds periodic data for merging
type PeriodicData struct {
	DiskUsage      []service.DiskData
	UserSessions   []service.UserSession
	NetworkUpdates []service.NetData
}

func convertPeriodicData(p *pb.PeriodicData) *PeriodicData {
	if p == nil {
		return nil
	}

	data := &PeriodicData{}

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

	return data
}
