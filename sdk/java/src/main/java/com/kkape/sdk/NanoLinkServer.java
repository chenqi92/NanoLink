package com.kkape.sdk;

import io.grpc.Server;
import io.grpc.ServerBuilder;
import com.kkape.sdk.grpc.NanoLinkServiceImpl;
import com.kkape.sdk.model.Metrics;
import com.kkape.sdk.model.PeriodicData;
import com.kkape.sdk.model.RealtimeMetrics;
import com.kkape.sdk.model.StaticInfo;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.function.Consumer;

/**
 * NanoLink gRPC Server - receives metrics from agents.
 *
 * <p>
 * This server only handles gRPC connections from agents.
 * For WebSocket/HTTP API functionality, implement your own server using
 * the callbacks and agent data provided by this class.
 * </p>
 */
@SuppressWarnings("unused") // Public API methods may not be used internally
public class NanoLinkServer {
    private static final Logger log = LoggerFactory.getLogger(NanoLinkServer.class);

    private final NanoLinkConfig config;
    private final Map<String, AgentConnection> agents = new ConcurrentHashMap<>();

    private Consumer<AgentConnection> onAgentConnect;
    private Consumer<AgentConnection> onAgentDisconnect;
    private Consumer<Metrics> onMetrics;
    private Consumer<RealtimeMetrics> onRealtimeMetrics;
    private Consumer<StaticInfo> onStaticInfo;
    private Consumer<PeriodicData> onPeriodicData;

    private Server grpcServer;
    private NanoLinkServiceImpl grpcServicer;

    private NanoLinkServer(NanoLinkConfig config) {
        this.config = config;
    }

    /**
     * Create a new builder
     */
    public static Builder builder() {
        return new Builder();
    }

    /**
     * Start the gRPC server
     */
    public void start() throws Exception {
        grpcServicer = new NanoLinkServiceImpl(this, config.getTokenValidator());
        grpcServer = ServerBuilder.forPort(config.getGrpcPort())
                .addService(grpcServicer)
                .keepAliveTime(30, TimeUnit.SECONDS)
                .keepAliveTimeout(10, TimeUnit.SECONDS)
                .permitKeepAliveTime(10, TimeUnit.SECONDS)
                .permitKeepAliveWithoutCalls(true)
                .maxInboundMessageSize(16 * 1024 * 1024)
                .build()
                .start();
        log.info("NanoLink gRPC Server started on port {}", config.getGrpcPort());
    }

    /**
     * Stop the server
     */
    public void stop() {
        log.info("Stopping NanoLink Server...");

        if (grpcServer != null) {
            grpcServer.shutdown();
            try {
                if (!grpcServer.awaitTermination(5, TimeUnit.SECONDS)) {
                    grpcServer.shutdownNow();
                }
            } catch (InterruptedException e) {
                grpcServer.shutdownNow();
                Thread.currentThread().interrupt();
            }
        }

        agents.values().forEach(AgentConnection::close);
        agents.clear();

        log.info("NanoLink Server stopped");
    }

    /**
     * Block until the server is closed
     */
    public void awaitTermination() throws InterruptedException {
        if (grpcServer != null) {
            grpcServer.awaitTermination();
        }
    }

    /**
     * Register a new agent connection
     */
    public void registerAgent(AgentConnection agent) {
        agents.put(agent.getAgentId(), agent);
        log.info("Agent registered: {} ({})", agent.getHostname(), agent.getAgentId());

        if (onAgentConnect != null) {
            try {
                onAgentConnect.accept(agent);
            } catch (Exception e) {
                log.error("Error in onAgentConnect callback", e);
            }
        }
    }

    /**
     * Unregister an agent connection
     */
    public void unregisterAgent(AgentConnection agent) {
        agents.remove(agent.getAgentId());
        log.info("Agent unregistered: {} ({})", agent.getHostname(), agent.getAgentId());

        if (onAgentDisconnect != null) {
            try {
                onAgentDisconnect.accept(agent);
            } catch (Exception e) {
                log.error("Error in onAgentDisconnect callback", e);
            }
        }
    }

    /**
     * Handle incoming metrics
     */
    public void handleMetrics(Metrics metrics) {
        if (onMetrics != null) {
            try {
                onMetrics.accept(metrics);
            } catch (Exception e) {
                log.error("Error in onMetrics callback", e);
            }
        }
    }

    /**
     * Handle incoming realtime metrics
     */
    public void handleRealtimeMetrics(RealtimeMetrics realtime) {
        if (onRealtimeMetrics != null) {
            try {
                onRealtimeMetrics.accept(realtime);
            } catch (Exception e) {
                log.error("Error in onRealtimeMetrics callback", e);
            }
        }
    }

    /**
     * Handle incoming static info
     */
    public void handleStaticInfo(StaticInfo staticInfo) {
        if (onStaticInfo != null) {
            try {
                onStaticInfo.accept(staticInfo);
            } catch (Exception e) {
                log.error("Error in onStaticInfo callback", e);
            }
        }
    }

