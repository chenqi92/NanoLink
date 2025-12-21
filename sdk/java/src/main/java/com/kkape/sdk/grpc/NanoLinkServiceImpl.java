package com.kkape.sdk.grpc;

import com.kkape.sdk.AgentConnection;
import com.kkape.sdk.NanoLinkServer;
import com.kkape.sdk.TokenValidator;
import com.kkape.sdk.model.Metrics;
import com.kkape.sdk.model.PeriodicData;
import com.kkape.sdk.model.RealtimeMetrics;
import com.kkape.sdk.model.StaticInfo;
import io.grpc.stub.StreamObserver;
import io.nanolink.proto.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * gRPC service implementation for NanoLink agent communication.
 * Handles authentication, metrics streaming, and command execution.
 */
public class NanoLinkServiceImpl extends NanoLinkServiceGrpc.NanoLinkServiceImplBase {
    private static final Logger log = LoggerFactory.getLogger(NanoLinkServiceImpl.class);

    private final NanoLinkServer server;
    private final TokenValidator tokenValidator;

    // Map of authenticated streams to their agent connections
    private final Map<StreamObserver<?>, AgentConnection> streamAgents = new ConcurrentHashMap<>();

    public NanoLinkServiceImpl(NanoLinkServer server, TokenValidator tokenValidator) {
        this.server = server;
        this.tokenValidator = tokenValidator;
    }

    @Override
    public void authenticate(AuthRequest request, StreamObserver<AuthResponse> responseObserver) {
        log.debug("Authentication request from: {} ({})", request.getHostname(), request.getAgentVersion());

        try {
            TokenValidator.ValidationResult result = tokenValidator.validate(request.getToken());

            if (result.isValid()) {
                // Check if agent with same hostname already exists (reconnection case)
                AgentConnection existingAgent = server.getAgentByHostname(request.getHostname());
                if (existingAgent != null) {
                    server.unregisterAgent(existingAgent);
                    log.info("Replacing stale agent connection for hostname: {}", request.getHostname());
                }

                // Create agent connection
                String agentId = UUID.randomUUID().toString();
                AgentConnection agent = new AgentConnection(
                        agentId,
                        request.getHostname(),
                        request.getOs(),
                        request.getArch(),
                        request.getAgentVersion(),
                        result.getPermissionLevel());

                server.registerAgent(agent);
                log.info("Agent authenticated: {} ({}) with permission level {}",
                        request.getHostname(), agentId, result.getPermissionLevel());

                responseObserver.onNext(AuthResponse.newBuilder()
                        .setSuccess(true)
                        .setPermissionLevel(result.getPermissionLevel())
                        .build());
            } else {
                log.warn("Authentication failed for: {}", request.getHostname());
                responseObserver.onNext(AuthResponse.newBuilder()
                        .setSuccess(false)
                        .setErrorMessage(result.getErrorMessage() != null ? result.getErrorMessage() : "Invalid token")
                        .build());
            }

            responseObserver.onCompleted();
        } catch (Exception e) {
            log.error("Authentication error", e);
            responseObserver.onError(e);
        }
    }

