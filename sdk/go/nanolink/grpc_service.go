package nanolink

import (
	"context"
	"fmt"
	"io"
	"log"
	"strings"
	"sync"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/keepalive"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"

	pb "github.com/chenqi92/NanoLink/sdk/go/nanolink/proto"
)

// AgentStream holds a stream and its associated agent
type AgentStream struct {
	Stream   pb.NanoLinkService_StreamMetricsServer
	Agent    *AgentConnection
	IsActive bool // Track if stream is still active
}

// NanoLinkServicer implements the NanoLinkService gRPC server
type NanoLinkServicer struct {
	pb.UnimplementedNanoLinkServiceServer

	server         *Server
	tokenValidator TokenValidator
	streamAgents   map[interface{}]*AgentConnection
	agentStreams   map[string]*AgentStream // agentID -> stream
	hostnameIndex  map[string]string       // hostname -> agentID for quick lookup
	mu             sync.RWMutex
}

// NewNanoLinkServicer creates a new gRPC servicer
func NewNanoLinkServicer(server *Server) *NanoLinkServicer {
	return &NanoLinkServicer{
		server:         server,
		tokenValidator: server.config.TokenValidator,
		streamAgents:   make(map[interface{}]*AgentConnection),
		agentStreams:   make(map[string]*AgentStream),
		hostnameIndex:  make(map[string]string),
	}
}

