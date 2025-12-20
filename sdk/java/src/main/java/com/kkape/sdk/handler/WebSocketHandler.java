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
import io.nanolink.proto.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.UUID;

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
            Envelope envelope = Envelope.parseFrom(data);

            switch (envelope.getPayloadCase()) {
                case AUTH_REQUEST:
                    handleAuthRequest(ctx, envelope);
                    break;
                case METRICS:
                    handleMetrics(envelope);
                    break;
                case METRICS_SYNC:
                    handleMetricsSync(envelope);
                    break;
                case COMMAND_RESULT:
                    handleCommandResult(envelope);
                    break;
                case HEARTBEAT:
                    handleHeartbeat(ctx, envelope);
                    break;
                default:
                    log.warn("Unknown message type: {}", envelope.getPayloadCase());
            }
        } catch (Exception e) {
            log.error("Error processing message", e);
        }
    }

    private void handleAuthRequest(ChannelHandlerContext ctx, Envelope envelope) {
        AuthRequest authRequest = envelope.getAuthRequest();

        String token = authRequest.getToken();
        String hostname = authRequest.getHostname();
        String version = authRequest.getAgentVersion();
        String os = authRequest.getOs();
        String arch = authRequest.getArch();

        log.info("Auth request from {} (os={}, arch={}, version={})", hostname, os, arch, version);

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
        AuthResponse.Builder responseBuilder = AuthResponse.newBuilder()
                .setSuccess(success)
                .setPermissionLevel(permissionLevel);

        if (error != null) {
            responseBuilder.setErrorMessage(error);
        }

        Envelope envelope = Envelope.newBuilder()
                .setTimestamp(System.currentTimeMillis())
                .setMessageId(UUID.randomUUID().toString())
                .setAuthResponse(responseBuilder.build())
                .build();

        byte[] data = envelope.toByteArray();
        ctx.writeAndFlush(new BinaryWebSocketFrame(ctx.alloc().buffer().writeBytes(data)));
    }

    private void handleMetrics(Envelope envelope) {
        if (!authenticated) {
            log.warn("Received metrics from unauthenticated agent");
            return;
        }

        io.nanolink.proto.Metrics protoMetrics = envelope.getMetrics();

        // Convert proto metrics to our model
        Metrics metrics = convertMetrics(protoMetrics);
        if (metrics != null) {
            agent.updateMetrics(metrics);
        }
    }

    private Metrics convertMetrics(io.nanolink.proto.Metrics protoMetrics) {
        Metrics metrics = new Metrics();
        metrics.setTimestamp(protoMetrics.getTimestamp());
        metrics.setHostname(protoMetrics.getHostname());

        // Convert CPU metrics
        if (protoMetrics.hasCpu()) {
            CpuMetrics protoCpu = protoMetrics.getCpu();
            Metrics.CpuMetrics cpu = new Metrics.CpuMetrics();
            cpu.setUsagePercent(protoCpu.getUsagePercent());
            cpu.setCoreCount(protoCpu.getCoreCount());
            metrics.setCpu(cpu);
        }

        // Convert memory metrics
        if (protoMetrics.hasMemory()) {
            MemoryMetrics protoMem = protoMetrics.getMemory();
            Metrics.MemoryMetrics memory = new Metrics.MemoryMetrics();
            memory.setTotal(protoMem.getTotal());
            memory.setUsed(protoMem.getUsed());
            memory.setAvailable(protoMem.getAvailable());
            memory.setSwapTotal(protoMem.getSwapTotal());
            memory.setSwapUsed(protoMem.getSwapUsed());
            metrics.setMemory(memory);
        }

        return metrics;
    }

    private void handleMetricsSync(Envelope envelope) {
        if (!authenticated) {
            return;
        }
        // Handle buffered metrics from agent after reconnection
        MetricsSync sync = envelope.getMetricsSync();
        log.info("Received metrics sync from {} with {} buffered entries",
                agent.getHostname(), sync.getBufferedMetricsCount());

        // Process each buffered metric
        for (io.nanolink.proto.Metrics protoMetrics : sync.getBufferedMetricsList()) {
            Metrics metrics = convertMetrics(protoMetrics);
            if (metrics != null) {
                agent.updateMetrics(metrics);
            }
        }
    }

    private void handleCommandResult(Envelope envelope) {
        if (!authenticated) {
            return;
        }
        io.nanolink.proto.CommandResult protoResult = envelope.getCommandResult();
        log.debug("Received command result from {}: success={}",
                agent.getHostname(), protoResult.getSuccess());

        // Convert proto result to Command.Result
        com.kkape.sdk.model.Command.Result result = new com.kkape.sdk.model.Command.Result();
        result.setCommandId(protoResult.getCommandId());
        result.setSuccess(protoResult.getSuccess());
        result.setOutput(protoResult.getOutput());
        result.setError(protoResult.getError());

        // Notify the agent connection about the result
        agent.handleCommandResult(protoResult.getCommandId(), result);
    }

    private void handleHeartbeat(ChannelHandlerContext ctx, Envelope envelope) {
        if (!authenticated) {
            return;
        }

        agent.updateHeartbeat();

        // Send heartbeat ack
        HeartbeatAck ack = HeartbeatAck.newBuilder()
                .setTimestamp(System.currentTimeMillis())
                .build();

        Envelope ackEnvelope = Envelope.newBuilder()
                .setTimestamp(System.currentTimeMillis())
                .setMessageId(UUID.randomUUID().toString())
                .setHeartbeatAck(ack)
                .build();

        byte[] data = ackEnvelope.toByteArray();
        ctx.writeAndFlush(new BinaryWebSocketFrame(ctx.alloc().buffer().writeBytes(data)));
    }

    @Override
    public void exceptionCaught(ChannelHandlerContext ctx, Throwable cause) {
        log.error("WebSocket error", cause);
        ctx.close();
    }
}