    @Override
    public StreamObserver<MetricsStreamRequest> streamMetrics(
            StreamObserver<MetricsStreamResponse> responseObserver) {

        log.debug("New metrics stream connection");

        // Send initial response immediately to trigger HTTP/2 headers
        // This allows tonic/rust clients to complete the stream_metrics() call
        responseObserver.onNext(MetricsStreamResponse.newBuilder()
                .setHeartbeatAck(HeartbeatAck.newBuilder()
                        .setTimestamp(System.currentTimeMillis())
                        .build())
                .build());
        log.debug("Sent initial heartbeat ack to establish stream");

        return new StreamObserver<MetricsStreamRequest>() {
            private AgentConnection agent = null;
            private String agentId = null;

            @Override
            public void onNext(MetricsStreamRequest request) {
                try {
                    if (request.hasMetrics()) {
                        io.nanolink.proto.Metrics protoMetrics = request.getMetrics();

                        // Register agent on first metrics if not already
                        if (agent == null) {
                            String hostname = protoMetrics.getHostname();

                            // Check if agent with same hostname already exists (reconnection case)
                            AgentConnection existingAgent = server.getAgentByHostname(hostname);
                            if (existingAgent != null) {
                                // Remove stale agent and reuse info
                                server.unregisterAgent(existingAgent);
                                log.info("Replacing stale agent connection for hostname: {}", hostname);
                            }

                            agentId = UUID.randomUUID().toString();
                            agent = new AgentConnection(
                                    agentId,
                                    hostname,
                                    protoMetrics.hasSystemInfo() ? protoMetrics.getSystemInfo().getOsName() : "",
                                    protoMetrics.hasCpu() ? protoMetrics.getCpu().getArchitecture() : "",
                                    "0.2.0",
                                    TokenValidator.PermissionLevel.READ_ONLY // Default to READ_ONLY for unauthenticated
                                                                             // streams
                            );
                            log.warn(
                                    "Agent {} registered via stream without authentication - using READ_ONLY permission",
                                    hostname);
                            server.registerAgent(agent);
                            streamAgents.put(responseObserver, agent);
                            log.info("Agent registered from metrics stream: {} ({})",
                                    hostname, agentId);
                        }

                        // Convert proto metrics to SDK metrics
                        Metrics sdkMetrics = convertMetrics(protoMetrics);
                        server.handleMetrics(sdkMetrics);
                        agent.updateLastMetricsAt();

                        log.trace("Received metrics from: {}", protoMetrics.getHostname());
                    } else if (request.hasHeartbeat()) {
                        // Respond to heartbeat
                        responseObserver.onNext(MetricsStreamResponse.newBuilder()
                                .setHeartbeatAck(HeartbeatAck.newBuilder()
                                        .setTimestamp(System.currentTimeMillis())
                                        .build())
                                .build());
                        if (agent != null) {
                            agent.updateHeartbeat();
                        }
                    } else if (request.hasCommandResult()) {
                        // Handle command result
                        CommandResult result = request.getCommandResult();
                        log.info("Command result received: {} success={}",
                                result.getCommandId(), result.getSuccess());
                    } else if (request.hasRealtime()) {
                        // Handle realtime metrics
                        io.nanolink.proto.RealtimeMetrics protoRealtime = request.getRealtime();

                        // Register agent on first message if needed
                        if (agent == null) {
                            agent = findOrCreateAgentForStream(responseObserver, "realtime");
                            if (agent != null) {
                                agentId = agent.getAgentId();
                            }
                        }

                        if (agent != null) {
                            RealtimeMetrics sdkRealtime = convertRealtimeMetrics(protoRealtime);
                            sdkRealtime.setHostname(agent.getHostname());
                            server.handleRealtimeMetrics(sdkRealtime);
                            agent.updateLastMetricsAt();
                            log.trace("Received realtime metrics from: {}", agent.getHostname());
                        }
                    } else if (request.hasStaticInfo()) {
                        // Handle static hardware info
                        io.nanolink.proto.StaticInfo protoStatic = request.getStaticInfo();

                        // Register agent from StaticInfo if not already registered
                        if (agent == null && protoStatic.hasSystemInfo()) {
                            String hostname = protoStatic.getSystemInfo().getHostname();
                            if (hostname != null && !hostname.isEmpty()) {
                                // Check if agent with same hostname already exists (reconnection case)
                                AgentConnection existingAgent = server.getAgentByHostname(hostname);
                                if (existingAgent != null) {
                                    server.unregisterAgent(existingAgent);
                                    log.info("Replacing stale agent connection for hostname: {}", hostname);
                                }

                                agentId = UUID.randomUUID().toString();
                                agent = new AgentConnection(
                                        agentId,
                                        hostname,
                                        protoStatic.getSystemInfo().getOsName(),
                                        protoStatic.hasCpu() ? protoStatic.getCpu().getArchitecture() : "",
                                        "0.2.1",
                                        TokenValidator.PermissionLevel.READ_ONLY // Default to READ_ONLY for
                                                                                 // unauthenticated streams
                                );
                                log.warn(
                                        "Agent {} registered via static info without authentication - using READ_ONLY permission",
                                        hostname);
                                server.registerAgent(agent);
                                streamAgents.put(responseObserver, agent);
                                log.info("Agent registered from static info: {} ({})", hostname, agentId);
                            }
                        }

                        if (agent != null) {
                            StaticInfo sdkStatic = convertStaticInfo(protoStatic);
                            sdkStatic.setHostname(agent.getHostname());
                            server.handleStaticInfo(sdkStatic);
                            log.info("Received static info from: {}", agent.getHostname());
                        }
                    } else if (request.hasPeriodic()) {
                        // Handle periodic data
                        io.nanolink.proto.PeriodicData protoPeriodic = request.getPeriodic();

                        if (agent != null) {
                            PeriodicData sdkPeriodic = convertPeriodicData(protoPeriodic);
                            sdkPeriodic.setHostname(agent.getHostname());
                            server.handlePeriodicData(sdkPeriodic);
                            log.debug("Received periodic data from: {}", agent.getHostname());
                        }
                    }
                } catch (Exception e) {
                    log.error("Error processing metrics stream request", e);
                }
            }

            @Override
            public void onError(Throwable t) {
                log.warn("Metrics stream error: {}", t.getMessage());
                cleanupAgent();
            }

            @Override
            public void onCompleted() {
                log.debug("Metrics stream completed");
                cleanupAgent();
                responseObserver.onCompleted();
            }

            private void cleanupAgent() {
                if (agent != null) {
                    server.unregisterAgent(agent);
                    streamAgents.remove(responseObserver);
                    log.info("Agent disconnected: {} ({})", agent.getHostname(), agentId);
                }
            }
        };
    }