// cleanupAgent safely removes an agent from all internal maps
func (s *NanoLinkServicer) cleanupAgent(agent *AgentConnection, stream interface{}) {
	if agent == nil {
		return
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	// Mark stream as inactive
	if agentStream, ok := s.agentStreams[agent.AgentID]; ok {
		agentStream.IsActive = false
	}

	// Remove from all maps
	delete(s.streamAgents, stream)
	delete(s.agentStreams, agent.AgentID)
	delete(s.hostnameIndex, agent.Hostname)
}

// registerAgentStream registers an agent and its stream
func (s *NanoLinkServicer) registerAgentStream(agent *AgentConnection, stream pb.NanoLinkService_StreamMetricsServer) {
	// Wire the command/data-request sender so SendCommand and SendDataRequest can
	// reach this agent over its bidirectional stream.
	agent.SetStreamSend(func(msg interface{}) error {
		resp, ok := msg.(*pb.MetricsStreamResponse)
		if !ok {
			return fmt.Errorf("unexpected stream message type %T", msg)
		}
		return stream.Send(resp)
	})

	s.mu.Lock()
	defer s.mu.Unlock()

	s.streamAgents[stream] = agent
	s.agentStreams[agent.AgentID] = &AgentStream{
		Stream:   stream,
		Agent:    agent,
		IsActive: true,
	}
	s.hostnameIndex[agent.Hostname] = agent.AgentID
}

// getAgentStreamByHostname returns the agent stream for a hostname
func (s *NanoLinkServicer) getAgentStreamByHostname(hostname string) (*AgentStream, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if agentID, ok := s.hostnameIndex[hostname]; ok {
		if stream, ok := s.agentStreams[agentID]; ok {
			return stream, true
		}
	}
	return nil, false
}

// Authenticate handles agent authentication
func (s *NanoLinkServicer) Authenticate(ctx context.Context, req *pb.AuthRequest) (*pb.AuthResponse, error) {
	// Sanitize agent-controlled fields before they reach any log line to prevent
	// log injection (CRLF / control chars forging audit entries).
	hostname := SanitizeHostname(req.Hostname)
	version := SanitizeString(req.AgentVersion)
	log.Printf("Authentication request from: %s (%s)", hostname, version)

	result := s.tokenValidator(req.Token)

	if result.Valid {
		// Check for existing agent with same hostname - handle gracefully
		if existingStream, ok := s.getAgentStreamByHostname(hostname); ok {
			// Check if existing connection is still active
			if existingStream.IsActive && existingStream.Agent != nil {
				// Check heartbeat age - if recent, this might be a duplicate
				if existingStream.Agent.HeartbeatAge() < 30*time.Second {
					log.Printf("WARNING: Agent %s attempting reconnect while existing connection is active (heartbeat age: %v)",
						hostname, existingStream.Agent.HeartbeatAge())
				}
			}
			// Clean up old connection (the new request passed token validation, so
			// this is an authenticated takeover).
			existingStream.Agent.Close()
			s.server.unregisterAgent(existingStream.Agent)
			s.cleanupAgent(existingStream.Agent, existingStream.Stream)
			log.Printf("Replaced stale agent connection for hostname: %s", hostname)
		}

		// Create agent connection
		agent := NewAgentConnectionFromGRPC(
			hostname,
			req.Os,
			req.Arch,
			version,
			result.PermissionLevel,
		)
		agentID := agent.AgentID

		s.server.registerAgent(agent)
		log.Printf("Agent authenticated: %s (%s) with permission level %d",
			hostname, agentID, result.PermissionLevel)

		return &pb.AuthResponse{
			Success:         true,
			PermissionLevel: int32(result.PermissionLevel),
		}, nil
	}

	log.Printf("Authentication failed for: %s", hostname)
	errMsg := result.ErrorMessage
	if errMsg == "" {
		errMsg = "Invalid token"
	}
	return &pb.AuthResponse{
		Success:      false,
		ErrorMessage: errMsg,
	}, nil
}

// authenticateStream validates the bearer credential attached to the gRPC
// stream metadata. The agent already sends this metadata on StreamMetrics;
// validating it here closes the gap where the unary Authenticate call and the
// subsequent stream were otherwise unrelated connections.
func (s *NanoLinkServicer) authenticateStream(ctx context.Context) (ValidationResult, bool, error) {
	md, ok := metadata.FromIncomingContext(ctx)
	if !ok {
		return ValidationResult{}, false, nil
	}
	values := md.Get("authorization")
	if len(values) == 0 {
		return ValidationResult{}, false, nil
	}
	parts := strings.SplitN(strings.TrimSpace(values[0]), " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "bearer") || parts[1] == "" {
		return ValidationResult{}, false, fmt.Errorf("invalid authorization metadata")
	}
	result := s.tokenValidator(parts[1])
	if !result.Valid {
		message := result.ErrorMessage
		if message == "" {
			message = "invalid token"
		}
		return result, false, fmt.Errorf("%s", message)
	}
	return result, true, nil
}

// StreamMetrics handles bidirectional metrics streaming
func (s *NanoLinkServicer) StreamMetrics(stream pb.NanoLinkService_StreamMetricsServer) error {
	log.Printf("New metrics stream connection")

	authResult, authenticated, authErr := s.authenticateStream(stream.Context())
	if authErr != nil {
		return status.Error(codes.Unauthenticated, authErr.Error())
	}
	if s.server.config.RequireAuthentication && !authenticated {
		return status.Error(codes.Unauthenticated, "bearer token required")
	}
	streamPermission := PermissionReadOnly
	if authenticated {
		streamPermission = authResult.PermissionLevel
	}

	var agent *AgentConnection
	var agentID string

	// Send initial heartbeat ack to establish stream
	if err := stream.Send(&pb.MetricsStreamResponse{
		Response: &pb.MetricsStreamResponse_HeartbeatAck{
			HeartbeatAck: &pb.HeartbeatAck{
				Timestamp: uint64(time.Now().UnixMilli()),
			},
		},
	}); err != nil {
		return err
	}
	log.Printf("Sent initial heartbeat ack")

	defer func() {
		if agent != nil {
			agent.Close()
			s.server.unregisterAgent(agent)
			s.cleanupAgent(agent, stream)
			log.Printf("Agent disconnected: %s (%s)", agent.Hostname, agentID)
		}
	}()

	for {
		req, err := stream.Recv()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			log.Printf("Stream error: %v", err)
			return err
		}

		switch payload := req.Request.(type) {
		case *pb.MetricsStreamRequest_Metrics:
			protoMetrics := payload.Metrics

			// Register agent from first metrics
			if agent == nil {
				hostname := SanitizeHostname(protoMetrics.Hostname)

				// Check for existing agent with same hostname
				if existingStream, ok := s.getAgentStreamByHostname(hostname); ok {
					// Security: an unauthenticated metrics stream must NOT be able
					// to evict a live connection by reusing its hostname — that
					// would let anyone disconnect/hijack an active (possibly
					// authenticated) agent. Only take over a connection that is
					// already stale; reject otherwise.
					if existingStream.IsActive && existingStream.Agent != nil &&
						existingStream.Agent.HeartbeatAge() < s.server.config.HeartbeatTimeout {
						log.Printf("SECURITY: refusing unauthenticated stream takeover of active connection for hostname %s (heartbeat age: %v)",
							hostname, existingStream.Agent.HeartbeatAge())
						return fmt.Errorf("a connection for this host is already active")
					}
					existingStream.Agent.Close()
					s.server.unregisterAgent(existingStream.Agent)
					s.cleanupAgent(existingStream.Agent, existingStream.Stream)
					log.Printf("Replacing stale agent for hostname: %s", hostname)
				}

				osName := ""
				arch := ""
				if protoMetrics.SystemInfo != nil {
					osName = protoMetrics.SystemInfo.OsName
				}
				if protoMetrics.Cpu != nil {
					arch = protoMetrics.Cpu.Architecture
				}

				agent = NewAgentConnectionFromGRPC(hostname, osName, arch, "0.2.0", streamPermission)
				agentID = agent.AgentID
				if authenticated {
					log.Printf("Agent %s registered via authenticated metrics stream with permission %d", hostname, streamPermission)
				} else {
					log.Printf("WARNING: Agent %s registered via anonymous metrics stream with READ_ONLY permission", hostname)
				}
				s.server.registerAgent(agent)
				s.registerAgentStream(agent, stream)
				log.Printf("Agent registered from metrics: %s (%s)", hostname, agentID)
			}

			// Convert and handle metrics
			sdkMetrics := s.convertMetrics(protoMetrics)
			sdkMetrics.Hostname = agent.Hostname
			s.server.handleMetrics(sdkMetrics)

		case *pb.MetricsStreamRequest_Heartbeat:
			if agent != nil {
				agent.UpdateHeartbeat()
			}
			// Send heartbeat ack. Once the agent is registered its sender is wired,
			// so route through it to stay serialized with command/data-request sends.
			ack := &pb.MetricsStreamResponse{
				Response: &pb.MetricsStreamResponse_HeartbeatAck{
					HeartbeatAck: &pb.HeartbeatAck{
						Timestamp: uint64(time.Now().UnixMilli()),
					},
				},
			}
			var ackErr error
			if agent != nil {
				ackErr = agent.sendOnStream(ack)
			} else {
				ackErr = stream.Send(ack)
			}
			if ackErr != nil {
				return ackErr
			}

		case *pb.MetricsStreamRequest_Realtime:
			protoRealtime := payload.Realtime
			if agent != nil {
				sdkRealtime := s.convertRealtimeMetrics(protoRealtime)
				sdkRealtime.Hostname = agent.Hostname
				s.server.handleRealtimeMetrics(sdkRealtime)
			}

		case *pb.MetricsStreamRequest_StaticInfo:
			protoStatic := payload.StaticInfo

			// Register agent from static info if not already registered
			if agent == nil && protoStatic.SystemInfo != nil {
				hostname := SanitizeHostname(protoStatic.SystemInfo.Hostname)
				if hostname != "" {
					// Check for existing agent with same hostname
					if existingStream, ok := s.getAgentStreamByHostname(hostname); ok {
						if existingStream.IsActive && existingStream.Agent != nil {
							if existingStream.Agent.HeartbeatAge() < 30*time.Second {
								log.Printf("WARNING: Agent %s static info while existing is active (heartbeat age: %v)",
									hostname, existingStream.Agent.HeartbeatAge())
							}
						}
						existingStream.Agent.Close()
						s.server.unregisterAgent(existingStream.Agent)
						s.cleanupAgent(existingStream.Agent, existingStream.Stream)
					}

					arch := ""
					if protoStatic.Cpu != nil {
						arch = protoStatic.Cpu.Architecture
					}

					agent = NewAgentConnectionFromGRPC(
						hostname,
						protoStatic.SystemInfo.OsName,
						arch,
						getVersionOrDefault(protoStatic.AgentVersion),
						streamPermission,
					)
					agentID = agent.AgentID
					if authenticated {
						log.Printf("Agent %s registered via authenticated static-info stream with permission %d", hostname, streamPermission)
					} else {
						log.Printf("WARNING: Agent %s registered via anonymous static-info stream with READ_ONLY permission", hostname)
					}
					s.server.registerAgent(agent)
					s.registerAgentStream(agent, stream)
					log.Printf("Agent registered from static info: %s (%s)", hostname, agentID)
				}
			}

			if agent != nil {
				sdkStatic := s.convertStaticInfo(protoStatic)
				sdkStatic.Hostname = agent.Hostname
				s.server.handleStaticInfo(sdkStatic)
			}

		case *pb.MetricsStreamRequest_Periodic:
			protoPeriodic := payload.Periodic
			if agent != nil {
				sdkPeriodic := s.convertPeriodicData(protoPeriodic)
				sdkPeriodic.Hostname = agent.Hostname
				s.server.handlePeriodicData(sdkPeriodic)
			}

		case *pb.MetricsStreamRequest_CommandResult:
			result := payload.CommandResult
			// Route the result back to the pending SendCommand/ExecuteCommand caller.
			if agent != nil {
				agent.HandleCommandResult(result.CommandId, convertCommandResult(result))
			}
			log.Printf("Command result: %s success=%v", result.CommandId, result.Success)
		}
	}
}

