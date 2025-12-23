package com.kkape.sdk;

import io.grpc.Server;
import io.grpc.ServerBuilder;
import io.netty.bootstrap.ServerBootstrap;
import io.netty.channel.*;
import io.netty.channel.nio.NioEventLoopGroup;
import io.netty.channel.socket.SocketChannel;
import io.netty.channel.socket.nio.NioServerSocketChannel;
import io.netty.handler.codec.http.HttpObjectAggregator;
import io.netty.handler.codec.http.HttpServerCodec;
import io.netty.handler.codec.http.websocketx.WebSocketServerProtocolHandler;
import io.netty.handler.ssl.SslContext;
import io.netty.handler.ssl.SslContextBuilder;
import io.netty.handler.stream.ChunkedWriteHandler;
import com.kkape.sdk.grpc.NanoLinkServiceImpl;
import com.kkape.sdk.handler.WebSocketHandler;
import com.kkape.sdk.handler.HttpRequestHandler;
import com.kkape.sdk.model.Metrics;
import com.kkape.sdk.model.PeriodicData;
import com.kkape.sdk.model.RealtimeMetrics;
import com.kkape.sdk.model.StaticInfo;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.File;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.function.Consumer;

/**
 * NanoLink Server - receives metrics from agents and provides management
 * interface.
 * 
 * <p>
 * Note: Dashboard functionality should be implemented separately (e.g., in
 * Spring Boot).
 * The SDK provides callbacks and API endpoints for integration.
 * </p>
 * 
 * <p>
 * Architecture:
 * </p>
 * <ul>
 * <li>Agent connections via gRPC (port 39100 by default) - recommended</li>
 * <li>Agent connections via WebSocket (port 9100 by default) - alternative
 * protocol</li>
 * <li>HTTP API endpoints (/api/agents, /api/health) for querying agent
 * state</li>
 * </ul>
 */
public class NanoLinkServer {
    private static final Logger log = LoggerFactory.getLogger(NanoLinkServer.class);

    private final NanoLinkConfig config;
    private final Map<String, AgentConnection> agents = new ConcurrentHashMap<>();
    private final EventLoopGroup bossGroup;
    private final EventLoopGroup workerGroup;

    private Consumer<AgentConnection> onAgentConnect;
    private Consumer<AgentConnection> onAgentDisconnect;
    private Consumer<Metrics> onMetrics;
    private Consumer<RealtimeMetrics> onRealtimeMetrics;
    private Consumer<StaticInfo> onStaticInfo;
    private Consumer<PeriodicData> onPeriodicData;

    private Channel serverChannel;
    private Server grpcServer;
    private NanoLinkServiceImpl grpcServicer;
    private SslContext sslContext;

    /** Optional static files path for serving dashboard */
    private String staticFilesPath;

    private NanoLinkServer(NanoLinkConfig config) {
        this.config = config;
        this.bossGroup = new NioEventLoopGroup(1);
        this.workerGroup = new NioEventLoopGroup();
    }

    /**
     * Create a new builder
     */
    public static Builder builder() {
        return new Builder();
    }

