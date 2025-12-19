package com.kkape.sdk;

import io.netty.channel.Channel;
import io.netty.handler.codec.http.websocketx.BinaryWebSocketFrame;
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

/**
 * Represents a connection to a monitoring agent
 */
public class AgentConnection {
    private static final Logger log = LoggerFactory.getLogger(AgentConnection.class);

    private final String agentId;
    private final Channel channel;
    private final NanoLinkServer server;

    private String hostname;
    private String agentVersion;
    private String os;
    private String arch;
    private int permissionLevel;
    private Instant connectedAt;
    private Instant lastHeartbeat;
    private Metrics lastMetrics;

    private final Map<String, CompletableFuture<Command.Result>> pendingCommands = new ConcurrentHashMap<>();

    public AgentConnection(Channel channel, NanoLinkServer server) {
        this.agentId = UUID.randomUUID().toString();
        this.channel = channel;
        this.server = server;
        this.connectedAt = Instant.now();
        this.lastHeartbeat = Instant.now();
    }

    /**
     * Initialize agent info after authentication
     */
    public void initialize(String hostname, String agentVersion, String os, String arch, int permissionLevel) {
        this.hostname = hostname;
        this.agentVersion = agentVersion;
        this.os = os;
        this.arch = arch;
        this.permissionLevel = permissionLevel;
    }

    /**
     * Send a command to the agent
     */
    public CompletableFuture<Command.Result> sendCommand(Command command) {
        if (!channel.isActive()) {
            return CompletableFuture.failedFuture(new IllegalStateException("Agent not connected"));
        }

        // Check permission
        if (command.getRequiredPermission() > permissionLevel) {
            return CompletableFuture.failedFuture(
                new SecurityException("Insufficient permission. Required: " + command.getRequiredPermission() +
                    ", Have: " + permissionLevel)
            );
        }

        String commandId = UUID.randomUUID().toString();
        command.setCommandId(commandId);

        CompletableFuture<Command.Result> future = new CompletableFuture<>();
        pendingCommands.put(commandId, future);

        // Set timeout
        future.orTimeout(30, TimeUnit.SECONDS)
            .whenComplete((result, error) -> pendingCommands.remove(commandId));

        // Send command
        byte[] data = command.toProtobuf();
        channel.writeAndFlush(new BinaryWebSocketFrame(
            channel.alloc().buffer().writeBytes(data)
        ));

        log.debug("Sent command {} to agent {}", command.getType(), hostname);
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
        server.handleMetrics(metrics);
    }

    /**
     * Close the connection
     */
    public void close() {
        if (channel.isActive()) {
            channel.close();
        }
        pendingCommands.values().forEach(f ->
            f.completeExceptionally(new IllegalStateException("Connection closed"))
        );
        pendingCommands.clear();
    }

    /**
     * Check if connection is active
     */
    public boolean isActive() {
        return channel.isActive();
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

    public Channel getChannel() {
        return channel;
    }
}