    @Override
    public void reportMetrics(io.nanolink.proto.Metrics request,
            StreamObserver<MetricsAck> responseObserver) {
        try {
            log.trace("Received one-time metrics from: {}", request.getHostname());

            // Convert and handle the metrics
            Metrics sdkMetrics = convertMetrics(request);
            server.handleMetrics(sdkMetrics);

            responseObserver.onNext(MetricsAck.newBuilder()
                    .setSuccess(true)
                    .setTimestamp(System.currentTimeMillis())
                    .build());
            responseObserver.onCompleted();
        } catch (Exception e) {
            log.error("Error processing metrics", e);
            responseObserver.onError(e);
        }
    }

    @Override
    public void heartbeat(HeartbeatRequest request,
            StreamObserver<HeartbeatResponse> responseObserver) {
        log.trace("Heartbeat from agent: {}", request.getAgentId());

        responseObserver.onNext(HeartbeatResponse.newBuilder()
                .setServerTimestamp(System.currentTimeMillis())
                .setConfigChanged(false)
                .build());
        responseObserver.onCompleted();
    }

    @Override
    public void executeCommand(Command request,
            StreamObserver<CommandResult> responseObserver) {
        log.info("Execute command request: {} type={}", request.getCommandId(), request.getType());

        // For now, return not implemented
        responseObserver.onNext(CommandResult.newBuilder()
                .setCommandId(request.getCommandId())
                .setSuccess(false)
                .setError("Command execution through server not yet implemented")
                .build());
        responseObserver.onCompleted();
    }

    @Override
    public void syncMetrics(MetricsSyncRequest request,
            StreamObserver<MetricsSyncResponse> responseObserver) {
        log.debug("Metrics sync request from: {}", request.getAgentId());

        responseObserver.onNext(MetricsSyncResponse.newBuilder()
                .setSuccess(true)
                .setServerTimestamp(System.currentTimeMillis())
                .build());
        responseObserver.onCompleted();
    }

    @Override
    public void getAgentInfo(AgentInfoRequest request,
            StreamObserver<AgentInfoResponse> responseObserver) {
        log.debug("Get agent info request: {}", request.getAgentId());

        AgentConnection agent = server.getAgent(request.getAgentId());
        if (agent != null) {
            responseObserver.onNext(AgentInfoResponse.newBuilder()
                    .setAgentId(agent.getAgentId())
                    .setHostname(agent.getHostname())
                    .setOs(agent.getOs())
                    .setArch(agent.getArch())
                    .setVersion(agent.getAgentVersion())
                    .setPermissionLevel(agent.getPermissionLevel())
                    .setConnectedAt(agent.getConnectedAt().toEpochMilli())
                    .setLastMetricsAt(agent.getLastMetricsAt() != null ? agent.getLastMetricsAt().toEpochMilli() : 0)
                    .build());
        } else {
            responseObserver.onNext(AgentInfoResponse.newBuilder()
                    .setAgentId(request.getAgentId())
                    .build());
        }
        responseObserver.onCompleted();
    }

