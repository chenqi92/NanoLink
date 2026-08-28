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
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/**
 * NanoOps Server Configuration
 *
 * Configures and starts the NanoOps server to receive metrics from agents.
 * 
 * <p>
 * Architecture:
 * </p>
 * <ul>
 * <li>Agent connections: gRPC (port 39100 by default)</li>
 * </ul>
 */
@Configuration
public class NanoLinkConfig {

    private static final Logger log = LoggerFactory.getLogger(NanoLinkConfig.class);

    @Value("${nanolink.server.grpc-port:39100}")
    private int grpcPort;

    @Value("${nanolink.server.token}")
    private String serverToken;

    private NanoLinkServer nanoLinkServer;

    /**
     * Creates and configures the NanoOps server
     */
    @Bean
    public NanoLinkServer nanoLinkServer(MetricsService metricsService) {
        log.info("Starting NanoOps Server - gRPC port: {}", grpcPort);

        var builder = NanoLinkServer.builder()
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
                })
                .onRealtimeMetrics(realtime -> {
                    metricsService.processRealtimeMetrics(realtime);
                })
                .onStaticInfo(staticInfo -> {
                    metricsService.processStaticInfo(staticInfo);
                })
                .onPeriodicData(periodic -> {
                    metricsService.processPeriodicData(periodic);
                });

        nanoLinkServer = builder.build();

        // Start server in background
        new Thread(() -> {
            try {
                nanoLinkServer.start();
            } catch (Exception e) {
                log.error("Failed to start NanoOps server", e);
            }
        }, "nanolink-server").start();

        log.info("NanoOps Server started successfully");
        return nanoLinkServer;
    }

    /**
     * Creates a token validator based on configuration
     */
    private TokenValidator createTokenValidator() {
        if (serverToken == null || serverToken.getBytes(StandardCharsets.UTF_8).length < 32) {
            throw new IllegalStateException(
                    "nanolink.server.token must be configured with at least 32 bytes");
        }

        return token -> {
            byte[] expected = serverToken.getBytes(StandardCharsets.UTF_8);
            byte[] actual = token == null ? new byte[0] : token.getBytes(StandardCharsets.UTF_8);
            if (MessageDigest.isEqual(expected, actual)) {
                return TokenValidator.ValidationResult.success(TokenValidator.PermissionLevel.SYSTEM_ADMIN);
            }
            return TokenValidator.ValidationResult.failure("Invalid token");
        };
    }

    @PreDestroy
    public void shutdown() {
        if (nanoLinkServer != null) {
            log.info("Stopping NanoOps Server...");
            nanoLinkServer.stop();
        }
    }
}
