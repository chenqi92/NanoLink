package com.kkape.sdk;

import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Function;
import com.google.gson.*;

/**
 * MCP (Model Context Protocol) Server wrapper for NanoLink SDK.
 * 
 * Enables AI/LLM applications like Claude Desktop to interact with
 * NanoLink monitoring servers.
 * 
 * Example:
 * 
 * <pre>
 * NanoLinkServer server = new NanoLinkServer(config);
 * MCPServer mcp = new MCPServer(server);
 * mcp.registerDefaultTools();
 * mcp.serveStdio();
 * </pre>
 */
public class MCPServer {

    /** Maximum allowed message size (1MB) */
    private static final int MAX_MESSAGE_SIZE = 1024 * 1024;

    /** Default timeout for tool execution (milliseconds) */
    private static final long DEFAULT_TOOL_TIMEOUT_MS = 30000;

    private final NanoLinkServer nanoServer;
    private final Map<String, MCPTool> tools = new ConcurrentHashMap<>();
    private final Map<String, MCPResource> resources = new ConcurrentHashMap<>();
    private final Map<String, MCPPrompt> prompts = new ConcurrentHashMap<>();
    private final Gson gson = new GsonBuilder().setPrettyPrinting().create();
    private final ExecutorService toolExecutor = Executors.newCachedThreadPool();
    private volatile boolean running = false;

    public MCPServer(NanoLinkServer nanoServer) {
        this.nanoServer = nanoServer;
    }

    /**
     * Register a custom tool.
     */
    public void registerTool(MCPTool tool) {
        tools.put(tool.getName(), tool);
    }

    /**
     * Register a custom resource.
     */
    public void registerResource(MCPResource resource) {
        resources.put(resource.getUri(), resource);
    }

    /**
     * Register a custom prompt.
     */
    public void registerPrompt(MCPPrompt prompt) {
        prompts.put(prompt.getName(), prompt);
    }

    /**
     * Register default NanoLink tools, resources, and prompts.
     */
    public void registerDefaults() {
        registerDefaultTools();
        registerDefaultResources();
        registerDefaultPrompts();
    }

    /**
     * Run MCP server using stdio transport (for Claude Desktop).
     */
    public void serveStdio() throws IOException {
        running = true;
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        PrintWriter writer = new PrintWriter(System.out, true);

        while (running) {
            String line = reader.readLine();
            if (line == null)
                break;

            // Check message size limit
            if (line.length() > MAX_MESSAGE_SIZE) {
                System.err.println("MCP error: message too large (" + line.length() + " bytes)");
                continue;
            }

            try {
                String response = handleMessage(line);
                if (response != null) {
                    writer.println(response);
                }
            } catch (Exception e) {
                System.err.println("MCP error: " + e.getMessage());
            }
        }
    }

    /**
     * Stop the MCP server.
     */
    public void stop() {
        running = false;
        toolExecutor.shutdown();
    }

    private String handleMessage(String data) {
        try {
            JsonObject msg = JsonParser.parseString(data).getAsJsonObject();

            if (!"2.0".equals(msg.get("jsonrpc").getAsString())) {
                return errorResponse(msg.get("id"), -32600, "Invalid JSON-RPC version");
            }

            String method = msg.get("method").getAsString();
            JsonElement id = msg.get("id");
            JsonObject params = msg.has("params") ? msg.get("params").getAsJsonObject() : new JsonObject();

            switch (method) {
                case "initialize":
                    return handleInitialize(id);
                case "initialized":
                    return null;
                case "tools/list":
                    return handleToolsList(id);
                case "tools/call":
                    return handleToolsCall(id, params);
                case "resources/list":
                    return handleResourcesList(id);
                case "resources/read":
                    return handleResourcesRead(id, params);
                case "prompts/list":
                    return handlePromptsList(id);
                case "prompts/get":
                    return handlePromptsGet(id, params);
                case "ping":
                    return successResponse(id, new JsonObject());
                default:
                    return errorResponse(id, -32601, "Method not found: " + method);
            }
        } catch (Exception e) {
            return errorResponse(null, -32700, "Parse error: " + e.getMessage());
        }
    }