// ReportMetrics handles one-time metrics report
func (s *NanoLinkServicer) ReportMetrics(ctx context.Context, req *pb.Metrics) (*pb.MetricsAck, error) {
	log.Printf("Received one-time metrics from: %s", req.Hostname)

	sdkMetrics := s.convertMetrics(req)
	s.server.handleMetrics(sdkMetrics)

	return &pb.MetricsAck{
		Success:   true,
		Timestamp: uint64(time.Now().UnixMilli()),
	}, nil
}

// Heartbeat handles heartbeat requests
func (s *NanoLinkServicer) Heartbeat(ctx context.Context, req *pb.HeartbeatRequest) (*pb.HeartbeatResponse, error) {
	log.Printf("Heartbeat from agent: %s", req.AgentId)

	return &pb.HeartbeatResponse{
		ServerTimestamp: uint64(time.Now().UnixMilli()),
		ConfigChanged:   false,
	}, nil
}

// ExecuteCommand dispatches a command to a connected agent and waits for its
// result. Since the unary Command message carries no agent identifier, the
// target is resolved from params["agent_id"] or params["hostname"]; if neither
// is set and exactly one agent is connected, that agent is used.
func (s *NanoLinkServicer) ExecuteCommand(ctx context.Context, req *pb.Command) (*pb.CommandResult, error) {
	log.Printf("Execute command: %s type=%v", req.CommandId, req.Type)

	agent := s.locateAgentForCommand(req)
	if agent == nil {
		return &pb.CommandResult{
			CommandId: req.CommandId,
			Success:   false,
			Error:     "no target agent: set params[\"agent_id\"] or params[\"hostname\"], or connect exactly one agent",
		}, nil
	}

	result, err := agent.SendCommand(CommandFromProto(req))
	if err != nil {
		return &pb.CommandResult{
			CommandId: req.CommandId,
			Success:   false,
			Error:     err.Error(),
		}, nil
	}

	out := commandResultToProto(result)
	if out.CommandId == "" {
		out.CommandId = req.CommandId
	}
	return out, nil
}

