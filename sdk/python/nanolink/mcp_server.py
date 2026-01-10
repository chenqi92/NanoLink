"""
MCP (Model Context Protocol) Server wrapper for NanoLink SDK.

Provides AI/LLM integration capabilities for NanoLink monitoring servers,
allowing tools like Claude Desktop to interact with the monitoring system.
"""

import asyncio
import json
import sys
from typing import Any, Callable, Optional
from dataclasses import dataclass, field

from .server import NanoLinkServer

# Maximum allowed message size (1MB)
MAX_MESSAGE_SIZE = 1024 * 1024

# Default timeout for tool execution (seconds)
DEFAULT_TOOL_TIMEOUT = 30.0


@dataclass
class MCPTool:
    """Represents an MCP tool that AI can execute."""
    name: str
    description: str
    input_schema: dict
    handler: Callable[[dict], Any]


@dataclass
class MCPResource:
    """Represents an MCP resource that AI can read."""
    uri: str
    name: str
    description: str
    mime_type: str = "application/json"
    handler: Optional[Callable[[str], bytes]] = None


@dataclass
class MCPPrompt:
    """Represents an MCP prompt template."""
    name: str
    description: str
    arguments: list = field(default_factory=list)
    generator: Optional[Callable[[dict], list]] = None


class MCPServer:
    """
    MCP wrapper for NanoLinkServer.
    
    Enables AI/LLM applications to interact with NanoLink monitoring system
    using the Model Context Protocol.
    
    Example:
        srv = NanoLinkServer(ServerConfig(port=39100))
        mcp = MCPServer(srv, with_default_tools=True)
        await mcp.serve_stdio()
    """
    
    def __init__(
        self,
        nano_server: NanoLinkServer,
        with_default_tools: bool = True,
        with_default_resources: bool = True,
        with_default_prompts: bool = True
    ):
        self.nano = nano_server
        self.tools: dict[str, MCPTool] = {}
        self.resources: dict[str, MCPResource] = {}
        self.prompts: dict[str, MCPPrompt] = {}
        self._running = False
        
        if with_default_tools:
            self._register_default_tools()
        if with_default_resources:
            self._register_default_resources()
        if with_default_prompts:
            self._register_default_prompts()
    
    def register_tool(self, tool: MCPTool) -> None:
        """Register a custom tool."""
        self.tools[tool.name] = tool
    
    def register_resource(self, resource: MCPResource) -> None:
        """Register a custom resource."""
        self.resources[resource.uri] = resource
    
    def register_prompt(self, prompt: MCPPrompt) -> None:
        """Register a custom prompt."""
        self.prompts[prompt.name] = prompt
    
    async def serve_stdio(self) -> None:
        """Run MCP server using stdio transport (for Claude Desktop)."""
        self._running = True
        reader = asyncio.StreamReader()
        protocol = asyncio.StreamReaderProtocol(reader)
        await asyncio.get_event_loop().connect_read_pipe(lambda: protocol, sys.stdin)
        
        writer_transport, writer_protocol = await asyncio.get_event_loop().connect_write_pipe(
            asyncio.streams.FlowControlMixin, sys.stdout
        )
        writer = asyncio.StreamWriter(writer_transport, writer_protocol, reader, asyncio.get_event_loop())
        
        while self._running:
            try:
                line = await reader.readline()
                if not line:
                    break
                
                # Check message size limit
                if len(line) > MAX_MESSAGE_SIZE:
                    print(f"MCP error: message too large ({len(line)} bytes)", file=sys.stderr)
                    continue
                
                response = await self._handle_message(line)
                if response:
                    writer.write(response + b'\n')
                    await writer.drain()
            except Exception as e:
                print(f"MCP error: {e}", file=sys.stderr)
    
    def stop(self) -> None:
        """Stop the MCP server."""
        self._running = False
    
    async def _handle_message(self, data: bytes) -> Optional[bytes]:
        """Process incoming JSON-RPC message."""
        try:
            msg = json.loads(data)
        except json.JSONDecodeError:
            return self._error_response(None, -32700, "Parse error")
        
        if msg.get("jsonrpc") != "2.0":
            return self._error_response(msg.get("id"), -32600, "Invalid JSON-RPC version")
        
        method = msg.get("method", "")
        msg_id = msg.get("id")
        params = msg.get("params", {})
        
        handlers = {
            "initialize": self._handle_initialize,
            "initialized": lambda p: None,
            "tools/list": self._handle_tools_list,
            "tools/call": self._handle_tools_call,
            "resources/list": self._handle_resources_list,
            "resources/read": self._handle_resources_read,
            "prompts/list": self._handle_prompts_list,
            "prompts/get": self._handle_prompts_get,
            "ping": lambda p: {},
        }
        
        handler = handlers.get(method)
        if not handler:
            return self._error_response(msg_id, -32601, f"Method not found: {method}")
        
        try:
            result = handler(params)
            if asyncio.iscoroutine(result):
                result = await result
            if result is None:
                return None
            return self._success_response(msg_id, result)
        except Exception as e:
            return self._error_response(msg_id, -32603, str(e))
    
    def _handle_initialize(self, params: dict) -> dict:
        return {
            "protocolVersion": "2024-11-05",
            "serverInfo": {"name": "nanolink-python-sdk", "version": "0.3.1"},
            "capabilities": {
                "tools": {"listChanged": False},
                "resources": {"subscribe": False, "listChanged": False},
                "prompts": {"listChanged": False},
            },
        }
    
    def _handle_tools_list(self, params: dict) -> dict:
        tools = [
            {"name": t.name, "description": t.description, "inputSchema": t.input_schema}
            for t in self.tools.values()
        ]
        return {"tools": tools}
    
    def _handle_tools_call(self, params: dict) -> dict:
        name = params.get("name")
        args = params.get("arguments", {})
        
        tool = self.tools.get(name)
        if not tool:
            raise ValueError(f"Unknown tool: {name}")
        
        try:
            # Execute with timeout using asyncio
            loop = asyncio.get_event_loop()
            if asyncio.iscoroutinefunction(tool.handler):
                result = loop.run_until_complete(
                    asyncio.wait_for(tool.handler(args), timeout=DEFAULT_TOOL_TIMEOUT)
                )
            else:
                result = tool.handler(args)
            content = self._format_result(result)
            return {"content": content}
        except asyncio.TimeoutError:
            return {"content": [{"type": "text", "text": f"Error: tool execution timed out after {DEFAULT_TOOL_TIMEOUT}s"}], "isError": True}
        except Exception as e:
            return {"content": [{"type": "text", "text": f"Error: {e}"}], "isError": True}
    
    def _handle_resources_list(self, params: dict) -> dict:
        resources = [
            {"uri": r.uri, "name": r.name, "description": r.description, "mimeType": r.mime_type}
            for r in self.resources.values()
        ]
        return {"resources": resources}
    
    def _handle_resources_read(self, params: dict) -> dict:
        uri = params.get("uri")
        resource = self.resources.get(uri)
        if not resource:
            raise ValueError(f"Unknown resource: {uri}")
        
        content = resource.handler(uri) if resource.handler else b"{}"
        return {"contents": [{"uri": uri, "mimeType": resource.mime_type, "text": content.decode()}]}
    
    def _handle_prompts_list(self, params: dict) -> dict:
        prompts = [
            {"name": p.name, "description": p.description, "arguments": p.arguments}
            for p in self.prompts.values()
        ]
        return {"prompts": prompts}
    
    def _handle_prompts_get(self, params: dict) -> dict:
        name = params.get("name")
        args = params.get("arguments", {})
        
        prompt = self.prompts.get(name)
        if not prompt:
            raise ValueError(f"Unknown prompt: {name}")
        
        messages = prompt.generator(args) if prompt.generator else []
        return {"description": prompt.description, "messages": messages}
    
    def _success_response(self, msg_id: Any, result: Any) -> bytes:
        return json.dumps({"jsonrpc": "2.0", "id": msg_id, "result": result}).encode()
    
    def _error_response(self, msg_id: Any, code: int, message: str) -> bytes:
        return json.dumps({
            "jsonrpc": "2.0", "id": msg_id,
            "error": {"code": code, "message": message}
        }).encode()
    
    def _format_result(self, result: Any) -> list:
        if isinstance(result, str):
            return [{"type": "text", "text": result}]
        return [{"type": "text", "text": json.dumps(result, indent=2, default=str)}]
    
    # ========================
    # Default registrations
    # ========================
    
    def _register_default_tools(self) -> None:
        self.register_tool(MCPTool(
            name="list_agents",
            description="List all connected monitoring agents",
            input_schema={"type": "object", "properties": {}},
            handler=self._tool_list_agents
        ))
        
        self.register_tool(MCPTool(
            name="get_agent_metrics",
            description="Get current metrics for a specific agent",
            input_schema={
                "type": "object",
                "properties": {"agent_id": {"type": "string", "description": "Agent ID or hostname"}},
                "required": ["agent_id"]
            },
            handler=self._tool_get_agent_metrics
        ))
        
        self.register_tool(MCPTool(
            name="get_system_summary",
            description="Get a summary of the entire monitored cluster including agent count and average resource usage",
            input_schema={"type": "object", "properties": {}},
            handler=self._tool_get_system_summary
        ))
        
        self.register_tool(MCPTool(
            name="find_high_cpu_agents",
            description="Find agents with CPU usage above a specified threshold",
            input_schema={
                "type": "object",
                "properties": {"threshold": {"type": "number", "description": "CPU threshold percentage (default: 80)", "default": 80}}
            },
            handler=self._tool_find_high_cpu_agents
        ))
    
    def _register_default_resources(self) -> None:
        self.register_resource(MCPResource(
            uri="nanolink://agents",
            name="Connected Agents",
            description="List of all connected monitoring agents",
            handler=self._resource_agents
        ))
    
    def _register_default_prompts(self) -> None:
        self.register_prompt(MCPPrompt(
            name="troubleshoot_agent",
            description="Troubleshoot a specific agent",
            arguments=[{"name": "agent_id", "description": "Agent ID to troubleshoot", "required": True}],
            generator=self._prompt_troubleshoot_agent
        ))
    
    def _tool_list_agents(self, args: dict) -> dict:
        agents = self.nano.get_agents()
        result = [
            {"id": a.agent_id, "hostname": a.hostname, "os": a.os, "arch": a.arch}
            for a in agents.values()
        ]
        return {"count": len(result), "agents": result}
    
    def _tool_get_agent_metrics(self, args: dict) -> dict:
        agent_id = args.get("agent_id", "")
        agent = self.nano.get_agent(agent_id) or self.nano.get_agent_by_hostname(agent_id)
        if not agent:
            raise ValueError(f"Agent not found: {agent_id}")
        return agent.last_metrics.to_dict() if agent.last_metrics else {}
    
    def _tool_get_system_summary(self, args: dict) -> dict:
        agents = self.nano.get_agents()
        total_cpu = 0.0
        total_mem_used = 0
        total_mem_total = 0
        count = 0
        
        for agent in agents.values():
            if agent.last_metrics:
                total_cpu += agent.last_metrics.cpu.usage_percent if agent.last_metrics.cpu else 0
                if agent.last_metrics.memory:
                    total_mem_used += agent.last_metrics.memory.used
                    total_mem_total += agent.last_metrics.memory.total
                count += 1
        
        avg_cpu = total_cpu / count if count > 0 else 0
        mem_percent = (total_mem_used / total_mem_total * 100) if total_mem_total > 0 else 0
        
        return {
            "agentCount": len(agents),
            "avgCpuPercent": avg_cpu,
            "totalMemory": total_mem_total,
            "usedMemory": total_mem_used,
            "memoryPercent": mem_percent
        }
    
    def _tool_find_high_cpu_agents(self, args: dict) -> dict:
        threshold = args.get("threshold", 80)
        if threshold < 0 or threshold > 100:
            raise ValueError("threshold must be between 0 and 100")
        
        agents = self.nano.get_agents()
        high_cpu = []
        
        for agent in agents.values():
            if agent.last_metrics and agent.last_metrics.cpu:
                if agent.last_metrics.cpu.usage_percent > threshold:
                    high_cpu.append({
                        "id": agent.agent_id,
                        "hostname": agent.hostname,
                        "cpuUsage": agent.last_metrics.cpu.usage_percent
                    })
        
        return {
            "threshold": threshold,
            "count": len(high_cpu),
            "agents": high_cpu
        }
    
    def _resource_agents(self, uri: str) -> bytes:
        result = self._tool_list_agents({})
        return json.dumps(result, indent=2).encode()
    
    def _prompt_troubleshoot_agent(self, args: dict) -> list:
        agent_id = args.get("agent_id", "unknown")
        return [{
            "role": "user",
            "content": {
                "type": "text",
                "text": f"Troubleshoot agent: {agent_id}\n\n1. Use list_agents to verify connection\n2. Use get_agent_metrics to check status"
            }
        }]