    private String handleInitialize(JsonElement id) {
        JsonObject result = new JsonObject();
        result.addProperty("protocolVersion", "2024-11-05");

        JsonObject serverInfo = new JsonObject();
        serverInfo.addProperty("name", "nanolink-java-sdk");
        serverInfo.addProperty("version", "0.3.1");
        result.add("serverInfo", serverInfo);

        JsonObject capabilities = new JsonObject();
        JsonObject toolsCap = new JsonObject();
        toolsCap.addProperty("listChanged", false);
        capabilities.add("tools", toolsCap);

        JsonObject resourcesCap = new JsonObject();
        resourcesCap.addProperty("subscribe", false);
        resourcesCap.addProperty("listChanged", false);
        capabilities.add("resources", resourcesCap);

        JsonObject promptsCap = new JsonObject();
        promptsCap.addProperty("listChanged", false);
        capabilities.add("prompts", promptsCap);

        result.add("capabilities", capabilities);
        return successResponse(id, result);
    }

    private String handleToolsList(JsonElement id) {
        JsonArray toolsArray = new JsonArray();
        for (MCPTool tool : tools.values()) {
            JsonObject t = new JsonObject();
            t.addProperty("name", tool.getName());
            t.addProperty("description", tool.getDescription());
            t.add("inputSchema", gson.toJsonTree(tool.getInputSchema()));
            toolsArray.add(t);
        }
        JsonObject result = new JsonObject();
        result.add("tools", toolsArray);
        return successResponse(id, result);
    }

    private String handleToolsCall(JsonElement id, JsonObject params) {
        String name = params.get("name").getAsString();
        JsonObject args = params.has("arguments") ? params.get("arguments").getAsJsonObject() : new JsonObject();

        MCPTool tool = tools.get(name);
        if (tool == null) {
            return errorResponse(id, -32602, "Unknown tool: " + name);
        }

        try {
            // Execute tool with timeout
            Future<Object> future = toolExecutor.submit(() -> tool.getHandler().apply(args));
            Object toolResult = future.get(DEFAULT_TOOL_TIMEOUT_MS, TimeUnit.MILLISECONDS);

            JsonArray content = new JsonArray();
            JsonObject textContent = new JsonObject();
            textContent.addProperty("type", "text");
            textContent.addProperty("text", gson.toJson(toolResult));
            content.add(textContent);

            JsonObject result = new JsonObject();
            result.add("content", content);
            return successResponse(id, result);
        } catch (TimeoutException e) {
            JsonArray content = new JsonArray();
            JsonObject textContent = new JsonObject();
            textContent.addProperty("type", "text");
            textContent.addProperty("text",
                    "Error: tool execution timed out after " + (DEFAULT_TOOL_TIMEOUT_MS / 1000) + "s");
            content.add(textContent);

            JsonObject result = new JsonObject();
            result.add("content", content);
            result.addProperty("isError", true);
            return successResponse(id, result);
        } catch (Exception e) {
            JsonArray content = new JsonArray();
            JsonObject textContent = new JsonObject();
            textContent.addProperty("type", "text");
            textContent.addProperty("text",
                    "Error: " + (e.getCause() != null ? e.getCause().getMessage() : e.getMessage()));
            content.add(textContent);

            JsonObject result = new JsonObject();
            result.add("content", content);
            result.addProperty("isError", true);
            return successResponse(id, result);
        }
    }

    private String handleResourcesList(JsonElement id) {
        JsonArray resourcesArray = new JsonArray();
        for (MCPResource resource : resources.values()) {
            JsonObject r = new JsonObject();
            r.addProperty("uri", resource.getUri());
            r.addProperty("name", resource.getName());
            r.addProperty("description", resource.getDescription());
            r.addProperty("mimeType", resource.getMimeType());
            resourcesArray.add(r);
        }
        JsonObject result = new JsonObject();
        result.add("resources", resourcesArray);
        return successResponse(id, result);
    }

    private String handleResourcesRead(JsonElement id, JsonObject params) {
        String uri = params.get("uri").getAsString();
        MCPResource resource = resources.get(uri);
        if (resource == null) {
            return errorResponse(id, -32602, "Unknown resource: " + uri);
        }

        String content = resource.getHandler().apply(uri);
        JsonArray contents = new JsonArray();
        JsonObject c = new JsonObject();
        c.addProperty("uri", uri);
        c.addProperty("mimeType", resource.getMimeType());
        c.addProperty("text", content);
        contents.add(c);

        JsonObject result = new JsonObject();
        result.add("contents", contents);
        return successResponse(id, result);
    }

