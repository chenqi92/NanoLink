package com.kkape.sdk.handler;

import io.netty.buffer.ByteBuf;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.SimpleChannelInboundHandler;
import io.netty.handler.codec.http.websocketx.BinaryWebSocketFrame;
import io.netty.handler.codec.http.websocketx.TextWebSocketFrame;
import io.netty.handler.codec.http.websocketx.WebSocketFrame;
import com.kkape.sdk.AgentConnection;
import com.kkape.sdk.NanoLinkServer;
import com.kkape.sdk.TokenValidator;
import com.kkape.sdk.model.Metrics;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * WebSocket handler for agent connections
 */
public class WebSocketHandler extends SimpleChannelInboundHandler<WebSocketFrame> {
    private static final Logger log = LoggerFactory.getLogger(WebSocketHandler.class);

    private final NanoLinkServer server;
    private AgentConnection agent;
    private boolean authenticated = false;

    public WebSocketHandler(NanoLinkServer server) {
        this.server = server;
    }

    @Override
    public void handlerAdded(ChannelHandlerContext ctx) {
        log.debug("New WebSocket connection from {}", ctx.channel().remoteAddress());
        agent = new AgentConnection(ctx.channel(), server);
    }

    @Override
    public void handlerRemoved(ChannelHandlerContext ctx) {
        log.debug("WebSocket connection closed: {}", ctx.channel().remoteAddress());
        if (agent != null && authenticated) {
            server.unregisterAgent(agent);
        }
    }

    @Override
    protected void channelRead0(ChannelHandlerContext ctx, WebSocketFrame frame) {
        if (frame instanceof BinaryWebSocketFrame) {
            handleBinaryFrame(ctx, (BinaryWebSocketFrame) frame);
        } else if (frame instanceof TextWebSocketFrame) {
            // Text frames not expected, but handle gracefully
            log.warn("Received unexpected text frame");
        }
    }

    private void handleBinaryFrame(ChannelHandlerContext ctx, BinaryWebSocketFrame frame) {
        ByteBuf content = frame.content();
        byte[] data = new byte[content.readableBytes()];
        content.readBytes(data);

        try {
            // Parse the protobuf envelope
            // In real implementation, use generated protobuf classes
            // For now, we'll use a simplified parsing

            // Check message type from first few bytes (simplified)
            if (data.length < 4) {
                return;
            }

            // Simplified message type detection
            // In production, properly parse the protobuf Envelope
            int messageType = detectMessageType(data);

            switch (messageType) {
                case 10: // AuthRequest
                    handleAuthRequest(ctx, data);
                    break;
                case 20: // Metrics
                    handleMetrics(data);
                    break;
                case 21: // MetricsSync
                    handleMetricsSync(data);
                    break;
                case 31: // CommandResult
                    handleCommandResult(data);
                    break;
                case 40: // Heartbeat
                    handleHeartbeat(ctx, data);
                    break;
                default:
                    log.warn("Unknown message type: {}", messageType);
            }
        } catch (Exception e) {
            log.error("Error processing message", e);
        }
    }

    private int detectMessageType(byte[] data) {
        // Simplified detection - in production use proper protobuf parsing
        // Look for field numbers in the protobuf data
        for (int i = 0; i < Math.min(data.length, 20); i++) {
            int fieldTag = data[i] & 0xFF;
            int fieldNumber = fieldTag >> 3;
            if (fieldNumber >= 10 && fieldNumber <= 50) {
                return fieldNumber;
            }
        }
        return 0;
    }

    private void handleAuthRequest(ChannelHandlerContext ctx, byte[] data) {
        // Parse auth request (simplified)
        // Extract token, hostname, version, os, arch from protobuf

        // For demo purposes, accept all connections
        // In production, properly parse and validate
        String token = "demo_token";
        String hostname = "unknown";
        String version = "0.1.0";
        String os = "unknown";
        String arch = "unknown";

        // Validate token
        TokenValidator validator = server.getConfig().getTokenValidator();
        TokenValidator.ValidationResult result = validator.validate(token);

        if (result.isValid()) {
            authenticated = true;
            agent.initialize(hostname, version, os, arch, result.getPermissionLevel());
            server.registerAgent(agent);

            // Send auth response
            sendAuthResponse(ctx, true, result.getPermissionLevel(), null);
            log.info("Agent authenticated: {} (permission: {})", hostname, result.getPermissionLevel());
        } else {
            sendAuthResponse(ctx, false, 0, result.getErrorMessage());
            ctx.close();
            log.warn("Agent authentication failed: {}", result.getErrorMessage());
        }
    }

    private void sendAuthResponse(ChannelHandlerContext ctx, boolean success, int permissionLevel, String error) {
        // Build and send auth response protobuf
        // Simplified - in production use generated protobuf classes
        byte[] response = buildAuthResponse(success, permissionLevel, error);
        ctx.writeAndFlush(new BinaryWebSocketFrame(ctx.alloc().buffer().writeBytes(response)));
    }

    private byte[] buildAuthResponse(boolean success, int permissionLevel, String error) {
        // Simplified response building
        // In production, use generated protobuf builders
        return new byte[0];
    }

    private void handleMetrics(byte[] data) {
        if (!authenticated) {
            log.warn("Received metrics from unauthenticated agent");
            return;
        }

        // Parse metrics from protobuf
        Metrics metrics = parseMetrics(data);
        if (metrics != null) {
            agent.updateMetrics(metrics);
        }
    }

    private Metrics parseMetrics(byte[] data) {
        // Simplified parsing - in production use generated protobuf classes
        Metrics metrics = new Metrics();
        metrics.setTimestamp(System.currentTimeMillis());
        metrics.setHostname(agent.getHostname());
        return metrics;
    }

    private void handleMetricsSync(byte[] data) {
        if (!authenticated) {
            return;
        }
        // Handle buffered metrics from agent after reconnection
        log.debug("Received metrics sync from {}", agent.getHostname());
    }

    private void handleCommandResult(byte[] data) {
        if (!authenticated) {
            return;
        }
        // Parse command result and notify waiting future
        // Simplified - in production properly parse the protobuf
        log.debug("Received command result from {}", agent.getHostname());
    }

    private void handleHeartbeat(ChannelHandlerContext ctx, byte[] data) {
        if (!authenticated) {
            return;
        }

        agent.updateHeartbeat();

        // Send heartbeat ack
        byte[] ack = buildHeartbeatAck();
        ctx.writeAndFlush(new BinaryWebSocketFrame(ctx.alloc().buffer().writeBytes(ack)));
    }

    private byte[] buildHeartbeatAck() {
        // Simplified - in production use generated protobuf classes
        return new byte[0];
    }

    @Override
    public void exceptionCaught(ChannelHandlerContext ctx, Throwable cause) {
        log.error("WebSocket error", cause);
        ctx.close();
    }
}