// locateAgentForCommand resolves the target agent for a unary ExecuteCommand.
func (s *NanoLinkServicer) locateAgentForCommand(req *pb.Command) *AgentConnection {
	if req.Params != nil {
		if id := req.Params["agent_id"]; id != "" {
			if a := s.server.GetAgent(id); a != nil {
				return a
			}
		}
		if h := req.Params["hostname"]; h != "" {
			if a := s.server.GetAgentByHostname(h); a != nil {
				return a
			}
		}
	}
	agents := s.server.GetAgents()
	if len(agents) == 1 {
		for _, a := range agents {
			return a
		}
	}
	return nil
}

// SyncMetrics handles metrics sync requests
func (s *NanoLinkServicer) SyncMetrics(ctx context.Context, req *pb.MetricsSyncRequest) (*pb.MetricsSyncResponse, error) {
	log.Printf("Metrics sync request from: %s", req.AgentId)

	return &pb.MetricsSyncResponse{
		Success:         true,
		ServerTimestamp: uint64(time.Now().UnixMilli()),
	}, nil
}

// GetAgentInfo returns agent information
func (s *NanoLinkServicer) GetAgentInfo(ctx context.Context, req *pb.AgentInfoRequest) (*pb.AgentInfoResponse, error) {
	log.Printf("Get agent info: %s", req.AgentId)

	agent := s.server.GetAgent(req.AgentId)
	if agent != nil {
		return &pb.AgentInfoResponse{
			AgentId:         agent.AgentID,
			Hostname:        agent.Hostname,
			Os:              agent.OS,
			Arch:            agent.Arch,
			Version:         agent.Version,
			PermissionLevel: int32(agent.PermissionLevel),
			ConnectedAt:     uint64(agent.ConnectedAt.UnixMilli()),
			LastMetricsAt:   uint64(agent.LastHeartbeat.UnixMilli()),
		}, nil
	}

	return &pb.AgentInfoResponse{AgentId: req.AgentId}, nil
}

