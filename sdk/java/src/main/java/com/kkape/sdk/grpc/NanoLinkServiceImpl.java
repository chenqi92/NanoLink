package com.kkape.sdk.grpc;

import com.kkape.sdk.AgentConnection;
import com.kkape.sdk.NanoLinkServer;
import com.kkape.sdk.TokenValidator;
import com.kkape.sdk.model.Metrics;
import com.kkape.sdk.model.PeriodicData;
import com.kkape.sdk.model.RealtimeMetrics;
import com.kkape.sdk.model.StaticInfo;
import com.kkape.sdk.util.SanitizeUtils;
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
 * gRPC service implementation for NanoOps agent communication.
 * Handles authentication, metrics streaming, and command execution.
 */
public class NanoLinkServiceImpl extends NanoLinkServiceGrpc.NanoLinkServiceImplBase {
    private static final Logger log = LoggerFactory.getLogger(NanoLinkServiceImpl.class);

    private final NanoLinkServer server;
    private final TokenValidator tokenValidator;

    // P0-3: 可选的强制认证模式，默认为false
    private final boolean requireAuthentication;

    // Map of authenticated streams to their agent connections
    private final Map<StreamObserver<?>, AgentConnection> streamAgents = new ConcurrentHashMap<>();

    public NanoLinkServiceImpl(NanoLinkServer server, TokenValidator tokenValidator) {
        this(server, tokenValidator, false);
    }

    /**
     * Constructor with optional authentication requirement.
     *
     * @param server               The NanoOps server instance
     * @param tokenValidator       Token validator for authentication
     * @param requireAuthentication If true, rejects unauthenticated stream connections
     */
    public NanoLinkServiceImpl(NanoLinkServer server, TokenValidator tokenValidator, boolean requireAuthentication) {
        this.server = server;
        this.tokenValidator = tokenValidator;
        this.requireAuthentication = requireAuthentication;
    }

    private TokenValidator.ValidationResult validateBearerAuthorization(String authorization) {
        if (authorization == null || authorization.isBlank()) {
            return TokenValidator.ValidationResult.failure("Bearer token required");
        }
        String[] parts = authorization.trim().split("\\s+", 2);
        if (parts.length != 2 || !"Bearer".equalsIgnoreCase(parts[0]) || parts[1].isBlank()) {
            return TokenValidator.ValidationResult.failure("Invalid authorization metadata");
        }
        try {
            return tokenValidator.validate(parts[1]);
        } catch (RuntimeException ex) {
            log.warn("Token validator failed", ex);
            return TokenValidator.ValidationResult.failure("Token validation failed");
        }
    }

    private static StreamObserver<MetricsStreamRequest> closedRequestObserver() {
        return new StreamObserver<>() {
            @Override
            public void onNext(MetricsStreamRequest ignored) {
            }

            @Override
            public void onError(Throwable ignored) {
            }

            @Override
            public void onCompleted() {
            }
        };
    }

