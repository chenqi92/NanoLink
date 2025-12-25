package com.kkape.sdk;

import com.kkape.sdk.model.Metrics;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;

import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Tests for NanoLinkServer
 */
class NanoLinkServerTest {

    @Test
    @DisplayName("Builder creates server with default config")
    void testBuilderDefaultConfig() {
        NanoLinkServer server = NanoLinkServer.builder().build();

        assertNotNull(server);
        assertNotNull(server.getConfig());
        assertEquals(NanoLinkConfig.DEFAULT_GRPC_PORT, server.getConfig().getGrpcPort());
    }

    @Test
    @DisplayName("Builder creates server with custom gRPC port")
    void testBuilderCustomPorts() {
        NanoLinkServer server = NanoLinkServer.builder()
                .grpcPort(40000)
                .build();

        assertEquals(40000, server.getConfig().getGrpcPort());
    }

    @Test
    @DisplayName("Builder creates server with TLS config")
    void testBuilderTlsConfig() {
        NanoLinkServer server = NanoLinkServer.builder()
                .tlsCert("/path/to/cert.pem")
                .tlsKey("/path/to/key.pem")
                .build();

        assertEquals("/path/to/cert.pem", server.getConfig().getTlsCertPath());
        assertEquals("/path/to/key.pem", server.getConfig().getTlsKeyPath());
    }

    @Test
    @DisplayName("Builder sets onAgentConnect callback")
    void testBuilderOnAgentConnect() {
        AtomicBoolean called = new AtomicBoolean(false);

        NanoLinkServer server = NanoLinkServer.builder()
                .onAgentConnect(agent -> called.set(true))
                .build();

        assertNotNull(server);
    }

    @Test
    @DisplayName("Builder sets onMetrics callback")
    void testBuilderOnMetrics() {
        AtomicReference<Metrics> receivedMetrics = new AtomicReference<>();

        NanoLinkServer server = NanoLinkServer.builder()
                .onMetrics(receivedMetrics::set)
                .build();

        assertNotNull(server);
    }

    @Test
    @DisplayName("Server returns empty agents map initially")
    void testGetAgentsEmpty() {
        NanoLinkServer server = NanoLinkServer.builder().build();

        assertTrue(server.getAgents().isEmpty());
    }

    @Test
    @DisplayName("Server returns null for non-existent agent by ID")
    void testGetAgentByIdNotFound() {
        NanoLinkServer server = NanoLinkServer.builder().build();

        assertNull(server.getAgent("non-existent-id"));
    }

    @Test
    @DisplayName("Server returns null for non-existent agent by hostname")
    void testGetAgentByHostnameNotFound() {
        NanoLinkServer server = NanoLinkServer.builder().build();

        assertNull(server.getAgentByHostname("non-existent-host"));
    }

    @Test
    @DisplayName("Builder sets custom token validator")
    void testBuilderTokenValidator() {
        TokenValidator validator = token -> {
            if ("valid-token".equals(token)) {
                return new TokenValidator.ValidationResult(true, 3, null);
            }
            return new TokenValidator.ValidationResult(false, 0, "Invalid token");
        };

        NanoLinkServer server = NanoLinkServer.builder()
                .tokenValidator(validator)
                .build();

        TokenValidator.ValidationResult result = server.getConfig()
                .getTokenValidator()
                .validate("valid-token");

        assertTrue(result.isValid());
        assertEquals(3, result.getPermissionLevel());
    }

    @Test
    @DisplayName("Builder creates server with all options")
    void testBuilderFullConfig() {
        NanoLinkServer server = NanoLinkServer.builder()
                .grpcPort(39200)
                .tlsCert("/cert.pem")
                .tlsKey("/key.pem")
                .onAgentConnect(agent -> {
                })
                .onAgentDisconnect(agent -> {
                })
                .onMetrics(metrics -> {
                })
                .build();

        NanoLinkConfig config = server.getConfig();
        assertEquals(39200, config.getGrpcPort());
        assertEquals("/cert.pem", config.getTlsCertPath());
        assertEquals("/key.pem", config.getTlsKeyPath());
    }
}