// CreateGRPCServer creates a gRPC server with the NanoLink servicer.
// extraOpts (e.g. grpc.Creds for TLS) are appended to the base options.
func CreateGRPCServer(servicer *NanoLinkServicer, extraOpts ...grpc.ServerOption) *grpc.Server {
	opts := []grpc.ServerOption{
		grpc.KeepaliveParams(keepalive.ServerParameters{
			Time:    30 * time.Second,
			Timeout: 10 * time.Second,
		}),
		grpc.KeepaliveEnforcementPolicy(keepalive.EnforcementPolicy{
			MinTime:             10 * time.Second,
			PermitWithoutStream: true,
		}),
		grpc.MaxRecvMsgSize(16 * 1024 * 1024), // 16MB max receive message size
		grpc.MaxSendMsgSize(16 * 1024 * 1024), // 16MB max send message size
	}
	opts = append(opts, extraOpts...)
	server := grpc.NewServer(opts...)
	pb.RegisterNanoLinkServiceServer(server, servicer)
	return server
}

// SendDataRequest sends a data request to a specific agent
// requestType should be one of: pb.DataRequestType_DATA_REQUEST_FULL, DATA_REQUEST_STATIC, etc.
func (s *NanoLinkServicer) SendDataRequest(agentID string, requestType pb.DataRequestType, target string) bool {
	s.mu.RLock()
	agentStream, exists := s.agentStreams[agentID]
	s.mu.RUnlock()

	if !exists {
		log.Printf("Agent %s not found for data request", agentID)
		return false
	}

	if !agentStream.IsActive {
		log.Printf("Agent %s stream is not active", agentID)
		return false
	}

	request := &pb.DataRequest{
		RequestType: requestType,
		Target:      target,
	}

	err := agentStream.Agent.sendOnStream(&pb.MetricsStreamResponse{
		Response: &pb.MetricsStreamResponse_DataRequest{
			DataRequest: request,
		},
	})

	if err != nil {
		log.Printf("Failed to send data request to agent %s: %v", agentID, err)
		// Mark stream as inactive
		s.mu.Lock()
		agentStream.IsActive = false
		s.mu.Unlock()
		return false
	}

	log.Printf("Sent data request %v to agent %s", requestType, agentID)
	return true
}

// BroadcastDataRequest sends a data request to all connected agents
func (s *NanoLinkServicer) BroadcastDataRequest(requestType pb.DataRequestType) {
	s.mu.RLock()
	streams := make([]*AgentStream, 0, len(s.agentStreams))
	for _, stream := range s.agentStreams {
		if stream.IsActive {
			streams = append(streams, stream)
		}
	}
	s.mu.RUnlock()

	request := &pb.DataRequest{
		RequestType: requestType,
	}

	response := &pb.MetricsStreamResponse{
		Response: &pb.MetricsStreamResponse_DataRequest{
			DataRequest: request,
		},
	}

	successCount := 0
	var failedAgents []*AgentStream
	for _, agentStream := range streams {
		if err := agentStream.Agent.sendOnStream(response); err == nil {
			successCount++
		} else {
			log.Printf("Failed to send broadcast to agent %s: %v", agentStream.Agent.Hostname, err)
			failedAgents = append(failedAgents, agentStream)
		}
	}

	// Mark failed streams as inactive (they will be cleaned up by their defer)
	if len(failedAgents) > 0 {
		s.mu.Lock()
		for _, agentStream := range failedAgents {
			agentStream.IsActive = false
		}
		s.mu.Unlock()
	}

	log.Printf("Broadcast data request %v to %d/%d agents", requestType, successCount, len(streams))
}

// Conversion functions