    /**
     * Handle incoming periodic data
     */
    public void handlePeriodicData(PeriodicData periodicData) {
        if (onPeriodicData != null) {
            try {
                onPeriodicData.accept(periodicData);
            } catch (Exception e) {
                log.error("Error in onPeriodicData callback", e);
            }
        }
    }

    /**
     * Get agent by ID
     */
    public AgentConnection getAgent(String agentId) {
        return agents.get(agentId);
    }

    /**
     * Get agent by hostname
     */
    public AgentConnection getAgentByHostname(String hostname) {
        return agents.values().stream()
                .filter(a -> a.getHostname().equals(hostname))
                .findFirst()
                .orElse(null);
    }

    /**
     * Get all connected agents
     */
    public Map<String, AgentConnection> getAgents() {
        return Map.copyOf(agents);
    }

    /**
     * Get server configuration
     */
    public NanoLinkConfig getConfig() {
        return config;
    }

    /**
     * Request specific data from an agent.
     */
    public boolean requestData(String agentId, io.nanolink.proto.DataRequestType requestType) {
        if (grpcServicer != null) {
            return grpcServicer.sendDataRequest(agentId, requestType, null);
        }
        log.warn("Cannot send data request - gRPC service not available");
        return false;
    }

    /**
     * Request specific data from an agent with a target parameter.
     */
    public boolean requestData(String agentId, io.nanolink.proto.DataRequestType requestType, String target) {
        if (grpcServicer != null) {
            return grpcServicer.sendDataRequest(agentId, requestType, target);
        }
        log.warn("Cannot send data request - gRPC service not available");
        return false;
    }

    /**
     * Request data from all connected agents.
     */
    public void broadcastDataRequest(io.nanolink.proto.DataRequestType requestType) {
        if (grpcServicer != null) {
            grpcServicer.broadcastDataRequest(requestType);
        } else {
            log.warn("Cannot broadcast data request - gRPC service not available");
        }
    }

    // Setters for callbacks
    void setOnAgentConnect(Consumer<AgentConnection> callback) {
        this.onAgentConnect = callback;
    }

    void setOnAgentDisconnect(Consumer<AgentConnection> callback) {
        this.onAgentDisconnect = callback;
    }

    void setOnMetrics(Consumer<Metrics> callback) {
        this.onMetrics = callback;
    }

    void setOnRealtimeMetrics(Consumer<RealtimeMetrics> callback) {
        this.onRealtimeMetrics = callback;
    }

    void setOnStaticInfo(Consumer<StaticInfo> callback) {
        this.onStaticInfo = callback;
    }

    void setOnPeriodicData(Consumer<PeriodicData> callback) {
        this.onPeriodicData = callback;
    }

    /**
     * Builder for NanoLinkServer
     */
    public static class Builder {
        private final NanoLinkConfig config = new NanoLinkConfig();
        private Consumer<AgentConnection> onAgentConnect;
        private Consumer<AgentConnection> onAgentDisconnect;
        private Consumer<Metrics> onMetrics;
        private Consumer<RealtimeMetrics> onRealtimeMetrics;
        private Consumer<StaticInfo> onStaticInfo;
        private Consumer<PeriodicData> onPeriodicData;

        /**
         * Set the gRPC port for agent connections (default: 39100)
         */
        public Builder grpcPort(int port) {
            config.setGrpcPort(port);
            return this;
        }

        public Builder tlsCert(String certPath) {
            config.setTlsCertPath(certPath);
            return this;
        }

        public Builder tlsKey(String keyPath) {
            config.setTlsKeyPath(keyPath);
            return this;
        }

        public Builder tokenValidator(TokenValidator validator) {
            config.setTokenValidator(validator);
            return this;
        }

        public Builder onAgentConnect(Consumer<AgentConnection> callback) {
            this.onAgentConnect = callback;
            return this;
        }

        public Builder onAgentDisconnect(Consumer<AgentConnection> callback) {
            this.onAgentDisconnect = callback;
            return this;
        }

        public Builder onMetrics(Consumer<Metrics> callback) {
            this.onMetrics = callback;
            return this;
        }

        public Builder onRealtimeMetrics(Consumer<RealtimeMetrics> callback) {
            this.onRealtimeMetrics = callback;
            return this;
        }

        public Builder onStaticInfo(Consumer<StaticInfo> callback) {
            this.onStaticInfo = callback;
            return this;
        }

        public Builder onPeriodicData(Consumer<PeriodicData> callback) {
            this.onPeriodicData = callback;
            return this;
        }

        public NanoLinkServer build() {
            NanoLinkServer server = new NanoLinkServer(config);
            server.setOnAgentConnect(onAgentConnect);
            server.setOnAgentDisconnect(onAgentDisconnect);
            server.setOnMetrics(onMetrics);
            server.setOnRealtimeMetrics(onRealtimeMetrics);
            server.setOnStaticInfo(onStaticInfo);
            server.setOnPeriodicData(onPeriodicData);
            return server;
        }
    }
}
