package com.kkape.sdk;

import com.kkape.sdk.model.Command;
import com.kkape.sdk.model.Metrics;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.function.Consumer;

/**
 * Represents a connection to a monitoring agent (gRPC-based)
 */
@SuppressWarnings("unused") // Public API methods may not be used internally
public class AgentConnection {
    private static final Logger log = LoggerFactory.getLogger(AgentConnection.class);

    private final String agentId;
    private String hostname;
    private String agentVersion;
    private String os;
    private String arch;
    private int permissionLevel;
    private Instant connectedAt;
    private Instant lastHeartbeat;
    private Metrics lastMetrics;
    private Instant lastMetricsAt;
    private volatile boolean active = true;

    // For sending commands via gRPC stream
    private Consumer<byte[]> streamSender;

    private final Map<String, CompletableFuture<Command.Result>> pendingCommands = new ConcurrentHashMap<>();

    /**
     * Constructor for gRPC-based connections
     */
    public AgentConnection(String agentId, String hostname, String os, String arch,
            String agentVersion, int permissionLevel) {
        this.agentId = agentId;
        this.hostname = hostname;
        this.os = os;
        this.arch = arch;
        this.agentVersion = agentVersion;
        this.permissionLevel = permissionLevel;
        this.connectedAt = Instant.now();
        this.lastHeartbeat = Instant.now();
    }

    /**
     * Create a new agent connection with auto-generated ID
     */
    public static AgentConnection create(String hostname, String os, String arch,
            String agentVersion, int permissionLevel) {
        return new AgentConnection(UUID.randomUUID().toString(), hostname, os, arch, agentVersion, permissionLevel);
    }

    /**
     * Set the stream sender for sending commands
     */
    public void setStreamSender(Consumer<byte[]> sender) {
        this.streamSender = sender;
    }

    /**
     * Send a command to the agent
     */
    public CompletableFuture<Command.Result> sendCommand(Command command) {
        if (!active) {
            return CompletableFuture.failedFuture(new IllegalStateException("Agent not connected"));
        }

        if (streamSender == null) {
            return CompletableFuture.failedFuture(new IllegalStateException("Stream sender not available"));
        }

        // Check permission
        if (command.getRequiredPermission() > permissionLevel) {
            return CompletableFuture.failedFuture(
                    new SecurityException("Insufficient permission. Required: " + command.getRequiredPermission() +
                            ", Have: " + permissionLevel));
        }

        String commandId = UUID.randomUUID().toString();
        command.setCommandId(commandId);

        CompletableFuture<Command.Result> future = new CompletableFuture<>();
        pendingCommands.put(commandId, future);

        // Set timeout
        future.orTimeout(30, TimeUnit.SECONDS)
                .whenComplete((result, error) -> pendingCommands.remove(commandId));

        // Send command via gRPC stream
        try {
            byte[] data = command.toProtobuf();
            streamSender.accept(data);
            log.debug("Sent command {} to agent {}", command.getType(), hostname);
        } catch (Exception e) {
            pendingCommands.remove(commandId);
            return CompletableFuture.failedFuture(e);
        }

        return future;
    }

    /**
     * Handle command result from agent
     */
    public void handleCommandResult(String commandId, Command.Result result) {
        CompletableFuture<Command.Result> future = pendingCommands.remove(commandId);
        if (future != null) {
            future.complete(result);
        }
    }

    /**
     * Update last heartbeat time
     */
    public void updateHeartbeat() {
        this.lastHeartbeat = Instant.now();
    }

    /**
     * Update last metrics
     */
    public void updateMetrics(Metrics metrics) {
        this.lastMetrics = metrics;
        this.lastMetricsAt = Instant.now();
    }

    /**
     * Update last metrics time
     */
    public void updateLastMetricsAt() {
        this.lastMetricsAt = Instant.now();
    }

    /**
     * Close the connection
     */
    public void close() {
        active = false;
        pendingCommands.values().forEach(f -> f.completeExceptionally(new IllegalStateException("Connection closed")));
        pendingCommands.clear();
    }

    /**
     * Check if connection is active
     */
    public boolean isActive() {
        return active;
    }

    // Command shortcuts

    /**
     * List processes on the agent
     */
    public CompletableFuture<Command.Result> listProcesses() {
        return sendCommand(Command.processList());
    }

    /**
     * Kill a process
     */
    public CompletableFuture<Command.Result> killProcess(String target) {
        return sendCommand(Command.processKill(target));
    }

    /**
     * Restart a service
     */
    public CompletableFuture<Command.Result> restartService(String serviceName) {
        return sendCommand(Command.serviceRestart(serviceName));
    }

    /**
     * Get service status
     */
    public CompletableFuture<Command.Result> serviceStatus(String serviceName) {
        return sendCommand(Command.serviceStatus(serviceName));
    }

    /**
     * Restart a Docker container
     */
    public CompletableFuture<Command.Result> restartContainer(String containerName) {
        return sendCommand(Command.dockerRestart(containerName));
    }

    /**
     * Get Docker container logs
     */
    public CompletableFuture<Command.Result> containerLogs(String containerName, int lines) {
        return sendCommand(Command.dockerLogs(containerName, lines));
    }

    /**
     * Tail a file
     */
    public CompletableFuture<Command.Result> tailFile(String path, int lines) {
        return sendCommand(Command.fileTail(path, lines));
    }

    // Getters

    public String getAgentId() {
        return agentId;
    }

    public String getHostname() {
        return hostname;
    }

    public String getAgentVersion() {
        return agentVersion;
    }

    public String getOs() {
        return os;
    }

    public String getArch() {
        return arch;
    }

    public int getPermissionLevel() {
        return permissionLevel;
    }

    public Instant getConnectedAt() {
        return connectedAt;
    }

    public Instant getLastHeartbeat() {
        return lastHeartbeat;
    }

    public Metrics getLastMetrics() {
        return lastMetrics;
    }

    public Instant getLastMetricsAt() {
        return lastMetricsAt;
    }
}