func (s *NanoLinkServicer) convertMetrics(proto *pb.Metrics) *Metrics {
	metrics := &Metrics{
		Timestamp:   int64(proto.Timestamp),
		Hostname:    proto.Hostname,
		LoadAverage: proto.LoadAverage,
	}

	if proto.Cpu != nil {
		metrics.CPU = &CPUMetrics{
			UsagePercent: proto.Cpu.UsagePercent,
			CoreCount:    int(proto.Cpu.CoreCount),
			Model:        proto.Cpu.Model,
			Vendor:       proto.Cpu.Vendor,
			FrequencyMHz: proto.Cpu.FrequencyMhz,
			Temperature:  proto.Cpu.Temperature,
			PerCoreUsage: proto.Cpu.PerCoreUsage,
		}
	}

	if proto.Memory != nil {
		metrics.Memory = &MemoryMetrics{
			Total:     proto.Memory.Total,
			Used:      proto.Memory.Used,
			Available: proto.Memory.Available,
			SwapTotal: proto.Memory.SwapTotal,
			SwapUsed:  proto.Memory.SwapUsed,
		}
	}

	for _, d := range proto.Disks {
		metrics.Disks = append(metrics.Disks, DiskMetrics{
			MountPoint:       d.MountPoint,
			Device:           d.Device,
			FSType:           d.FsType,
			Total:            d.Total,
			Used:             d.Used,
			Available:        d.Available,
			ReadBytesPerSec:  d.ReadBytesSec,
			WriteBytesPerSec: d.WriteBytesSec,
			Model:            d.Model,
			DiskType:         d.DiskType,
			Temperature:      d.Temperature,
		})
	}

	for _, n := range proto.Networks {
		metrics.Networks = append(metrics.Networks, NetworkMetrics{
			Interface:       n.Interface,
			RxBytesPerSec:   n.RxBytesSec,
			TxBytesPerSec:   n.TxBytesSec,
			RxPacketsPerSec: n.RxPacketsSec,
			TxPacketsPerSec: n.TxPacketsSec,
			IsUp:            n.IsUp,
			MacAddress:      n.MacAddress,
			IPAddresses:     n.IpAddresses,
			SpeedMbps:       n.SpeedMbps,
		})
	}

	for _, g := range proto.Gpus {
		metrics.GPUs = append(metrics.GPUs, GPUMetrics{
			Index:           g.Index,
			Name:            g.Name,
			Vendor:          g.Vendor,
			UsagePercent:    g.UsagePercent,
			MemoryTotal:     g.MemoryTotal,
			MemoryUsed:      g.MemoryUsed,
			Temperature:     g.Temperature,
			FanSpeedPercent: g.FanSpeedPercent,
			PowerWatts:      g.PowerWatts,
			ClockCoreMHz:    g.ClockCoreMhz,
			ClockMemoryMHz:  g.ClockMemoryMhz,
			DriverVersion:   g.DriverVersion,
			EncoderUsage:    g.EncoderUsage,
			DecoderUsage:    g.DecoderUsage,
		})
	}

	if proto.SystemInfo != nil {
		metrics.SystemInfo = &SystemInfo{
			OSName:            proto.SystemInfo.OsName,
			OSVersion:         proto.SystemInfo.OsVersion,
			KernelVersion:     proto.SystemInfo.KernelVersion,
			Hostname:          proto.SystemInfo.Hostname,
			BootTime:          proto.SystemInfo.BootTime,
			UptimeSeconds:     proto.SystemInfo.UptimeSeconds,
			MotherboardModel:  proto.SystemInfo.MotherboardModel,
			MotherboardVendor: proto.SystemInfo.MotherboardVendor,
			BIOSVersion:       proto.SystemInfo.BiosVersion,
		}
	}

	for _, sess := range proto.UserSessions {
		metrics.UserSessions = append(metrics.UserSessions, UserSession{
			Username:    sess.Username,
			TTY:         sess.Tty,
			LoginTime:   sess.LoginTime,
			RemoteHost:  sess.RemoteHost,
			IdleSeconds: sess.IdleSeconds,
			SessionType: sess.SessionType,
		})
	}

	for _, n := range proto.Npus {
		metrics.NPUs = append(metrics.NPUs, NPUMetrics{
			Index:         n.Index,
			Name:          n.Name,
			Vendor:        n.Vendor,
			UsagePercent:  n.UsagePercent,
			MemoryTotal:   n.MemoryTotal,
			MemoryUsed:    n.MemoryUsed,
			Temperature:   n.Temperature,
			PowerWatts:    n.PowerWatts,
			DriverVersion: n.DriverVersion,
		})
	}

	return metrics
}