    /**
     * Convert proto Metrics to SDK Metrics model.
     * Complete conversion including all available fields.
     */
    private Metrics convertMetrics(io.nanolink.proto.Metrics proto) {
        Metrics metrics = new Metrics();
        metrics.setTimestamp(proto.getTimestamp());
        metrics.setHostname(proto.getHostname());

        // Convert load average
        List<Double> loadAvgList = proto.getLoadAverageList();
        if (!loadAvgList.isEmpty()) {
            double[] loadAvg = new double[loadAvgList.size()];
            for (int i = 0; i < loadAvgList.size(); i++) {
                loadAvg[i] = loadAvgList.get(i);
            }
            metrics.setLoadAverage(loadAvg);
        }

        // Convert CPU with extended fields
        if (proto.hasCpu()) {
            CpuMetrics cpu = proto.getCpu();
            Metrics.CpuMetrics sdkCpu = new Metrics.CpuMetrics();
            sdkCpu.setUsagePercent(cpu.getUsagePercent());
            sdkCpu.setCoreCount(cpu.getCoreCount());
            sdkCpu.setModel(cpu.getModel());
            sdkCpu.setVendor(cpu.getVendor());
            sdkCpu.setFrequencyMhz(cpu.getFrequencyMhz());
            sdkCpu.setFrequencyMaxMhz(cpu.getFrequencyMaxMhz());
            sdkCpu.setPhysicalCores(cpu.getPhysicalCores());
            sdkCpu.setLogicalCores(cpu.getLogicalCores());
            sdkCpu.setArchitecture(cpu.getArchitecture());
            sdkCpu.setTemperature(cpu.getTemperature());

            // Convert per-core usage list to array
            List<Double> perCoreList = cpu.getPerCoreUsageList();
            double[] perCoreArray = new double[perCoreList.size()];
            for (int i = 0; i < perCoreList.size(); i++) {
                perCoreArray[i] = perCoreList.get(i);
            }
            sdkCpu.setPerCoreUsage(perCoreArray);
            metrics.setCpu(sdkCpu);
        }

        // Convert Memory with extended fields
        if (proto.hasMemory()) {
            MemoryMetrics mem = proto.getMemory();
            Metrics.MemoryMetrics sdkMem = new Metrics.MemoryMetrics();
            sdkMem.setTotal(mem.getTotal());
            sdkMem.setUsed(mem.getUsed());
            sdkMem.setAvailable(mem.getAvailable());
            sdkMem.setSwapTotal(mem.getSwapTotal());
            sdkMem.setSwapUsed(mem.getSwapUsed());
            sdkMem.setCached(mem.getCached());
            sdkMem.setBuffers(mem.getBuffers());
            sdkMem.setMemoryType(mem.getMemoryType());
            sdkMem.setMemorySpeedMhz(mem.getMemorySpeedMhz());
            metrics.setMemory(sdkMem);
        }

        // Convert Disks with extended fields
        List<Metrics.DiskMetrics> diskList = new ArrayList<>();
        for (DiskMetrics disk : proto.getDisksList()) {
            Metrics.DiskMetrics sdkDisk = new Metrics.DiskMetrics();
            sdkDisk.setMountPoint(disk.getMountPoint());
            sdkDisk.setDevice(disk.getDevice());
            sdkDisk.setFsType(disk.getFsType());
            sdkDisk.setTotal(disk.getTotal());
            sdkDisk.setUsed(disk.getUsed());
            sdkDisk.setAvailable(disk.getAvailable());
            sdkDisk.setReadBytesPerSec(disk.getReadBytesSec());
            sdkDisk.setWriteBytesPerSec(disk.getWriteBytesSec());
            sdkDisk.setModel(disk.getModel());
            sdkDisk.setSerial(disk.getSerial());
            sdkDisk.setDiskType(disk.getDiskType());
            sdkDisk.setReadIops(disk.getReadIops());
            sdkDisk.setWriteIops(disk.getWriteIops());
            sdkDisk.setTemperature(disk.getTemperature());
            sdkDisk.setHealthStatus(disk.getHealthStatus());
            diskList.add(sdkDisk);
        }
        metrics.setDisks(diskList);

        // Convert Networks with extended fields
        List<Metrics.NetworkMetrics> netList = new ArrayList<>();
        for (NetworkMetrics net : proto.getNetworksList()) {
            Metrics.NetworkMetrics sdkNet = new Metrics.NetworkMetrics();
            sdkNet.setInterfaceName(net.getInterface());
            sdkNet.setRxBytesPerSec(net.getRxBytesSec());
            sdkNet.setTxBytesPerSec(net.getTxBytesSec());
            sdkNet.setRxPacketsPerSec(net.getRxPacketsSec());
            sdkNet.setTxPacketsPerSec(net.getTxPacketsSec());
            sdkNet.setUp(net.getIsUp());
            sdkNet.setMacAddress(net.getMacAddress());
            sdkNet.setIpAddresses(net.getIpAddressesList());
            sdkNet.setSpeedMbps(net.getSpeedMbps());
            sdkNet.setInterfaceType(net.getInterfaceType());
            netList.add(sdkNet);
        }
        metrics.setNetworks(netList);

        // Convert GPUs
        List<Metrics.GpuMetrics> gpuList = new ArrayList<>();
        for (GpuMetrics gpu : proto.getGpusList()) {
            Metrics.GpuMetrics sdkGpu = new Metrics.GpuMetrics();
            sdkGpu.setIndex(gpu.getIndex());
            sdkGpu.setName(gpu.getName());
            sdkGpu.setVendor(gpu.getVendor());
            sdkGpu.setUsagePercent(gpu.getUsagePercent());
            sdkGpu.setMemoryTotal(gpu.getMemoryTotal());
            sdkGpu.setMemoryUsed(gpu.getMemoryUsed());
            sdkGpu.setTemperature(gpu.getTemperature());
            sdkGpu.setFanSpeedPercent(gpu.getFanSpeedPercent());
            sdkGpu.setPowerWatts(gpu.getPowerWatts());
            sdkGpu.setPowerLimitWatts(gpu.getPowerLimitWatts());
            sdkGpu.setClockCoreMhz(gpu.getClockCoreMhz());
            sdkGpu.setClockMemoryMhz(gpu.getClockMemoryMhz());
            sdkGpu.setDriverVersion(gpu.getDriverVersion());
            sdkGpu.setPcieGeneration(gpu.getPcieGeneration());
            sdkGpu.setEncoderUsage(gpu.getEncoderUsage());
            sdkGpu.setDecoderUsage(gpu.getDecoderUsage());
            gpuList.add(sdkGpu);
        }
        metrics.setGpus(gpuList);

        // Convert SystemInfo
        if (proto.hasSystemInfo()) {
            io.nanolink.proto.SystemInfo sysInfo = proto.getSystemInfo();
            Metrics.SystemInfo sdkSysInfo = new Metrics.SystemInfo();
            sdkSysInfo.setOsName(sysInfo.getOsName());
            sdkSysInfo.setOsVersion(sysInfo.getOsVersion());
            sdkSysInfo.setKernelVersion(sysInfo.getKernelVersion());
            sdkSysInfo.setHostname(sysInfo.getHostname());
            sdkSysInfo.setBootTime(sysInfo.getBootTime());
            sdkSysInfo.setUptimeSeconds(sysInfo.getUptimeSeconds());
            sdkSysInfo.setMotherboardModel(sysInfo.getMotherboardModel());
            sdkSysInfo.setMotherboardVendor(sysInfo.getMotherboardVendor());
            sdkSysInfo.setBiosVersion(sysInfo.getBiosVersion());
            sdkSysInfo.setSystemModel(sysInfo.getSystemModel());
            sdkSysInfo.setSystemVendor(sysInfo.getSystemVendor());
            metrics.setSystemInfo(sdkSysInfo);
        }

        // Convert User Sessions
        List<Metrics.UserSession> sessionList = new ArrayList<>();
        for (io.nanolink.proto.UserSession session : proto.getUserSessionsList()) {
            Metrics.UserSession sdkSession = new Metrics.UserSession();
            sdkSession.setUsername(session.getUsername());
            sdkSession.setTty(session.getTty());
            sdkSession.setLoginTime(session.getLoginTime());
            sdkSession.setRemoteHost(session.getRemoteHost());
            sdkSession.setIdleSeconds(session.getIdleSeconds());
            sdkSession.setSessionType(session.getSessionType());
            sessionList.add(sdkSession);
        }
        metrics.setUserSessions(sessionList);

        // Convert NPUs
        List<Metrics.NpuMetrics> npuList = new ArrayList<>();
        for (NpuMetrics npu : proto.getNpusList()) {
            Metrics.NpuMetrics sdkNpu = new Metrics.NpuMetrics();
            sdkNpu.setIndex(npu.getIndex());
            sdkNpu.setName(npu.getName());
            sdkNpu.setVendor(npu.getVendor());
            sdkNpu.setUsagePercent(npu.getUsagePercent());
            sdkNpu.setMemoryTotal(npu.getMemoryTotal());
            sdkNpu.setMemoryUsed(npu.getMemoryUsed());
            sdkNpu.setTemperature(npu.getTemperature());
            sdkNpu.setPowerWatts(npu.getPowerWatts());
            sdkNpu.setDriverVersion(npu.getDriverVersion());
            npuList.add(sdkNpu);
        }
        metrics.setNpus(npuList);

        return metrics;
    }

