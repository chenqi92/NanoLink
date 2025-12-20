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
 * Note: Dashboard functionality has been removed from the SDK.
 * Use the dashboard from the demo projects or implement your own frontend.
 * </p>
 * 
 * <p>
 * Architecture:
 * </p>
 * <ul>
 * <li>Agent connections: gRPC (port 39100 by default)</li>
 * <li>Dashboard connections: WebSocket (port 9100 by default)</li>
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

    private Channel serverChannel;
    private Server grpcServer;
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
        log.info("NanoLink Server started on port {} (WebSocket for Dashboard)", config.getWsPort());

        // Start gRPC server for agent connections
        grpcServer = ServerBuilder.forPort(config.getGrpcPort())
                .addService(new NanoLinkServiceImpl(this, config.getTokenValidator()))
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
        private String staticFilesPath;

        /**
         * Set the WebSocket port for dashboard connections (default: 9100)
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

        public NanoLinkServer build() {
            NanoLinkServer server = new NanoLinkServer(config);
            server.setOnAgentConnect(onAgentConnect);
            server.setOnAgentDisconnect(onAgentDisconnect);
            server.setOnMetrics(onMetrics);
            server.setStaticFilesPath(staticFilesPath);
            return server;
        }
    }
}