func (s *NanoLinkServicer) convertRealtimeMetrics(proto *pb.RealtimeMetrics) *RealtimeMetrics {
	realtime := &RealtimeMetrics{
		Timestamp:      int64(proto.Timestamp),
		CPUUsage:       proto.CpuUsagePercent,
		CPUTemperature: proto.CpuTemperature,
		MemoryUsed:     proto.MemoryUsed,
		SwapUsed:       proto.SwapUsed,
		CPUPerCore:     proto.CpuPerCore,
		LoadAverage:    proto.LoadAverage,
	}

	for _, d := range proto.DiskIo {
		realtime.DiskIO = append(realtime.DiskIO, DiskIO{
			Device:           d.Device,
			ReadBytesPerSec:  d.ReadBytesSec,
			WriteBytesPerSec: d.WriteBytesSec,
		})
	}

	for _, n := range proto.NetworkIo {
		realtime.NetworkIO = append(realtime.NetworkIO, NetworkIO{
			Interface:     n.Interface,
			RxBytesPerSec: n.RxBytesSec,
			TxBytesPerSec: n.TxBytesSec,
		})
	}

	for _, g := range proto.GpuUsage {
		realtime.GPUUsages = append(realtime.GPUUsages, GPUUsage{
			Index:        g.Index,
			UsagePercent: g.UsagePercent,
			MemoryUsed:   g.MemoryUsed,
			Temperature:  g.Temperature,
		})
	}

	for _, n := range proto.NpuUsage {
		realtime.NPUUsages = append(realtime.NPUUsages, NPUUsage{
			Index:        n.Index,
			UsagePercent: n.UsagePercent,
			MemoryUsed:   n.MemoryUsed,
			Temperature:  n.Temperature,
		})
	}

	return realtime
}

func (s *NanoLinkServicer) convertStaticInfo(proto *pb.StaticInfo) *StaticInfo {
	static := &StaticInfo{
		Timestamp: int64(proto.Timestamp),
	}

	if proto.Cpu != nil {
		static.CPU = &CPUStaticInfo{
			Model:        proto.Cpu.Model,
			Vendor:       proto.Cpu.Vendor,
			Cores:        int(proto.Cpu.PhysicalCores),
			Threads:      int(proto.Cpu.LogicalCores),
			FrequencyMHz: proto.Cpu.FrequencyMaxMhz,
			Architecture: proto.Cpu.Architecture,
		}
	}

	if proto.Memory != nil {
		static.Memory = &MemoryStaticInfo{
			TotalPhysical: proto.Memory.Total,
			TotalSwap:     proto.Memory.SwapTotal,
			MemoryType:    proto.Memory.MemoryType,
			SpeedMHz:      proto.Memory.MemorySpeedMhz,
			Slots:         proto.Memory.MemorySlots,
		}
	}

	for _, d := range proto.Disks {
		static.Disks = append(static.Disks, DiskStaticInfo{
			Device:     d.Device,
			MountPoint: d.MountPoint,
			FSType:     d.FsType,
			Model:      d.Model,
			Serial:     d.Serial,
			Type:       d.DiskType,
			Total:      d.TotalBytes,
		})
	}

	for _, n := range proto.Networks {
		static.Networks = append(static.Networks, NetworkStaticInfo{
			Interface:  n.Interface,
			MacAddress: n.MacAddress,
			SpeedMbps:  n.SpeedMbps,
			Type:       n.InterfaceType,
			IPAddress:  n.IpAddresses,
		})
	}

	for _, g := range proto.Gpus {
		static.GPUs = append(static.GPUs, GPUStaticInfo{
			Index:         g.Index,
			Name:          g.Name,
			Vendor:        g.Vendor,
			MemoryTotal:   g.MemoryTotal,
			DriverVersion: g.DriverVersion,
		})
	}

	for _, n := range proto.Npus {
		static.NPUs = append(static.NPUs, NPUStaticInfo{
			Index:         n.Index,
			Name:          n.Name,
			Vendor:        n.Vendor,
			MemoryTotal:   n.MemoryTotal,
			DriverVersion: n.DriverVersion,
		})
	}

	if proto.SystemInfo != nil {
		static.OSName = proto.SystemInfo.OsName
		static.OSVersion = proto.SystemInfo.OsVersion
		static.KernelVersion = proto.SystemInfo.KernelVersion
		static.BootTime = proto.SystemInfo.BootTime
		static.MotherboardModel = proto.SystemInfo.MotherboardModel
		static.MotherboardVendor = proto.SystemInfo.MotherboardVendor
		static.BIOSVersion = proto.SystemInfo.BiosVersion
		static.Hostname = proto.SystemInfo.Hostname
	}

	return static
}