    /**
     * Find or create an agent for the current stream.
     * Used when receiving layered metrics without initial full metrics.
     */
    private AgentConnection findOrCreateAgentForStream(StreamObserver<?> observer, String source) {
        // Check if already registered
        AgentConnection existing = streamAgents.get(observer);
        if (existing != null) {
            return existing;
        }
        // For layered metrics, we need to wait for either full metrics or static info
        // to get the hostname. Return null to indicate we need to wait.
        log.debug("No agent found for {} stream, waiting for initial data", source);
        return null;
    }

    /**
     * Convert proto RealtimeMetrics to SDK RealtimeMetrics.
     */
    private RealtimeMetrics convertRealtimeMetrics(io.nanolink.proto.RealtimeMetrics proto) {
        RealtimeMetrics realtime = new RealtimeMetrics();
        realtime.setTimestamp(proto.getTimestamp());
        realtime.setCpuUsagePercent(proto.getCpuUsagePercent());
        realtime.setCpuTemperature(proto.getCpuTemperature());
        realtime.setCpuFrequencyMhz(proto.getCpuFrequencyMhz());
        realtime.setMemoryUsed(proto.getMemoryUsed());
        realtime.setMemoryCached(proto.getMemoryCached());
        realtime.setSwapUsed(proto.getSwapUsed());

        // CPU per-core usage
        List<Double> perCoreList = proto.getCpuPerCoreList();
        double[] perCore = new double[perCoreList.size()];
        for (int i = 0; i < perCoreList.size(); i++) {
            perCore[i] = perCoreList.get(i);
        }
        realtime.setCpuPerCore(perCore);

        // Load average
        List<Double> loadList = proto.getLoadAverageList();
        double[] load = new double[loadList.size()];
        for (int i = 0; i < loadList.size(); i++) {
            load[i] = loadList.get(i);
        }
        realtime.setLoadAverage(load);

        // Disk IO
        List<RealtimeMetrics.DiskIO> diskIoList = new ArrayList<>();
        for (io.nanolink.proto.DiskIO disk : proto.getDiskIoList()) {
            RealtimeMetrics.DiskIO sdkDisk = new RealtimeMetrics.DiskIO();
            sdkDisk.setDevice(disk.getDevice());
            sdkDisk.setReadBytesSec(disk.getReadBytesSec());
            sdkDisk.setWriteBytesSec(disk.getWriteBytesSec());
            sdkDisk.setReadIops(disk.getReadIops());
            sdkDisk.setWriteIops(disk.getWriteIops());
            diskIoList.add(sdkDisk);
        }
        realtime.setDiskIo(diskIoList);

        // Network IO
        List<RealtimeMetrics.NetworkIO> netIoList = new ArrayList<>();
        for (io.nanolink.proto.NetworkIO net : proto.getNetworkIoList()) {
            RealtimeMetrics.NetworkIO sdkNet = new RealtimeMetrics.NetworkIO();
            sdkNet.setInterfaceName(net.getInterface());
            sdkNet.setRxBytesSec(net.getRxBytesSec());
            sdkNet.setTxBytesSec(net.getTxBytesSec());
            sdkNet.setRxPacketsSec(net.getRxPacketsSec());
            sdkNet.setTxPacketsSec(net.getTxPacketsSec());
            sdkNet.setUp(net.getIsUp());
            netIoList.add(sdkNet);
        }
        realtime.setNetworkIo(netIoList);

        // GPU usage
        List<RealtimeMetrics.GpuUsage> gpuList = new ArrayList<>();
        for (io.nanolink.proto.GpuUsage gpu : proto.getGpuUsageList()) {
            RealtimeMetrics.GpuUsage sdkGpu = new RealtimeMetrics.GpuUsage();
            sdkGpu.setIndex(gpu.getIndex());
            sdkGpu.setUsagePercent(gpu.getUsagePercent());
            sdkGpu.setMemoryUsed(gpu.getMemoryUsed());
            sdkGpu.setTemperature(gpu.getTemperature());
            sdkGpu.setPowerWatts(gpu.getPowerWatts());
            sdkGpu.setClockCoreMhz(gpu.getClockCoreMhz());
            sdkGpu.setEncoderUsage(gpu.getEncoderUsage());
            sdkGpu.setDecoderUsage(gpu.getDecoderUsage());
            gpuList.add(sdkGpu);
        }
        realtime.setGpuUsage(gpuList);

        // NPU usage
        List<RealtimeMetrics.NpuUsage> npuList = new ArrayList<>();
        for (io.nanolink.proto.NpuUsage npu : proto.getNpuUsageList()) {
            RealtimeMetrics.NpuUsage sdkNpu = new RealtimeMetrics.NpuUsage();
            sdkNpu.setIndex(npu.getIndex());
            sdkNpu.setUsagePercent(npu.getUsagePercent());
            sdkNpu.setMemoryUsed(npu.getMemoryUsed());
            sdkNpu.setTemperature(npu.getTemperature());
            sdkNpu.setPowerWatts(npu.getPowerWatts());
            npuList.add(sdkNpu);
        }
        realtime.setNpuUsage(npuList);

        return realtime;
    }