    @Override
    public void authenticate(AuthRequest request, StreamObserver<AuthResponse> responseObserver) {
        // Sanitize agent-controlled fields before logging to prevent log injection
        // (CRLF / control chars forging audit entries).
        String hostname = SanitizeUtils.sanitizeHostname(request.getHostname());
        String version = SanitizeUtils.sanitizeString(request.getAgentVersion());
        log.debug("Authentication request from: {} ({})", hostname, version);

        try {
            TokenValidator.ValidationResult result = tokenValidator.validate(request.getToken());

            if (result.isValid()) {
                // Check if agent with same hostname already exists (reconnection case).
                // This request passed token validation, so an authenticated takeover
                // is allowed.
                AgentConnection existingAgent = server.getAgentByHostname(hostname);
                if (existingAgent != null) {
                    server.unregisterAgent(existingAgent);
                    log.info("Replacing stale agent connection for hostname: {}", hostname);
                }

                // Create agent connection
                String agentId = UUID.randomUUID().toString();
                AgentConnection agent = new AgentConnection(
                        agentId,
                        hostname,
                        request.getOs(),
                        request.getArch(),
                        version,
                        result.getPermissionLevel());

                server.registerAgent(agent);
                log.info("Agent authenticated: {} ({}) with permission level {}",
                        hostname, agentId, result.getPermissionLevel());

                responseObserver.onNext(AuthResponse.newBuilder()
                        .setSuccess(true)
                        .setPermissionLevel(result.getPermissionLevel())
                        .build());
            } else {
                log.warn("Authentication failed for: {}", hostname);
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

        String authorization = NanoLinkServer.currentAuthorizationHeader();
        TokenValidator.ValidationResult streamAuth = validateBearerAuthorization(authorization);
        boolean credentialProvided = authorization != null && !authorization.isBlank();
        if ((credentialProvided && !streamAuth.isValid())
                || (requireAuthentication && !streamAuth.isValid())) {
            responseObserver.onError(io.grpc.Status.UNAUTHENTICATED
                    .withDescription(credentialProvided ? "Invalid bearer token" : "Bearer token required")
                    .asRuntimeException());
            return closedRequestObserver();
        }
        final int streamPermission = streamAuth.isValid()
                ? streamAuth.getPermissionLevel()
                : TokenValidator.PermissionLevel.READ_ONLY;

        // Send initial response immediately to trigger HTTP/2 headers
        // This allows tonic/rust clients to complete the stream_metrics() call
        responseObserver.onNext(MetricsStreamResponse.newBuilder()
                .setHeartbeatAck(HeartbeatAck.newBuilder()
                        .setTimestamp(System.currentTimeMillis())
                        .build())
                .build());
        log.debug("Sent initial heartbeat ack to establish stream");

        return new StreamObserver<>() {
            private AgentConnection agent = null;
            private String agentId = null;

            @Override
            public void onNext(MetricsStreamRequest request) {
                try {
                    if (request.hasMetrics()) {
                        io.nanolink.proto.Metrics protoMetrics = request.getMetrics();

                        // Register agent on first metrics if not already
                        if (agent == null) {
                            String hostname = SanitizeUtils.sanitizeHostname(protoMetrics.getHostname());

                            // Check if agent with same hostname already exists.
                            // Security: an unauthenticated metrics stream must NOT evict
                            // a live connection by reusing its hostname — that would let
                            // anyone disconnect/hijack an active (possibly authenticated)
                            // agent. Only take over a stale connection; reject otherwise.
                            AgentConnection existingAgent = server.getAgentByHostname(hostname);
                            if (existingAgent != null) {
                                long ageSec = java.time.Duration
                                        .between(existingAgent.getLastHeartbeat(), java.time.Instant.now())
                                        .getSeconds();
                                if (existingAgent.isActive() && ageSec < 90) {
                                    log.warn("SECURITY: refusing unauthenticated stream takeover of active "
                                            + "connection for hostname {} (heartbeat age: {}s)", hostname, ageSec);
                                    responseObserver.onError(io.grpc.Status.ALREADY_EXISTS
                                            .withDescription("a connection for this host is already active")
                                            .asRuntimeException());
                                    return;
                                }
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
                                    streamPermission
                            );
                            if (streamAuth.isValid()) {
                                log.info("Agent {} registered via authenticated metrics stream with permission {}",
                                        hostname, streamPermission);
                            } else {
                                log.warn("Agent {} registered via anonymous metrics stream with READ_ONLY permission",
                                        hostname);
                            }
                            server.registerAgent(agent);
                            streamAgents.put(responseObserver, agent);
                            wireCommandSender(agent, responseObserver);
                            log.info("Agent registered from metrics stream: {} ({})",
                                    hostname, agentId);
                        }

                        // Convert proto metrics to SDK metrics
                        Metrics sdkMetrics = convertMetrics(protoMetrics);
                        server.handleMetrics(sdkMetrics);
                        agent.updateLastMetricsAt();

                        log.trace("Received metrics from: {}", protoMetrics.getHostname());
                    } else if (request.hasHeartbeat()) {
                        // Respond to heartbeat (synchronized: onNext is not safe to
                        // call concurrently with command/data-request sends).
                        synchronized (responseObserver) {
                            responseObserver.onNext(MetricsStreamResponse.newBuilder()
                                    .setHeartbeatAck(HeartbeatAck.newBuilder()
                                            .setTimestamp(System.currentTimeMillis())
                                            .build())
                                    .build());
                        }
                        if (agent != null) {
                            agent.updateHeartbeat();
                        }
                    } else if (request.hasCommandResult()) {
                        // Route the result back to the pending sendCommand/executeCommand caller
                        CommandResult result = request.getCommandResult();
                        if (agent != null) {
                            agent.handleCommandResult(result.getCommandId(), convertCommandResult(result));
                        }
                        log.info("Command result received: {} success={}",
                                result.getCommandId(), result.getSuccess());
                    } else if (request.hasRealtime()) {
                        // Handle realtime metrics
                        io.nanolink.proto.RealtimeMetrics protoRealtime = request.getRealtime();

                        // Register agent on first message if needed
                        if (agent == null) {
                            agent = findOrCreateAgentForStream(responseObserver);
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
                            String hostname = SanitizeUtils.sanitizeHostname(protoStatic.getSystemInfo().getHostname());
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
                                        protoStatic.getAgentVersion().isEmpty() ? "unknown" : protoStatic.getAgentVersion(),
                                        streamPermission
                                );
                                if (streamAuth.isValid()) {
                                    log.info("Agent {} registered via authenticated static-info stream with permission {}",
                                            hostname, streamPermission);
                                } else {
                                    log.warn("Agent {} registered via anonymous static-info stream with READ_ONLY permission",
                                            hostname);
                                }
                                server.registerAgent(agent);
                                streamAgents.put(responseObserver, agent);
                                wireCommandSender(agent, responseObserver);
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

        AgentConnection agent = locateAgentForCommand(request);
        if (agent == null) {
            responseObserver.onNext(CommandResult.newBuilder()
                    .setCommandId(request.getCommandId())
                    .setSuccess(false)
                    .setError("no target agent: set params[\"agent_id\"] or params[\"hostname\"], "
                            + "or connect exactly one agent")
                    .build());
            responseObserver.onCompleted();
            return;
        }

        try {
            com.kkape.sdk.model.Command.Result result = agent.sendCommand(commandFromProto(request))
                    .get(35, java.util.concurrent.TimeUnit.SECONDS);
            responseObserver.onNext(commandResultToProto(result, request.getCommandId()));
        } catch (Exception e) {
            log.warn("executeCommand failed: {}", e.getMessage());
            responseObserver.onNext(CommandResult.newBuilder()
                    .setCommandId(request.getCommandId())
                    .setSuccess(false)
                    .setError(e.getMessage() != null ? e.getMessage() : e.toString())
                    .build());
        }
        responseObserver.onCompleted();
    }

    /** Wire the command sender so AgentConnection.sendCommand reaches this stream. */
    private void wireCommandSender(AgentConnection agent, StreamObserver<MetricsStreamResponse> observer) {
        agent.setStreamSender(resp -> {
            synchronized (observer) {
                observer.onNext(resp);
            }
        });
    }

    /** Resolve the target agent for a unary executeCommand. */
    private AgentConnection locateAgentForCommand(Command request) {
        Map<String, String> params = request.getParamsMap();
        String aid = params.get("agent_id");
        if (aid != null && !aid.isEmpty()) {
            AgentConnection a = server.getAgent(aid);
            if (a != null) {
                return a;
            }
        }
        String host = params.get("hostname");
        if (host != null && !host.isEmpty()) {
            AgentConnection a = server.getAgentByHostname(host);
            if (a != null) {
                return a;
            }
        }
        Map<String, AgentConnection> all = server.getAgents();
        if (all.size() == 1) {
            return all.values().iterator().next();
        }
        return null;
    }

    /** Build an SDK Command from its protobuf representation. */
    private com.kkape.sdk.model.Command commandFromProto(Command proto) {
        com.kkape.sdk.model.Command cmd = new com.kkape.sdk.model.Command();
        for (com.kkape.sdk.model.Command.Type t : com.kkape.sdk.model.Command.Type.values()) {
            if (t.getCode() == proto.getType().getNumber()) {
                cmd.setType(t);
                break;
            }
        }
        cmd.setTarget(proto.getTarget());
        cmd.setParams(new java.util.HashMap<>(proto.getParamsMap()));
        cmd.setSuperToken(proto.getSuperToken());
        if (!proto.getCommandId().isEmpty()) {
            cmd.setCommandId(proto.getCommandId());
        }
        return cmd;
    }

    /** Convert a protobuf CommandResult into the SDK result type. */
    private com.kkape.sdk.model.Command.Result convertCommandResult(CommandResult proto) {
        com.kkape.sdk.model.Command.Result r = new com.kkape.sdk.model.Command.Result();
        r.setCommandId(proto.getCommandId());
        r.setSuccess(proto.getSuccess());
        r.setOutput(proto.getOutput());
        r.setError(proto.getError());
        if (!proto.getFileContent().isEmpty()) {
            r.setFileContent(proto.getFileContent().toByteArray());
        }
        return r;
    }

    /** Convert an SDK result into protobuf, falling back to the request id. */
    private CommandResult commandResultToProto(com.kkape.sdk.model.Command.Result r, String fallbackId) {
        CommandResult.Builder b = CommandResult.newBuilder().setSuccess(r.isSuccess());
        b.setCommandId(r.getCommandId() != null && !r.getCommandId().isEmpty() ? r.getCommandId() : fallbackId);
        if (r.getOutput() != null) {
            b.setOutput(r.getOutput());
        }
        if (r.getError() != null) {
            b.setError(r.getError());
        }
        if (r.getFileContent() != null) {
            b.setFileContent(com.google.protobuf.ByteString.copyFrom(r.getFileContent()));
        }
        return b.build();
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
    private AgentConnection findOrCreateAgentForStream(StreamObserver<?> observer) {
        // Check if already registered
        AgentConnection existing = streamAgents.get(observer);
        if (existing != null) {
            return existing;
        }
        // For layered metrics, we need to wait for either full metrics or static info
        // to get the hostname. Return null to indicate we need to wait.
        log.debug("No agent found for realtime stream, waiting for initial data");
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

                synchronized (observer) {
                    observer.onNext(MetricsStreamResponse.newBuilder()
                            .setDataRequest(builder.build())
                            .build());
                }

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
            synchronized (observer) {
                observer.onNext(response);
            }
        }
        log.info("Broadcast data request {} to {} agents", requestType, streamAgents.size());
    }
}
