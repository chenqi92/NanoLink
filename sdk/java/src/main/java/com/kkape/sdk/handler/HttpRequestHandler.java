package com.kkape.sdk.handler;

import io.netty.buffer.ByteBuf;
import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelFutureListener;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.SimpleChannelInboundHandler;
import io.netty.handler.codec.http.*;
import io.netty.util.CharsetUtil;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.HashMap;
import java.util.Map;

/**
 * HTTP request handler for WebSocket and API endpoints.
 * 
 * <p>
 * Note: Dashboard functionality has been removed from the SDK.
 * Use the dashboard from the demo projects or implement your own frontend.
 * </p>
 */
public class HttpRequestHandler extends SimpleChannelInboundHandler<FullHttpRequest> {
    private static final Logger log = LoggerFactory.getLogger(HttpRequestHandler.class);

    private final String wsPath;
    private final String staticFilesPath;

    private static final Map<String, String> MIME_TYPES = new HashMap<>();

    static {
        MIME_TYPES.put("html", "text/html");
        MIME_TYPES.put("css", "text/css");
        MIME_TYPES.put("js", "application/javascript");
        MIME_TYPES.put("json", "application/json");
        MIME_TYPES.put("png", "image/png");
        MIME_TYPES.put("jpg", "image/jpeg");
        MIME_TYPES.put("jpeg", "image/jpeg");
        MIME_TYPES.put("gif", "image/gif");
        MIME_TYPES.put("svg", "image/svg+xml");
        MIME_TYPES.put("ico", "image/x-icon");
        MIME_TYPES.put("woff", "font/woff");
        MIME_TYPES.put("woff2", "font/woff2");
        MIME_TYPES.put("ttf", "font/ttf");
    }

    public HttpRequestHandler(String wsPath) {
        this(wsPath, null);
    }

    public HttpRequestHandler(String wsPath, String staticFilesPath) {
        this.wsPath = wsPath;
        this.staticFilesPath = staticFilesPath;
    }

    @Override
    protected void channelRead0(ChannelHandlerContext ctx, FullHttpRequest request) throws Exception {
        String uri = request.uri();

        // Pass WebSocket upgrade requests to the next handler
        if (uri.equals(wsPath) || uri.startsWith(wsPath + "?")) {
            ctx.fireChannelRead(request.retain());
            return;
        }

        // Handle API endpoints
        if (uri.startsWith("/api/")) {
            handleApiRequest(ctx, request);
            return;
        }

        // Serve static files if path is configured
        if (staticFilesPath != null) {
            handleStaticFile(ctx, request);
            return;
        }

        // No static files configured - return a simple info page
        sendInfoPage(ctx);
    }

    private void handleApiRequest(ChannelHandlerContext ctx, FullHttpRequest request) {
        String uri = request.uri();

        if (uri.equals("/api/agents")) {
            // Return list of connected agents (simplified)
            String json = "{\"agents\": []}";
            sendJsonResponse(ctx, json);
        } else if (uri.equals("/api/health")) {
            sendJsonResponse(ctx, "{\"status\": \"ok\"}");
        } else {
            sendNotFound(ctx);
        }
    }

    private void handleStaticFile(ChannelHandlerContext ctx, FullHttpRequest request) {
        String uri = request.uri();

        // Default to index.html
        if (uri.equals("/") || uri.isEmpty()) {
            uri = "/index.html";
        }

        // Remove query string
        int queryIndex = uri.indexOf('?');
        if (queryIndex > 0) {
            uri = uri.substring(0, queryIndex);
        }

        // Security: prevent path traversal
        if (uri.contains("..")) {
            sendForbidden(ctx);
            return;
        }

        // Try to load from external path
        Path filePath = Paths.get(staticFilesPath, uri);
        if (Files.exists(filePath) && Files.isRegularFile(filePath)) {
            try {
                byte[] content = Files.readAllBytes(filePath);
                String contentType = getMimeType(uri);
                sendResponse(ctx, content, contentType);
                return;
            } catch (IOException e) {
                log.error("Error reading file: {}", filePath, e);
            }
        }

        sendNotFound(ctx);
    }

    private void sendInfoPage(ChannelHandlerContext ctx) {
        String html = "<!DOCTYPE html>\n" +
                "<html><head><title>NanoLink Server</title></head>\n" +
                "<body style=\"font-family:sans-serif;padding:40px;background:#0f172a;color:#e2e8f0\">\n" +
                "<h1>NanoLink Server</h1>\n" +
                "<p>The server is running. WebSocket endpoint: <code>" + wsPath + "</code></p>\n" +
                "<p>To use a dashboard, configure static file serving or use the demo projects.</p>\n" +
                "<p><a href=\"/api/health\" style=\"color:#3b82f6\">Health Check API</a></p>\n" +
                "</body></html>";
        sendResponse(ctx, html.getBytes(CharsetUtil.UTF_8), "text/html");
    }

    private String getMimeType(String path) {
        int dotIndex = path.lastIndexOf('.');
        if (dotIndex > 0) {
            String ext = path.substring(dotIndex + 1).toLowerCase();
            return MIME_TYPES.getOrDefault(ext, "application/octet-stream");
        }
        return "application/octet-stream";
    }

    private void sendResponse(ChannelHandlerContext ctx, byte[] content, String contentType) {
        ByteBuf buffer = Unpooled.wrappedBuffer(content);
        FullHttpResponse response = new DefaultFullHttpResponse(
                HttpVersion.HTTP_1_1, HttpResponseStatus.OK, buffer);

        response.headers().set(HttpHeaderNames.CONTENT_TYPE, contentType);
        response.headers().set(HttpHeaderNames.CONTENT_LENGTH, content.length);
        response.headers().set(HttpHeaderNames.CACHE_CONTROL, "no-cache");

        ctx.writeAndFlush(response).addListener(ChannelFutureListener.CLOSE);
    }

    private void sendJsonResponse(ChannelHandlerContext ctx, String json) {
        sendResponse(ctx, json.getBytes(CharsetUtil.UTF_8), "application/json");
    }

    private void sendNotFound(ChannelHandlerContext ctx) {
        FullHttpResponse response = new DefaultFullHttpResponse(
                HttpVersion.HTTP_1_1, HttpResponseStatus.NOT_FOUND,
                Unpooled.copiedBuffer("Not Found", CharsetUtil.UTF_8));
        response.headers().set(HttpHeaderNames.CONTENT_TYPE, "text/plain");
        ctx.writeAndFlush(response).addListener(ChannelFutureListener.CLOSE);
    }

    private void sendForbidden(ChannelHandlerContext ctx) {
        FullHttpResponse response = new DefaultFullHttpResponse(
                HttpVersion.HTTP_1_1, HttpResponseStatus.FORBIDDEN,
                Unpooled.copiedBuffer("Forbidden", CharsetUtil.UTF_8));
        response.headers().set(HttpHeaderNames.CONTENT_TYPE, "text/plain");
        ctx.writeAndFlush(response).addListener(ChannelFutureListener.CLOSE);
    }

    @Override
    public void exceptionCaught(ChannelHandlerContext ctx, Throwable cause) {
        log.error("HTTP handler error", cause);
        ctx.close();
    }
}