    /**
     * Convert proto StaticInfo to SDK StaticInfo.
     */
    private StaticInfo convertStaticInfo(io.nanolink.proto.StaticInfo proto) {
        StaticInfo staticInfo = new StaticInfo();
        staticInfo.setTimestamp(proto.getTimestamp());

        // CPU static info
        if (proto.hasCpu()) {
            io.nanolink.proto.CpuStaticInfo cpu = proto.getCpu();
            StaticInfo.CpuStaticInfo sdkCpu = new StaticInfo.CpuStaticInfo();
            sdkCpu.setModel(cpu.getModel());
            sdkCpu.setVendor(cpu.getVendor());
            sdkCpu.setPhysicalCores(cpu.getPhysicalCores());
            sdkCpu.setLogicalCores(cpu.getLogicalCores());
            sdkCpu.setArchitecture(cpu.getArchitecture());
            sdkCpu.setFrequencyMaxMhz(cpu.getFrequencyMaxMhz());
            sdkCpu.setL1CacheKb(cpu.getL1CacheKb());
            sdkCpu.setL2CacheKb(cpu.getL2CacheKb());
            sdkCpu.setL3CacheKb(cpu.getL3CacheKb());
            staticInfo.setCpu(sdkCpu);
        }

        // Memory static info
        if (proto.hasMemory()) {
            io.nanolink.proto.MemoryStaticInfo mem = proto.getMemory();
            StaticInfo.MemoryStaticInfo sdkMem = new StaticInfo.MemoryStaticInfo();
            sdkMem.setTotal(mem.getTotal());
            sdkMem.setSwapTotal(mem.getSwapTotal());
            sdkMem.setMemoryType(mem.getMemoryType());
            sdkMem.setMemorySpeedMhz(mem.getMemorySpeedMhz());
            sdkMem.setMemorySlots(mem.getMemorySlots());
            staticInfo.setMemory(sdkMem);
        }

        // Disk static info
        List<StaticInfo.DiskStaticInfo> diskList = new ArrayList<>();
        for (io.nanolink.proto.DiskStaticInfo disk : proto.getDisksList()) {
            StaticInfo.DiskStaticInfo sdkDisk = new StaticInfo.DiskStaticInfo();
            sdkDisk.setDevice(disk.getDevice());
            sdkDisk.setMountPoint(disk.getMountPoint());
            sdkDisk.setFsType(disk.getFsType());
            sdkDisk.setModel(disk.getModel());
            sdkDisk.setSerial(disk.getSerial());
            sdkDisk.setDiskType(disk.getDiskType());
            sdkDisk.setTotalBytes(disk.getTotalBytes());
            sdkDisk.setHealthStatus(disk.getHealthStatus());
            diskList.add(sdkDisk);
        }
        staticInfo.setDisks(diskList);

        // Network static info
        List<StaticInfo.NetworkStaticInfo> netList = new ArrayList<>();
        for (io.nanolink.proto.NetworkStaticInfo net : proto.getNetworksList()) {
            StaticInfo.NetworkStaticInfo sdkNet = new StaticInfo.NetworkStaticInfo();
            sdkNet.setInterfaceName(net.getInterface());
            sdkNet.setMacAddress(net.getMacAddress());
            sdkNet.setIpAddresses(net.getIpAddressesList());
            sdkNet.setSpeedMbps(net.getSpeedMbps());
            sdkNet.setInterfaceType(net.getInterfaceType());
            sdkNet.setVirtual(net.getIsVirtual());
            netList.add(sdkNet);
        }
        staticInfo.setNetworks(netList);

        // GPU static info
        List<StaticInfo.GpuStaticInfo> gpuList = new ArrayList<>();
        for (io.nanolink.proto.GpuStaticInfo gpu : proto.getGpusList()) {
            StaticInfo.GpuStaticInfo sdkGpu = new StaticInfo.GpuStaticInfo();
            sdkGpu.setIndex(gpu.getIndex());
            sdkGpu.setName(gpu.getName());
            sdkGpu.setVendor(gpu.getVendor());
            sdkGpu.setMemoryTotal(gpu.getMemoryTotal());
            sdkGpu.setDriverVersion(gpu.getDriverVersion());
            sdkGpu.setPcieGeneration(gpu.getPcieGeneration());
            sdkGpu.setPowerLimitWatts(gpu.getPowerLimitWatts());
            gpuList.add(sdkGpu);
        }
        staticInfo.setGpus(gpuList);

        // NPU static info
        List<StaticInfo.NpuStaticInfo> npuList = new ArrayList<>();
        for (io.nanolink.proto.NpuStaticInfo npu : proto.getNpusList()) {
            StaticInfo.NpuStaticInfo sdkNpu = new StaticInfo.NpuStaticInfo();
            sdkNpu.setIndex(npu.getIndex());
            sdkNpu.setName(npu.getName());
            sdkNpu.setVendor(npu.getVendor());
            sdkNpu.setMemoryTotal(npu.getMemoryTotal());
            sdkNpu.setDriverVersion(npu.getDriverVersion());
            npuList.add(sdkNpu);
        }
        staticInfo.setNpus(npuList);

        // System info
        if (proto.hasSystemInfo()) {
            io.nanolink.proto.SystemInfo sysInfo = proto.getSystemInfo();
            Metrics.SystemInfo sdkSysInfo = new Metrics.SystemInfo();
            sdkSysInfo.setOsName(sysInfo.getOsName());
            sdkSysInfo.setOsVersion(sysInfo.getOsVersion());
            sdkSysInfo.setKernelVersion(sysInfo.getKernelVersion());
            sdkSysInfo.setHostname(sysInfo.getHostname());
            sdkSysInfo.setBootTime(sysInfo.getBootTime());
            sdkSysInfo.setUptimeSeconds(sysInfo.getUptimeSeconds());
            sdkSysInfo.setMotherboardModel(sysInfo.getMotherboardModel());
            sdkSysInfo.setMotherboardVendor(sysInfo.getMotherboardVendor());
            sdkSysInfo.setBiosVersion(sysInfo.getBiosVersion());
            sdkSysInfo.setSystemModel(sysInfo.getSystemModel());
            sdkSysInfo.setSystemVendor(sysInfo.getSystemVendor());
            staticInfo.setSystemInfo(sdkSysInfo);
        }

        return staticInfo;
    }

