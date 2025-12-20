package com.kkape.sdk.grpc;

import com.kkape.sdk.AgentConnection;
import com.kkape.sdk.NanoLinkServer;
import com.kkape.sdk.TokenValidator;
import com.kkape.sdk.model.Metrics;
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
                                    3 // Default permission
                            );
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
     * Simplified conversion that only maps essential fields.
     */
    private Metrics convertMetrics(io.nanolink.proto.Metrics proto) {
        Metrics metrics = new Metrics();
        metrics.setTimestamp(proto.getTimestamp());
        metrics.setHostname(proto.getHostname());

        // Convert CPU
        if (proto.hasCpu()) {
            CpuMetrics cpu = proto.getCpu();
            Metrics.CpuMetrics sdkCpu = new Metrics.CpuMetrics();
            sdkCpu.setUsagePercent(cpu.getUsagePercent());
            sdkCpu.setCoreCount(cpu.getCoreCount());

            // Convert per-core usage list to array
            List<Double> perCoreList = cpu.getPerCoreUsageList();
            double[] perCoreArray = new double[perCoreList.size()];
            for (int i = 0; i < perCoreList.size(); i++) {
                perCoreArray[i] = perCoreList.get(i);
            }
            sdkCpu.setPerCoreUsage(perCoreArray);
            metrics.setCpu(sdkCpu);
        }

        // Convert Memory
        if (proto.hasMemory()) {
            MemoryMetrics mem = proto.getMemory();
            Metrics.MemoryMetrics sdkMem = new Metrics.MemoryMetrics();
            sdkMem.setTotal(mem.getTotal());
            sdkMem.setUsed(mem.getUsed());
            sdkMem.setAvailable(mem.getAvailable());
            sdkMem.setSwapTotal(mem.getSwapTotal());
            sdkMem.setSwapUsed(mem.getSwapUsed());
            metrics.setMemory(sdkMem);
        }

        // Convert Disks
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
            diskList.add(sdkDisk);
        }
        metrics.setDisks(diskList);

        // Convert Networks
        List<Metrics.NetworkMetrics> netList = new ArrayList<>();
        for (NetworkMetrics net : proto.getNetworksList()) {
            Metrics.NetworkMetrics sdkNet = new Metrics.NetworkMetrics();
            sdkNet.setInterfaceName(net.getInterface());
            sdkNet.setRxBytesPerSec(net.getRxBytesSec());
            sdkNet.setTxBytesPerSec(net.getTxBytesSec());
            sdkNet.setRxPacketsPerSec(net.getRxPacketsSec());
            sdkNet.setTxPacketsPerSec(net.getTxPacketsSec());
            sdkNet.setUp(net.getIsUp());
            netList.add(sdkNet);
        }
        metrics.setNetworks(netList);

        return metrics;
    }
}
