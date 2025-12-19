package io.nanolink.sdk;

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
import io.nanolink.sdk.handler.WebSocketHandler;
import io.nanolink.sdk.handler.HttpRequestHandler;
import io.nanolink.sdk.model.Metrics;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.File;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Consumer;

/**
 * NanoLink Server - receives metrics from agents and provides management interface
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
    private SslContext sslContext;

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
                new File(config.getTlsKeyPath())
            ).build();
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

                    // Handle HTTP requests (for dashboard)
                    if (config.isDashboardEnabled()) {
                        pipeline.addLast(new HttpRequestHandler("/ws", config.getDashboardPath()));
                    }

                    pipeline.addLast(new WebSocketServerProtocolHandler("/ws", null, true, 65536));
                    pipeline.addLast(new WebSocketHandler(NanoLinkServer.this));
                }
            })
            .option(ChannelOption.SO_BACKLOG, 128)
            .childOption(ChannelOption.SO_KEEPALIVE, true);

        serverChannel = bootstrap.bind(config.getPort()).sync().channel();
        log.info("NanoLink Server started on port {}", config.getPort());

        if (config.isDashboardEnabled()) {
            log.info("Dashboard available at http://localhost:{}/", config.getPort());
        }
    }

    /**
     * Stop the server
     */
    public void stop() {
        log.info("Stopping NanoLink Server...");

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

    /**
     * Builder for NanoLinkServer
     */
    public static class Builder {
        private final NanoLinkConfig config = new NanoLinkConfig();
        private Consumer<AgentConnection> onAgentConnect;
        private Consumer<AgentConnection> onAgentDisconnect;
        private Consumer<Metrics> onMetrics;

        public Builder port(int port) {
            config.setPort(port);
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

        public Builder enableDashboard(boolean enabled) {
            config.setDashboardEnabled(enabled);
            return this;
        }

        public Builder dashboardPath(String path) {
            config.setDashboardPath(path);
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
            return server;
        }
    }
}