    /**
     * Convert proto PeriodicData to SDK PeriodicData.
     */
    private PeriodicData convertPeriodicData(io.nanolink.proto.PeriodicData proto) {
        PeriodicData periodic = new PeriodicData();
        periodic.setTimestamp(proto.getTimestamp());

        // Disk usage
        List<PeriodicData.DiskUsage> diskList = new ArrayList<>();
        for (io.nanolink.proto.DiskUsage disk : proto.getDiskUsageList()) {
            PeriodicData.DiskUsage sdkDisk = new PeriodicData.DiskUsage();
            sdkDisk.setDevice(disk.getDevice());
            sdkDisk.setMountPoint(disk.getMountPoint());
            sdkDisk.setTotal(disk.getTotal());
            sdkDisk.setUsed(disk.getUsed());
            sdkDisk.setAvailable(disk.getAvailable());
            sdkDisk.setTemperature(disk.getTemperature());
            diskList.add(sdkDisk);
        }
        periodic.setDiskUsage(diskList);

        // User sessions
        List<Metrics.UserSession> sessionList = new ArrayList<>();
        for (io.nanolink.proto.UserSession session : proto.getUserSessionsList()) {
            Metrics.UserSession sdkSession = new Metrics.UserSession();
            sdkSession.setUsername(session.getUsername());
            sdkSession.setTty(session.getTty());
            sdkSession.setLoginTime(session.getLoginTime());
            sdkSession.setRemoteHost(session.getRemoteHost());
            sdkSession.setIdleSeconds(session.getIdleSeconds());
            sdkSession.setSessionType(session.getSessionType());
            sessionList.add(sdkSession);
        }
        periodic.setUserSessions(sessionList);

        // Network address updates
        List<PeriodicData.NetworkAddressUpdate> netList = new ArrayList<>();
        for (io.nanolink.proto.NetworkAddressUpdate net : proto.getNetworkUpdatesList()) {
            PeriodicData.NetworkAddressUpdate sdkNet = new PeriodicData.NetworkAddressUpdate();
            sdkNet.setInterfaceName(net.getInterface());
            sdkNet.setIpAddresses(net.getIpAddressesList());
            sdkNet.setUp(net.getIsUp());
            netList.add(sdkNet);
        }
        periodic.setNetworkUpdates(netList);

        return periodic;
    }