    /**
     * Start the server
     */
    public void start() throws Exception {
        // Setup SSL if configured
        if (config.getTlsCertPath() != null && config.getTlsKeyPath() != null) {
            sslContext = SslContextBuilder.forServer(
                    new File(config.getTlsCertPath()),
                    new File(config.getTlsKeyPath())).build();
            log.info("TLS enabled");
        }

        ServerBootstrap bootstrap = new ServerBootstrap();
        bootstrap.group(bossGroup, workerGroup)
                .channel(NioServerSocketChannel.class)
                .childHandler(new ChannelInitializer<SocketChannel>() {
                    @Override
                    protected void initChannel(SocketChannel ch) {
                        ChannelPipeline pipeline = ch.pipeline();

                        if (sslContext != null) {
                            pipeline.addLast(sslContext.newHandler(ch.alloc()));
                        }

                        pipeline.addLast(new HttpServerCodec());
                        pipeline.addLast(new HttpObjectAggregator(65536));
                        pipeline.addLast(new ChunkedWriteHandler());

                        // Handle HTTP requests (for API and optional static files)
                        pipeline.addLast(new HttpRequestHandler("/ws", staticFilesPath));

                        pipeline.addLast(new WebSocketServerProtocolHandler("/ws", null, true, 65536));
                        pipeline.addLast(new WebSocketHandler(NanoLinkServer.this));
                    }
                })
                .option(ChannelOption.SO_BACKLOG, 128)
                .childOption(ChannelOption.SO_KEEPALIVE, true);

        serverChannel = bootstrap.bind(config.getWsPort()).sync().channel();
        log.info("NanoLink Server started on port {} (WebSocket for Agent connections + HTTP API)", config.getWsPort());

        // Start gRPC server for agent connections with keepalive settings
        grpcServicer = new NanoLinkServiceImpl(this, config.getTokenValidator());
        grpcServer = ServerBuilder.forPort(config.getGrpcPort())
                .addService(grpcServicer)
                .keepAliveTime(30, TimeUnit.SECONDS)
                .keepAliveTimeout(10, TimeUnit.SECONDS)
                .permitKeepAliveTime(10, TimeUnit.SECONDS)
                .permitKeepAliveWithoutCalls(true)
                .maxInboundMessageSize(16 * 1024 * 1024) // 16MB max message size
                .build()
                .start();
        log.info("gRPC Server started on port {} (Agent connections)", config.getGrpcPort());

        if (staticFilesPath != null) {
            log.info("Dashboard available at http://localhost:{}/", config.getWsPort());
        }
    }

    /**
     * Stop the server
     */
    public void stop() {
        log.info("Stopping NanoLink Server...");

        // Stop gRPC server
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

        if (serverChannel != null) {
            serverChannel.close();
        }

        // Disconnect all agents
        agents.values().forEach(AgentConnection::close);
        agents.clear();

        workerGroup.shutdownGracefully();
        bossGroup.shutdownGracefully();

        log.info("NanoLink Server stopped");
    }

    /**
     * Block until the server is closed
     */
    public void awaitTermination() throws InterruptedException {
        if (serverChannel != null) {
            serverChannel.closeFuture().sync();
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
     * Handle incoming realtime metrics (lightweight, sent every second)
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
     * Handle incoming static info (sent once on connect or on request)
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
     * Handle incoming periodic data (disk usage, sessions, etc.)
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
     * Use this to fetch static info, disk usage, network info etc. on demand.
     *
     * @param agentId     The agent ID to request data from
     * @param requestType The type of data to request (use DataRequestType enum values)
     * @return true if request was sent successfully
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
     *
     * @param agentId     The agent ID to request data from
     * @param requestType The type of data to request
     * @param target      Optional target (e.g., specific device or mount point)
     * @return true if request was sent successfully
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
     *
     * @param requestType The type of data to request
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

    void setStaticFilesPath(String path) {
        this.staticFilesPath = path;
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
        private String staticFilesPath;

        /**
         * Set the WebSocket/HTTP port for agent connections and API (default: 9100)
         * <p>
         * This port serves:
         * <ul>
         * <li>WebSocket endpoint (/ws) for agent connections using protobuf</li>
         * <li>HTTP API endpoints (/api/agents, /api/health)</li>
         * </ul>
         */
        public Builder wsPort(int port) {
            config.setWsPort(port);
            return this;
        }

        /**
         * Set the gRPC port for agent connections (default: 39100)
         */
        public Builder grpcPort(int port) {
            config.setGrpcPort(port);
            return this;
        }

        /**
         * @deprecated Use {@link #wsPort(int)} instead
         */
        @Deprecated
        public Builder port(int port) {
            config.setWsPort(port);
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

        /**
         * Set the path to static files directory (for dashboard).
         * If not set, only the API endpoints will be available.
         */
        public Builder staticFilesPath(String path) {
            this.staticFilesPath = path;
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

        /**
         * Set callback for realtime metrics (lightweight, sent every second)
         */
        public Builder onRealtimeMetrics(Consumer<RealtimeMetrics> callback) {
            this.onRealtimeMetrics = callback;
            return this;
        }

        /**
         * Set callback for static info (hardware info, sent once or on request)
         */
        public Builder onStaticInfo(Consumer<StaticInfo> callback) {
            this.onStaticInfo = callback;
            return this;
        }

        /**
         * Set callback for periodic data (disk usage, sessions, etc.)
         */
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
            server.setStaticFilesPath(staticFilesPath);
            return server;
        }
    }
}