    private String handlePromptsList(JsonElement id) {
        JsonArray promptsArray = new JsonArray();
        for (MCPPrompt prompt : prompts.values()) {
            JsonObject p = new JsonObject();
            p.addProperty("name", prompt.getName());
            p.addProperty("description", prompt.getDescription());
            p.add("arguments", gson.toJsonTree(prompt.getArguments()));
            promptsArray.add(p);
        }
        JsonObject result = new JsonObject();
        result.add("prompts", promptsArray);
        return successResponse(id, result);
    }

    private String handlePromptsGet(JsonElement id, JsonObject params) {
        String name = params.get("name").getAsString();
        JsonObject args = params.has("arguments") ? params.get("arguments").getAsJsonObject() : new JsonObject();

        MCPPrompt prompt = prompts.get(name);
        if (prompt == null) {
            return errorResponse(id, -32602, "Unknown prompt: " + name);
        }

        List<Map<String, Object>> messages = prompt.getGenerator().apply(args);
        JsonObject result = new JsonObject();
        result.addProperty("description", prompt.getDescription());
        result.add("messages", gson.toJsonTree(messages));
        return successResponse(id, result);
    }

    private String successResponse(JsonElement id, JsonObject result) {
        JsonObject response = new JsonObject();
        response.addProperty("jsonrpc", "2.0");
        response.add("id", id);
        response.add("result", result);
        return gson.toJson(response);
    }

    private String errorResponse(JsonElement id, int code, String message) {
        JsonObject response = new JsonObject();
        response.addProperty("jsonrpc", "2.0");
        response.add("id", id);
        JsonObject error = new JsonObject();
        error.addProperty("code", code);
        error.addProperty("message", message);
        response.add("error", error);
        return gson.toJson(response);
    }

    // ========================
    // Default registrations
    // ========================

    private void registerDefaultTools() {
        registerTool(new MCPTool(
                "list_agents",
                "List all connected monitoring agents",
                Map.of("type", "object", "properties", Map.of()),
                args -> {
                    var agents = nanoServer.getAgents();
                    List<Map<String, Object>> result = new ArrayList<>();
                    for (var entry : agents.entrySet()) {
                        result.add(Map.of(
                                "id", entry.getKey(),
                                "hostname", entry.getValue().getHostname(),
                                "os", entry.getValue().getOs(),
                                "arch", entry.getValue().getArch()));
                    }
                    return Map.of("count", result.size(), "agents", result);
                }));

        // get_system_summary
        registerTool(new MCPTool(
                "get_system_summary",
                "Get a summary of the entire monitored cluster including agent count and average resource usage",
                Map.of("type", "object", "properties", Map.of()),
                args -> {
                    var agents = nanoServer.getAgents();
                    double totalCpu = 0;
                    long totalMemUsed = 0;
                    long totalMemTotal = 0;
                    int count = 0;

                    for (var agent : agents.values()) {
                        var metrics = agent.getLastMetrics();
                        if (metrics != null) {
                            if (metrics.getCpu() != null) {
                                totalCpu += metrics.getCpu().getUsagePercent();
                            }
                            if (metrics.getMemory() != null) {
                                totalMemUsed += metrics.getMemory().getUsed();
                                totalMemTotal += metrics.getMemory().getTotal();
                            }
                            count++;
                        }
                    }

                    double avgCpu = count > 0 ? totalCpu / count : 0;
                    double memPercent = totalMemTotal > 0 ? (double) totalMemUsed / totalMemTotal * 100 : 0;

                    return Map.of(
                            "agentCount", agents.size(),
                            "avgCpuPercent", avgCpu,
                            "totalMemory", totalMemTotal,
                            "usedMemory", totalMemUsed,
                            "memoryPercent", memPercent);
                }));

        // find_high_cpu_agents
        registerTool(new MCPTool(
                "find_high_cpu_agents",
                "Find agents with CPU usage above a specified threshold",
                Map.of("type", "object", "properties",
                        Map.of("threshold",
                                Map.of("type", "number", "description", "CPU threshold percentage (default: 80)",
                                        "default", 80))),
                args -> {
                    double threshold = args.has("threshold") ? args.get("threshold").getAsDouble() : 80;
                    if (threshold < 0 || threshold > 100) {
                        throw new IllegalArgumentException("threshold must be between 0 and 100");
                    }

                    var agents = nanoServer.getAgents();
                    List<Map<String, Object>> highCpu = new ArrayList<>();

                    for (var entry : agents.entrySet()) {
                        var metrics = entry.getValue().getLastMetrics();
                        if (metrics != null && metrics.getCpu() != null
                                && metrics.getCpu().getUsagePercent() > threshold) {
                            highCpu.add(Map.of(
                                    "id", entry.getKey(),
                                    "hostname", entry.getValue().getHostname(),
                                    "cpuUsage", metrics.getCpu().getUsagePercent()));
                        }
                    }

                    return Map.of("threshold", threshold, "count", highCpu.size(), "agents", highCpu);
                }));
    }

