package nanolink

import (
	"context"
	"fmt"
	"io"
	"log"
	"sync"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/keepalive"

	pb "github.com/chenqi92/NanoLink/sdk/go/nanolink/proto"
)

// AgentStream holds a stream and its associated agent
type AgentStream struct {
	Stream pb.NanoLinkService_StreamMetricsServer
	Agent  *AgentConnection
}

// NanoLinkServicer implements the NanoLinkService gRPC server
type NanoLinkServicer struct {
	pb.UnimplementedNanoLinkServiceServer

	server         *Server
	tokenValidator TokenValidator
	streamAgents   map[interface{}]*AgentConnection
	agentStreams   map[string]*AgentStream // agentID -> stream
	mu             sync.RWMutex
}

// NewNanoLinkServicer creates a new gRPC servicer
func NewNanoLinkServicer(server *Server) *NanoLinkServicer {
	return &NanoLinkServicer{
		server:         server,
		tokenValidator: server.config.TokenValidator,
		streamAgents:   make(map[interface{}]*AgentConnection),
		agentStreams:   make(map[string]*AgentStream),
	}
}

// Authenticate handles agent authentication
func (s *NanoLinkServicer) Authenticate(ctx context.Context, req *pb.AuthRequest) (*pb.AuthResponse, error) {
	log.Printf("Authentication request from: %s (%s)", req.Hostname, req.AgentVersion)

	result := s.tokenValidator(req.Token)

	if result.Valid {
		// Check for existing agent with same hostname
		existing := s.server.GetAgentByHostname(req.Hostname)
		if existing != nil {
			s.server.unregisterAgent(existing)
			log.Printf("Replacing stale agent connection for hostname: %s", req.Hostname)
		}

		// Create agent connection
		agent := NewAgentConnectionFromGRPC(
			req.Hostname,
			req.Os,
			req.Arch,
			req.AgentVersion,
			result.PermissionLevel,
		)
		agentID := agent.AgentID

		s.server.registerAgent(agent)
		log.Printf("Agent authenticated: %s (%s) with permission level %d",
			req.Hostname, agentID, result.PermissionLevel)

		return &pb.AuthResponse{
			Success:         true,
			PermissionLevel: int32(result.PermissionLevel),
		}, nil
	}

	log.Printf("Authentication failed for: %s", req.Hostname)
	errMsg := result.ErrorMessage
	if errMsg == "" {
		errMsg = "Invalid token"
	}
	return &pb.AuthResponse{
		Success:      false,
		ErrorMessage: errMsg,
	}, nil
}

// StreamMetrics handles bidirectional metrics streaming
func (s *NanoLinkServicer) StreamMetrics(stream pb.NanoLinkService_StreamMetricsServer) error {
	log.Printf("New metrics stream connection")

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
			s.server.unregisterAgent(agent)
			s.mu.Lock()
			delete(s.streamAgents, stream)
			delete(s.agentStreams, agentID)
			s.mu.Unlock()
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
				// P0-3: 强制认证模式检查
				if s.server.config.RequireAuthentication {
					log.Printf("SECURITY: Rejecting unauthenticated metrics stream (RequireAuthentication=true)")
					return fmt.Errorf("authentication required: use Authenticate RPC before streaming metrics")
				}

				hostname := SanitizeHostname(protoMetrics.Hostname)

				// Check for existing agent
				existing := s.server.GetAgentByHostname(hostname)
				if existing != nil {
					s.server.unregisterAgent(existing)
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

				agent = NewAgentConnectionFromGRPC(hostname, osName, arch, "0.2.0", PermissionReadOnly)
				agentID = agent.AgentID
				log.Printf("WARNING: Agent %s registered via stream without authentication - using READ_ONLY permission", hostname)
				s.server.registerAgent(agent)
				s.mu.Lock()
				s.streamAgents[stream] = agent
				s.agentStreams[agentID] = &AgentStream{Stream: stream, Agent: agent}
				s.mu.Unlock()
				log.Printf("Agent registered from metrics: %s (%s)", hostname, agentID)
			}

			// Convert and handle metrics
			sdkMetrics := s.convertMetrics(protoMetrics)
			sdkMetrics.Hostname = agent.Hostname
			s.server.handleMetrics(sdkMetrics)

		case *pb.MetricsStreamRequest_Heartbeat:
			if agent != nil {
				agent.LastHeartbeat = time.Now()
			}
			// Send heartbeat ack
			if err := stream.Send(&pb.MetricsStreamResponse{
				Response: &pb.MetricsStreamResponse_HeartbeatAck{
					HeartbeatAck: &pb.HeartbeatAck{
						Timestamp: uint64(time.Now().UnixMilli()),
					},
				},
			}); err != nil {
				return err
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
					existing := s.server.GetAgentByHostname(hostname)
					if existing != nil {
						s.server.unregisterAgent(existing)
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
						PermissionReadOnly,
					)
					agentID = agent.AgentID
					log.Printf("WARNING: Agent %s registered via static info without authentication - using READ_ONLY permission", hostname)
					s.server.registerAgent(agent)
					s.mu.Lock()
					s.streamAgents[stream] = agent
					s.agentStreams[agentID] = &AgentStream{Stream: stream, Agent: agent}
					s.mu.Unlock()
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

// ExecuteCommand handles command execution (placeholder)
func (s *NanoLinkServicer) ExecuteCommand(ctx context.Context, req *pb.Command) (*pb.CommandResult, error) {
	log.Printf("Execute command: %s type=%v", req.CommandId, req.Type)

	return &pb.CommandResult{
		CommandId: req.CommandId,
		Success:   false,
		Error:     "Command execution through server not yet implemented",
	}, nil
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

// CreateGRPCServer creates a gRPC server with the NanoLink servicer
func CreateGRPCServer(servicer *NanoLinkServicer) *grpc.Server {
	server := grpc.NewServer(
		grpc.KeepaliveParams(keepalive.ServerParameters{
			Time:    30 * time.Second,
			Timeout: 10 * time.Second,
		}),
		grpc.KeepaliveEnforcementPolicy(keepalive.EnforcementPolicy{
			MinTime:             10 * time.Second,
			PermitWithoutStream: true,
		}),
		grpc.MaxRecvMsgSize(16*1024*1024), // 16MB max receive message size
		grpc.MaxSendMsgSize(16*1024*1024), // 16MB max send message size
	)
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

	request := &pb.DataRequest{
		RequestType: requestType,
		Target:      target,
	}

	err := agentStream.Stream.Send(&pb.MetricsStreamResponse{
		Response: &pb.MetricsStreamResponse_DataRequest{
			DataRequest: request,
		},
	})

	if err != nil {
		log.Printf("Failed to send data request to agent %s: %v", agentID, err)
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
		streams = append(streams, stream)
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
	for _, agentStream := range streams {
		if err := agentStream.Stream.Send(response); err == nil {
			successCount++
		}
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
