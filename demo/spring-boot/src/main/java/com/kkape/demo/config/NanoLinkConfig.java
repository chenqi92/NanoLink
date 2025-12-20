package com.kkape.demo.config;

import com.kkape.sdk.NanoLinkServer;
import com.kkape.sdk.TokenValidator;
import com.kkape.demo.service.MetricsService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import jakarta.annotation.PreDestroy;

/**
 * NanoLink Server Configuration
 *
 * Configures and starts the NanoLink server to receive metrics from agents.
 * 
 * <p>
 * Architecture:
 * </p>
 * <ul>
 * <li>Agent connections: gRPC (port 39100 by default)</li>
 * <li>Dashboard connections: WebSocket (port 9100 by default)</li>
 * </ul>
 */
@Configuration
public class NanoLinkConfig {

    private static final Logger log = LoggerFactory.getLogger(NanoLinkConfig.class);

    @Value("${nanolink.server.ws-port:9100}")
    private int wsPort;

    @Value("${nanolink.server.grpc-port:39100}")
    private int grpcPort;

    @Value("${nanolink.server.static-files-path:}")
    private String staticFilesPath;

    @Value("${nanolink.server.token:}")
    private String serverToken;

    private NanoLinkServer nanoLinkServer;

    /**
     * Creates and configures the NanoLink server
     */
    @Bean
    public NanoLinkServer nanoLinkServer(MetricsService metricsService) {
        log.info("Starting NanoLink Server - WebSocket port: {}, gRPC port: {}", wsPort, grpcPort);

        var builder = NanoLinkServer.builder()
                .wsPort(wsPort)
                .grpcPort(grpcPort)
                .tokenValidator(createTokenValidator())
                .onAgentConnect(agent -> {
                    log.info("Agent connected: {} ({})", agent.getHostname(), agent.getAgentId());
                    log.info("  OS: {}/{}", agent.getOs(), agent.getArch());
                    log.info("  Version: {}", agent.getAgentVersion());
                    metricsService.registerAgent(agent);
                })
                .onAgentDisconnect(agent -> {
                    log.info("Agent disconnected: {} ({})", agent.getHostname(), agent.getAgentId());
                    metricsService.unregisterAgent(agent);
                })
                .onMetrics(metrics -> {
                    metricsService.processMetrics(metrics);
                });

        // Configure static files path if provided
        if (staticFilesPath != null && !staticFilesPath.isEmpty()) {
            builder.staticFilesPath(staticFilesPath);
        }

        nanoLinkServer = builder.build();

        // Start server in background
        new Thread(() -> {
            try {
                nanoLinkServer.start();
            } catch (Exception e) {
                log.error("Failed to start NanoLink server", e);
            }
        }, "nanolink-server").start();

        log.info("NanoLink Server started successfully");
        if (staticFilesPath != null && !staticFilesPath.isEmpty()) {
            log.info("Dashboard available at http://localhost:{}/", wsPort);
        } else {
            log.info("No static files configured. To enable dashboard, set nanolink.server.static-files-path");
        }

        return nanoLinkServer;
    }

    /**
     * Creates a token validator based on configuration
     */
    private TokenValidator createTokenValidator() {
        if (serverToken == null || serverToken.isEmpty()) {
            // Accept all tokens in development mode
            log.warn("No token configured - accepting all connections (not recommended for production)");
            return token -> new TokenValidator.ValidationResult(true, 3, null);
        }

        return token -> {
            if (serverToken.equals(token)) {
                return new TokenValidator.ValidationResult(true, 3, null);
            }
            // Read-only access for any other token
            return new TokenValidator.ValidationResult(true, 0, null);
        };
    }

    @PreDestroy
    public void shutdown() {
        if (nanoLinkServer != null) {
            log.info("Stopping NanoLink Server...");
            nanoLinkServer.stop();
        }
    }
}