    private void registerDefaultResources() {
        registerResource(new MCPResource(
                "nanolink://agents",
                "Connected Agents",
                "List of all connected monitoring agents",
                "application/json",
                uri -> {
                    var agents = nanoServer.getAgents();
                    List<Map<String, Object>> result = new ArrayList<>();
                    for (var entry : agents.entrySet()) {
                        result.add(Map.of(
                                "id", entry.getKey(),
                                "hostname", entry.getValue().getHostname()));
                    }
                    return gson.toJson(Map.of("count", result.size(), "agents", result));
                }));
    }

    private void registerDefaultPrompts() {
        registerPrompt(new MCPPrompt(
                "troubleshoot_agent",
                "Troubleshoot a specific agent",
                List.of(Map.of("name", "agent_id", "description", "Agent ID", "required", true)),
                args -> {
                    String agentId = args.has("agent_id") ? args.get("agent_id").getAsString() : "unknown";
                    return List.of(Map.of(
                            "role", "user",
                            "content", Map.of(
                                    "type", "text",
                                    "text", "Troubleshoot agent: " + agentId
                                            + "\n\n1. Use list_agents\n2. Use get_agent_metrics")));
                }));
    }

    // ========================
    // Inner classes
    // ========================

    public static class MCPTool {
        private final String name;
        private final String description;
        private final Map<String, Object> inputSchema;
        private final Function<JsonObject, Object> handler;

        public MCPTool(String name, String description, Map<String, Object> inputSchema,
                Function<JsonObject, Object> handler) {
            this.name = name;
            this.description = description;
            this.inputSchema = inputSchema;
            this.handler = handler;
        }

        public String getName() {
            return name;
        }

        public String getDescription() {
            return description;
        }

        public Map<String, Object> getInputSchema() {
            return inputSchema;
        }

        public Function<JsonObject, Object> getHandler() {
            return handler;
        }
    }

    public static class MCPResource {
        private final String uri;
        private final String name;
        private final String description;
        private final String mimeType;
        private final Function<String, String> handler;

        public MCPResource(String uri, String name, String description, String mimeType,
                Function<String, String> handler) {
            this.uri = uri;
            this.name = name;
            this.description = description;
            this.mimeType = mimeType;
            this.handler = handler;
        }

        public String getUri() {
            return uri;
        }

        public String getName() {
            return name;
        }

        public String getDescription() {
            return description;
        }

        public String getMimeType() {
            return mimeType;
        }

        public Function<String, String> getHandler() {
            return handler;
        }
    }

    public static class MCPPrompt {
        private final String name;
        private final String description;
        private final List<Map<String, Object>> arguments;
        private final Function<JsonObject, List<Map<String, Object>>> generator;

        public MCPPrompt(String name, String description, List<Map<String, Object>> arguments,
                Function<JsonObject, List<Map<String, Object>>> generator) {
            this.name = name;
            this.description = description;
            this.arguments = arguments;
            this.generator = generator;
        }

        public String getName() {
            return name;
        }

        public String getDescription() {
            return description;
        }

        public List<Map<String, Object>> getArguments() {
            return arguments;
        }

        public Function<JsonObject, List<Map<String, Object>>> getGenerator() {
            return generator;
        }
    }
}