    /**
     * Send a data request to a specific agent.
     * Used to request static info, disk usage, etc. on demand.
     *
     * @param agentId     The agent ID to send the request to
     * @param requestType The type of data to request
     * @param target      Optional target (e.g., specific device name)
     * @return true if the request was sent successfully
     */
    public boolean sendDataRequest(String agentId, DataRequestType requestType, String target) {
        for (Map.Entry<StreamObserver<?>, AgentConnection> entry : streamAgents.entrySet()) {
            if (entry.getValue().getAgentId().equals(agentId)) {
                @SuppressWarnings("unchecked")
                StreamObserver<MetricsStreamResponse> observer = (StreamObserver<MetricsStreamResponse>) entry.getKey();

                io.nanolink.proto.DataRequest.Builder builder = io.nanolink.proto.DataRequest.newBuilder()
                        .setRequestType(requestType);
                if (target != null) {
                    builder.setTarget(target);
                }

                observer.onNext(MetricsStreamResponse.newBuilder()
                        .setDataRequest(builder.build())
                        .build());

                log.info("Sent data request {} to agent {}", requestType, agentId);
                return true;
            }
        }
        log.warn("Agent {} not found for data request", agentId);
        return false;
    }

    /**
     * Send a data request to all connected agents.
     */
    public void broadcastDataRequest(DataRequestType requestType) {
        io.nanolink.proto.DataRequest request = io.nanolink.proto.DataRequest.newBuilder()
                .setRequestType(requestType)
                .build();

        MetricsStreamResponse response = MetricsStreamResponse.newBuilder()
                .setDataRequest(request)
                .build();

        for (Map.Entry<StreamObserver<?>, AgentConnection> entry : streamAgents.entrySet()) {
            @SuppressWarnings("unchecked")
            StreamObserver<MetricsStreamResponse> observer = (StreamObserver<MetricsStreamResponse>) entry.getKey();
            observer.onNext(response);
        }
        log.info("Broadcast data request {} to {} agents", requestType, streamAgents.size());
    }
}
