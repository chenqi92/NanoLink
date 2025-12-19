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
 */
@Configuration
public class NanoLinkConfig {

    private static final Logger log = LoggerFactory.getLogger(NanoLinkConfig.class);

    @Value("${nanolink.server.port:9100}")
    private int serverPort;

    @Value("${nanolink.server.dashboard.enabled:true}")
    private boolean dashboardEnabled;

    @Value("${nanolink.server.token:}")
    private String serverToken;

    private NanoLinkServer nanoLinkServer;

    /**
     * Creates and configures the NanoLink server
     */
    @Bean
    public NanoLinkServer nanoLinkServer(MetricsService metricsService) {
        log.info("Starting NanoLink Server on port {}", serverPort);

        nanoLinkServer = NanoLinkServer.builder()
                .port(serverPort)
                .enableDashboard(dashboardEnabled)
                .tokenValidator(createTokenValidator())
                .onAgentConnect(agent -> {
                    log.info("Agent connected: {} ({})", agent.getHostname(), agent.getAgentId());
                    log.info("  OS: {}/{}", agent.getOs(), agent.getArch());
                    log.info("  Version: {}", agent.getVersion());
                    metricsService.registerAgent(agent);
                })
                .onAgentDisconnect(agent -> {
                    log.info("Agent disconnected: {} ({})", agent.getHostname(), agent.getAgentId());
                    metricsService.unregisterAgent(agent);
                })
                .onMetrics(metrics -> {
                    metricsService.processMetrics(metrics);
                })
                .build();

        // Start server in background
        new Thread(() -> {
            try {
                nanoLinkServer.start();
            } catch (Exception e) {
                log.error("Failed to start NanoLink server", e);
            }
        }, "nanolink-server").start();

        log.info("NanoLink Server started successfully");
        if (dashboardEnabled) {
            log.info("Dashboard available at http://localhost:{}/", serverPort);
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
