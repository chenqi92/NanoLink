package io.nanolink.sdk.handler;

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
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.HashMap;
import java.util.Map;

/**
 * HTTP request handler for serving dashboard static files
 */
public class HttpRequestHandler extends SimpleChannelInboundHandler<FullHttpRequest> {
    private static final Logger log = LoggerFactory.getLogger(HttpRequestHandler.class);

    private final String wsPath;
    private final String dashboardPath;

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

    public HttpRequestHandler(String wsPath, String dashboardPath) {
        this.wsPath = wsPath;
        this.dashboardPath = dashboardPath;
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

        // Serve static files
        handleStaticFile(ctx, request);
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

        byte[] content = null;
        String contentType = "application/octet-stream";

        // Try to load from external path first
        if (dashboardPath != null) {
            Path filePath = Paths.get(dashboardPath, uri);
            if (Files.exists(filePath) && Files.isRegularFile(filePath)) {
                try {
                    content = Files.readAllBytes(filePath);
                    contentType = getMimeType(uri);
                } catch (IOException e) {
                    log.error("Error reading file: {}", filePath, e);
                }
            }
        }

        // Try to load from classpath (embedded dashboard)
        if (content == null) {
            String resourcePath = "/dashboard" + uri;
            try (InputStream is = getClass().getResourceAsStream(resourcePath)) {
                if (is != null) {
                    content = is.readAllBytes();
                    contentType = getMimeType(uri);
                }
            } catch (IOException e) {
                log.error("Error reading resource: {}", resourcePath, e);
            }
        }

        // If still not found, serve embedded minimal dashboard
        if (content == null && uri.equals("/index.html")) {
            content = getEmbeddedDashboard().getBytes(CharsetUtil.UTF_8);
            contentType = "text/html";
        }

        if (content != null) {
            sendResponse(ctx, content, contentType);
        } else {
            sendNotFound(ctx);
        }
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

    private static final String EMBEDDED_DASHBOARD_HTML = buildEmbeddedDashboard();

    /**
     * Get embedded minimal dashboard HTML
     */
    private String getEmbeddedDashboard() {
        return EMBEDDED_DASHBOARD_HTML;
    }

    /**
     * Build embedded dashboard HTML (Java 11 compatible - no text blocks)
     */
    private static String buildEmbeddedDashboard() {
        StringBuilder sb = new StringBuilder();
        sb.append("<!DOCTYPE html>\n");
        sb.append("<html lang=\"en\">\n");
        sb.append("<head>\n");
        sb.append("    <meta charset=\"UTF-8\">\n");
        sb.append("    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n");
        sb.append("    <title>NanoLink Dashboard</title>\n");
        sb.append("    <style>\n");
        sb.append("        * { margin: 0; padding: 0; box-sizing: border-box; }\n");
        sb.append("        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0f172a; color: #e2e8f0; min-height: 100vh; }\n");
        sb.append("        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }\n");
        sb.append("        header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 30px; }\n");
        sb.append("        h1 { font-size: 24px; font-weight: 600; }\n");
        sb.append("        .status { display: flex; align-items: center; gap: 8px; }\n");
        sb.append("        .status-dot { width: 10px; height: 10px; border-radius: 50%; background: #22c55e; }\n");
        sb.append("        .status-dot.disconnected { background: #ef4444; }\n");
        sb.append("        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(350px, 1fr)); gap: 20px; }\n");
        sb.append("        .card { background: #1e293b; border-radius: 12px; padding: 20px; border: 1px solid #334155; }\n");
        sb.append("        .card-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px; }\n");
        sb.append("        .card-title { font-size: 14px; color: #94a3b8; text-transform: uppercase; letter-spacing: 0.5px; }\n");
        sb.append("        .card-value { font-size: 32px; font-weight: 700; }\n");
        sb.append("        .card-subtitle { font-size: 12px; color: #64748b; margin-top: 5px; }\n");
        sb.append("        .progress-bar { height: 6px; background: #334155; border-radius: 3px; margin-top: 10px; overflow: hidden; }\n");
        sb.append("        .progress-fill { height: 100%; border-radius: 3px; transition: width 0.3s; }\n");
        sb.append("        .progress-fill.cpu { background: linear-gradient(90deg, #3b82f6, #8b5cf6); }\n");
        sb.append("        .progress-fill.memory { background: linear-gradient(90deg, #22c55e, #84cc16); }\n");
        sb.append("        .progress-fill.disk { background: linear-gradient(90deg, #f59e0b, #ef4444); }\n");
        sb.append("        .agents { margin-top: 30px; }\n");
        sb.append("        .agents h2 { font-size: 18px; margin-bottom: 15px; }\n");
        sb.append("        .agent-list { display: flex; flex-direction: column; gap: 10px; }\n");
        sb.append("        .agent-item { background: #1e293b; border-radius: 8px; padding: 15px; display: flex; justify-content: space-between; align-items: center; border: 1px solid #334155; }\n");
        sb.append("        .agent-info { display: flex; align-items: center; gap: 12px; }\n");
        sb.append("        .agent-avatar { width: 40px; height: 40px; border-radius: 8px; background: #3b82f6; display: flex; align-items: center; justify-content: center; font-weight: 600; }\n");
        sb.append("        .agent-name { font-weight: 500; }\n");
        sb.append("        .agent-meta { font-size: 12px; color: #64748b; }\n");
        sb.append("        .agent-stats { display: flex; gap: 20px; }\n");
        sb.append("        .agent-stat { text-align: right; }\n");
        sb.append("        .agent-stat-value { font-weight: 600; }\n");
        sb.append("        .agent-stat-label { font-size: 11px; color: #64748b; }\n");
        sb.append("        .no-agents { text-align: center; padding: 40px; color: #64748b; }\n");
        sb.append("    </style>\n");
        sb.append("</head>\n");
        sb.append("<body>\n");
        sb.append("    <div class=\"container\">\n");
        sb.append("        <header>\n");
        sb.append("            <h1>NanoLink Dashboard</h1>\n");
        sb.append("            <div class=\"status\">\n");
        sb.append("                <div class=\"status-dot\" id=\"statusDot\"></div>\n");
        sb.append("                <span id=\"statusText\">Connecting...</span>\n");
        sb.append("            </div>\n");
        sb.append("        </header>\n");
        sb.append("\n");
        sb.append("        <div class=\"grid\" id=\"metricsGrid\">\n");
        sb.append("            <div class=\"card\">\n");
        sb.append("                <div class=\"card-header\">\n");
        sb.append("                    <span class=\"card-title\">CPU Usage</span>\n");
        sb.append("                </div>\n");
        sb.append("                <div class=\"card-value\" id=\"cpuValue\">--</div>\n");
        sb.append("                <div class=\"card-subtitle\" id=\"cpuCores\">-- cores</div>\n");
        sb.append("                <div class=\"progress-bar\"><div class=\"progress-fill cpu\" id=\"cpuBar\" style=\"width: 0%\"></div></div>\n");
        sb.append("            </div>\n");
        sb.append("\n");
        sb.append("            <div class=\"card\">\n");
        sb.append("                <div class=\"card-header\">\n");
        sb.append("                    <span class=\"card-title\">Memory</span>\n");
        sb.append("                </div>\n");
        sb.append("                <div class=\"card-value\" id=\"memValue\">--</div>\n");
        sb.append("                <div class=\"card-subtitle\" id=\"memInfo\">-- / --</div>\n");
        sb.append("                <div class=\"progress-bar\"><div class=\"progress-fill memory\" id=\"memBar\" style=\"width: 0%\"></div></div>\n");
        sb.append("            </div>\n");
        sb.append("\n");
        sb.append("            <div class=\"card\">\n");
        sb.append("                <div class=\"card-header\">\n");
        sb.append("                    <span class=\"card-title\">Disk</span>\n");
        sb.append("                </div>\n");
        sb.append("                <div class=\"card-value\" id=\"diskValue\">--</div>\n");
        sb.append("                <div class=\"card-subtitle\" id=\"diskInfo\">-- / --</div>\n");
        sb.append("                <div class=\"progress-bar\"><div class=\"progress-fill disk\" id=\"diskBar\" style=\"width: 0%\"></div></div>\n");
        sb.append("            </div>\n");
        sb.append("\n");
        sb.append("            <div class=\"card\">\n");
        sb.append("                <div class=\"card-header\">\n");
        sb.append("                    <span class=\"card-title\">Network</span>\n");
        sb.append("                </div>\n");
        sb.append("                <div class=\"card-value\" id=\"netValue\">-- / --</div>\n");
        sb.append("                <div class=\"card-subtitle\">RX / TX</div>\n");
        sb.append("            </div>\n");
        sb.append("        </div>\n");
        sb.append("\n");
        sb.append("        <div class=\"agents\">\n");
        sb.append("            <h2>Connected Agents</h2>\n");
        sb.append("            <div class=\"agent-list\" id=\"agentList\">\n");
        sb.append("                <div class=\"no-agents\">No agents connected</div>\n");
        sb.append("            </div>\n");
        sb.append("        </div>\n");
        sb.append("    </div>\n");
        sb.append("\n");
        sb.append("    <script>\n");
        sb.append("        const wsUrl = `ws://${window.location.host}/ws`;\n");
        sb.append("        let ws = null;\n");
        sb.append("        let agents = new Map();\n");
        sb.append("\n");
        sb.append("        function connect() {\n");
        sb.append("            ws = new WebSocket(wsUrl);\n");
        sb.append("\n");
        sb.append("            ws.onopen = () => {\n");
        sb.append("                document.getElementById('statusDot').classList.remove('disconnected');\n");
        sb.append("                document.getElementById('statusText').textContent = 'Connected';\n");
        sb.append("            };\n");
        sb.append("\n");
        sb.append("            ws.onclose = () => {\n");
        sb.append("                document.getElementById('statusDot').classList.add('disconnected');\n");
        sb.append("                document.getElementById('statusText').textContent = 'Disconnected';\n");
        sb.append("                setTimeout(connect, 3000);\n");
        sb.append("            };\n");
        sb.append("\n");
        sb.append("            ws.onmessage = (event) => {\n");
        sb.append("                // Handle binary protobuf messages\n");
        sb.append("                // For demo, we'll update with random data\n");
        sb.append("            };\n");
        sb.append("        }\n");
        sb.append("\n");
        sb.append("        function formatBytes(bytes) {\n");
        sb.append("            if (bytes === 0) return '0 B';\n");
        sb.append("            const k = 1024;\n");
        sb.append("            const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];\n");
        sb.append("            const i = Math.floor(Math.log(bytes) / Math.log(k));\n");
        sb.append("            return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];\n");
        sb.append("        }\n");
        sb.append("\n");
        sb.append("        function updateMetrics(metrics) {\n");
        sb.append("            if (metrics.cpu) {\n");
        sb.append("                document.getElementById('cpuValue').textContent = metrics.cpu.usagePercent.toFixed(1) + '%';\n");
        sb.append("                document.getElementById('cpuCores').textContent = metrics.cpu.coreCount + ' cores';\n");
        sb.append("                document.getElementById('cpuBar').style.width = metrics.cpu.usagePercent + '%';\n");
        sb.append("            }\n");
        sb.append("\n");
        sb.append("            if (metrics.memory) {\n");
        sb.append("                const memPercent = (metrics.memory.used / metrics.memory.total * 100).toFixed(1);\n");
        sb.append("                document.getElementById('memValue').textContent = memPercent + '%';\n");
        sb.append("                document.getElementById('memInfo').textContent = formatBytes(metrics.memory.used) + ' / ' + formatBytes(metrics.memory.total);\n");
        sb.append("                document.getElementById('memBar').style.width = memPercent + '%';\n");
        sb.append("            }\n");
        sb.append("\n");
        sb.append("            if (metrics.disks && metrics.disks.length > 0) {\n");
        sb.append("                const disk = metrics.disks[0];\n");
        sb.append("                const diskPercent = (disk.used / disk.total * 100).toFixed(1);\n");
        sb.append("                document.getElementById('diskValue').textContent = diskPercent + '%';\n");
        sb.append("                document.getElementById('diskInfo').textContent = formatBytes(disk.used) + ' / ' + formatBytes(disk.total);\n");
        sb.append("                document.getElementById('diskBar').style.width = diskPercent + '%';\n");
        sb.append("            }\n");
        sb.append("\n");
        sb.append("            if (metrics.networks && metrics.networks.length > 0) {\n");
        sb.append("                const net = metrics.networks[0];\n");
        sb.append("                document.getElementById('netValue').textContent =\n");
        sb.append("                    formatBytes(net.rxBytesPerSec) + '/s / ' + formatBytes(net.txBytesPerSec) + '/s';\n");
        sb.append("            }\n");
        sb.append("        }\n");
        sb.append("\n");
        sb.append("        // Demo: simulate metrics updates\n");
        sb.append("        setInterval(() => {\n");
        sb.append("            updateMetrics({\n");
        sb.append("                cpu: { usagePercent: 20 + Math.random() * 30, coreCount: 8 },\n");
        sb.append("                memory: { used: 8 * 1024 * 1024 * 1024, total: 16 * 1024 * 1024 * 1024 },\n");
        sb.append("                disks: [{ used: 200 * 1024 * 1024 * 1024, total: 500 * 1024 * 1024 * 1024 }],\n");
        sb.append("                networks: [{ rxBytesPerSec: Math.random() * 1024 * 1024, txBytesPerSec: Math.random() * 512 * 1024 }]\n");
        sb.append("            });\n");
        sb.append("        }, 1000);\n");
        sb.append("\n");
        sb.append("        connect();\n");
        sb.append("    </script>\n");
        sb.append("</body>\n");
        sb.append("</html>\n");
        return sb.toString();
    }

    @Override
    public void exceptionCaught(ChannelHandlerContext ctx, Throwable cause) {
        log.error("HTTP handler error", cause);
        ctx.close();
    }
}