func (s *NanoLinkServicer) convertPeriodicData(proto *pb.PeriodicData) *PeriodicData {
	periodic := &PeriodicData{
		Timestamp: int64(proto.Timestamp),
	}

	for _, d := range proto.DiskUsage {
		periodic.DiskUsage = append(periodic.DiskUsage, DiskUsage{
			MountPoint: d.MountPoint,
			Used:       d.Used,
			Available:  d.Available,
		})
	}

	for _, n := range proto.NetworkUpdates {
		periodic.NetworkAddress = append(periodic.NetworkAddress, NetworkAddressUpdate{
			Interface:   n.Interface,
			IPAddresses: n.IpAddresses,
		})
	}

	for _, s := range proto.UserSessions {
		periodic.UserSessions = append(periodic.UserSessions, UserSession{
			Username:    s.Username,
			TTY:         s.Tty,
			LoginTime:   s.LoginTime,
			RemoteHost:  s.RemoteHost,
			IdleSeconds: s.IdleSeconds,
			SessionType: s.SessionType,
		})
	}

	return periodic
}

// getVersionOrDefault returns the version or "unknown" if empty
func getVersionOrDefault(version string) string {
	if version == "" {
		return "unknown"
	}
	return version
}

// convertCommandResult converts a protobuf CommandResult into the SDK type.
func convertCommandResult(p *pb.CommandResult) *CommandResult {
	if p == nil {
		return &CommandResult{}
	}
	r := &CommandResult{
		CommandID:   p.GetCommandId(),
		Success:     p.GetSuccess(),
		Output:      p.GetOutput(),
		Error:       p.GetError(),
		FileContent: p.GetFileContent(),
	}
	for _, pi := range p.GetProcesses() {
		r.Processes = append(r.Processes, ProcessInfo{
			PID:         int(pi.GetPid()),
			Name:        pi.GetName(),
			User:        pi.GetUser(),
			CPUPercent:  pi.GetCpuPercent(),
			MemoryBytes: pi.GetMemoryBytes(),
			Status:      pi.GetStatus(),
			StartTime:   int64(pi.GetStartTime()),
		})
	}
	for _, ci := range p.GetContainers() {
		r.Containers = append(r.Containers, ContainerInfo{
			ID:      ci.GetId(),
			Name:    ci.GetName(),
			Image:   ci.GetImage(),
			Status:  ci.GetStatus(),
			State:   ci.GetState(),
			Created: int64(ci.GetCreated()),
		})
	}
	return r
}

// commandResultToProto converts an SDK CommandResult into its protobuf form.
func commandResultToProto(r *CommandResult) *pb.CommandResult {
	if r == nil {
		return &pb.CommandResult{}
	}
	p := &pb.CommandResult{
		CommandId:   r.CommandID,
		Success:     r.Success,
		Output:      r.Output,
		Error:       r.Error,
		FileContent: r.FileContent,
	}
	for _, pi := range r.Processes {
		p.Processes = append(p.Processes, &pb.ProcessInfo{
			Pid:         uint32(pi.PID),
			Name:        pi.Name,
			User:        pi.User,
			CpuPercent:  pi.CPUPercent,
			MemoryBytes: pi.MemoryBytes,
			Status:      pi.Status,
			StartTime:   uint64(pi.StartTime),
		})
	}
	for _, ci := range r.Containers {
		p.Containers = append(p.Containers, &pb.ContainerInfo{
			Id:      ci.ID,
			Name:    ci.Name,
			Image:   ci.Image,
			Status:  ci.Status,
			State:   ci.State,
			Created: uint64(ci.Created),
		})
	}
	return p
}
