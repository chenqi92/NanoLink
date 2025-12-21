"""
NanoLink Server implementation for Python SDK
"""

import asyncio
import json
import logging
import ssl
import uuid
import threading
from concurrent import futures
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Callable, Dict, Optional, Awaitable, Union

import websockets
from websockets.server import WebSocketServerProtocol, serve
from aiohttp import web

try:
    import grpc
    from .grpc_service import NanoLinkServicer, create_grpc_server
    GRPC_AVAILABLE = True
except ImportError:
    GRPC_AVAILABLE = False

from .connection import (
    AgentConnection,
    AgentInfo,
    ValidationResult,
    TokenValidator,
    default_token_validator,
)
from .metrics import (
    Metrics, RealtimeMetrics, StaticInfo, PeriodicData, DataRequestType
)
from .command import CommandResult

logger = logging.getLogger(__name__)

# Default ports
DEFAULT_GRPC_PORT = 39100
DEFAULT_WS_PORT = 9100


@dataclass
class ServerConfig:
    """
    Server configuration
    
    Attributes:
        ws_port: WebSocket port for dashboard connections (default: 9100)
        grpc_port: gRPC port for agent connections (default: 39100)
        host: Host to bind to
        tls_cert_path: Path to TLS certificate
        tls_key_path: Path to TLS key
        static_files_path: Optional path to dashboard static files
        token_validator: Token validation function
    """
    ws_port: int = DEFAULT_WS_PORT
    grpc_port: int = DEFAULT_GRPC_PORT
    host: str = "0.0.0.0"
    tls_cert_path: Optional[str] = None
    tls_key_path: Optional[str] = None
    static_files_path: Optional[str] = None
    token_validator: TokenValidator = default_token_validator


class NanoLinkServer:
    """
    NanoLink Server - receives metrics from agents and provides management interface

    Example usage:
        server = NanoLinkServer(ServerConfig(port=9100))

        @server.on_agent_connect
        async def handle_connect(agent: AgentConnection):
            print(f"Agent connected: {agent.hostname}")

        @server.on_metrics
        async def handle_metrics(metrics: Metrics):
            print(f"CPU: {metrics.cpu.usage_percent}%")

        await server.start()
    """

    def __init__(self, config: Optional[ServerConfig] = None):
        self.config = config or ServerConfig()
        self._agents: Dict[str, AgentConnection] = {}
        self._websocket_server = None
        self._grpc_server = None
        self._grpc_servicer = None
        self._http_app = None
        self._http_runner = None

        # Callbacks
        self._on_agent_connect: Optional[Callable[[AgentConnection], Awaitable[None]]] = None
        self._on_agent_disconnect: Optional[Callable[[AgentConnection], Awaitable[None]]] = None
        self._on_metrics: Optional[Callable[[Metrics], Awaitable[None]]] = None
        self._on_realtime_metrics: Optional[Callable[[RealtimeMetrics], Awaitable[None]]] = None
        self._on_static_info: Optional[Callable[[StaticInfo], Awaitable[None]]] = None
        self._on_periodic_data: Optional[Callable[[PeriodicData], Awaitable[None]]] = None

    def on_agent_connect(self, callback: Callable[[AgentConnection], Awaitable[None]]):
        """Decorator to set agent connect callback"""
        self._on_agent_connect = callback
        return callback

    def on_agent_disconnect(self, callback: Callable[[AgentConnection], Awaitable[None]]):
        """Decorator to set agent disconnect callback"""
        self._on_agent_disconnect = callback
        return callback

    def on_metrics(self, callback: Callable[[Metrics], Awaitable[None]]):
        """Decorator to set metrics callback"""
        self._on_metrics = callback
        return callback

    def on_realtime_metrics(self, callback: Callable[[RealtimeMetrics], Awaitable[None]]):
        """Decorator to set realtime metrics callback"""
        self._on_realtime_metrics = callback
        return callback

    def on_static_info(self, callback: Callable[[StaticInfo], Awaitable[None]]):
        """Decorator to set static info callback"""
        self._on_static_info = callback
        return callback

    def on_periodic_data(self, callback: Callable[[PeriodicData], Awaitable[None]]):
        """Decorator to set periodic data callback"""
        self._on_periodic_data = callback
        return callback

    @property
    def agents(self) -> Dict[str, AgentConnection]:
        """Get all connected agents"""
        return dict(self._agents)

    def get_agent(self, agent_id: str) -> Optional[AgentConnection]:
        """Get agent by ID"""
        return self._agents.get(agent_id)

    def get_agent_by_hostname(self, hostname: str) -> Optional[AgentConnection]:
        """Get agent by hostname"""
        for agent in self._agents.values():
            if agent.hostname == hostname:
                return agent
        return None

    async def start(self) -> None:
        """Start the server (WebSocket + gRPC)"""
        # Setup SSL if configured
        ssl_context = None
        if self.config.tls_cert_path and self.config.tls_key_path:
            ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            ssl_context.load_cert_chain(
                self.config.tls_cert_path,
                self.config.tls_key_path,
            )
            logger.info("TLS enabled")

        # Start WebSocket server for dashboard connections
        self._websocket_server = await serve(
            self._handle_websocket,
            self.config.host,
            self.config.ws_port,
            ssl=ssl_context,
        )

        logger.info(f"NanoLink Server started on port {self.config.ws_port} (WebSocket for Dashboard)")

        # Start gRPC server for agent connections
        if GRPC_AVAILABLE:
            self._start_grpc_server()
            logger.info(f"gRPC Server started on port {self.config.grpc_port} (Agent connections)")
        else:
            logger.warning("gRPC not available. Install grpcio to enable agent connections via gRPC.")

        if self.config.static_files_path:
            logger.info(f"Dashboard available at http://localhost:{self.config.ws_port}/")

    def _start_grpc_server(self) -> None:
        """Start the gRPC server in a background thread"""
        if not GRPC_AVAILABLE:
            raise RuntimeError("gRPC is not available. Install grpcio and grpcio-tools.")

        # Create callback wrappers that work with both sync and async
        def sync_on_agent_connect(agent: AgentConnection) -> None:
            if self._on_agent_connect:
                self._agents[agent.agent_id] = agent
                try:
                    # Run async callback in event loop if possible
                    loop = asyncio.get_running_loop()
                    asyncio.run_coroutine_threadsafe(self._on_agent_connect(agent), loop)
                except RuntimeError:
                    # No event loop running, just register the agent
                    pass

        def sync_on_agent_disconnect(agent: AgentConnection) -> None:
            if self._on_agent_disconnect:
                self._agents.pop(agent.agent_id, None)
                try:
                    loop = asyncio.get_running_loop()
                    asyncio.run_coroutine_threadsafe(self._on_agent_disconnect(agent), loop)
                except RuntimeError:
                    pass

        def sync_on_metrics(metrics: Metrics) -> None:
            if self._on_metrics:
                try:
                    loop = asyncio.get_running_loop()
                    asyncio.run_coroutine_threadsafe(self._on_metrics(metrics), loop)
                except RuntimeError:
                    pass

        def sync_on_realtime(realtime: RealtimeMetrics) -> None:
            if self._on_realtime_metrics:
                try:
                    loop = asyncio.get_running_loop()
                    asyncio.run_coroutine_threadsafe(self._on_realtime_metrics(realtime), loop)
                except RuntimeError:
                    pass

        def sync_on_static(static_info: StaticInfo) -> None:
            if self._on_static_info:
                try:
                    loop = asyncio.get_running_loop()
                    asyncio.run_coroutine_threadsafe(self._on_static_info(static_info), loop)
                except RuntimeError:
                    pass

        def sync_on_periodic(periodic: PeriodicData) -> None:
            if self._on_periodic_data:
                try:
                    loop = asyncio.get_running_loop()
                    asyncio.run_coroutine_threadsafe(self._on_periodic_data(periodic), loop)
                except RuntimeError:
                    pass

        # Create the gRPC servicer with callback wrappers
        self._grpc_servicer = NanoLinkServicer(
            token_validator=self.config.token_validator,
            on_agent_connect=sync_on_agent_connect,
            on_agent_disconnect=sync_on_agent_disconnect,
            on_metrics=sync_on_metrics,
            on_realtime_metrics=sync_on_realtime,
            on_static_info=sync_on_static,
            on_periodic_data=sync_on_periodic,
        )

        # Create and start the gRPC server
        self._grpc_server = create_grpc_server(
            self._grpc_servicer,
            port=self.config.grpc_port,
        )
        self._grpc_server.start()

    async def stop(self) -> None:
        """Stop the server"""
        logger.info("Stopping NanoLink Server...")

        # Stop gRPC server first
        if self._grpc_server:
            self._grpc_server.stop(grace=5)
            logger.info("gRPC server stopped")

        # Close all agent connections
        for agent in list(self._agents.values()):
            await agent.close()
        self._agents.clear()

        # Stop WebSocket server
        if self._websocket_server:
            self._websocket_server.close()
            await self._websocket_server.wait_closed()

        logger.info("NanoLink Server stopped")

    async def run_forever(self) -> None:
        """Run the server forever"""
        await self.start()
        try:
            await asyncio.Future()  # Run forever
        except asyncio.CancelledError:
            await self.stop()

    @property
    def grpc_agents(self) -> Dict[str, AgentConnection]:
        """Get agents connected via gRPC"""
        if self._grpc_servicer:
            return self._grpc_servicer.agents
        return {}


    async def _handle_websocket(self, websocket: WebSocketServerProtocol) -> None:
        """Handle incoming WebSocket connection"""
        agent: Optional[AgentConnection] = None

        try:
            # Wait for authentication message
            auth_message = await asyncio.wait_for(websocket.recv(), timeout=10.0)
            auth_data = json.loads(auth_message)

            if auth_data.get("type") != "auth":
                await websocket.close(1008, "Expected auth message")
                return

            payload = auth_data.get("payload", {})
            token = payload.get("token", "")

            # Validate token
            validation = self.config.token_validator(token)
            if not validation.valid:
                response = {
                    "type": "auth_response",
                    "payload": {
                        "success": False,
                        "errorMessage": validation.error_message or "Invalid token",
                    },
                }
                await websocket.send(json.dumps(response))
                await websocket.close(1008, "Authentication failed")
                return

            # Create agent connection
            agent_id = str(uuid.uuid4())
            agent = AgentConnection(
                agent_id=agent_id,
                hostname=payload.get("hostname", "unknown"),
                os=payload.get("os", ""),
                arch=payload.get("arch", ""),
                version=payload.get("agentVersion", ""),
                permission_level=validation.permission_level,
                connected_at=datetime.now(),
                last_heartbeat=datetime.now(),
                _websocket=websocket,
            )

            # Send auth response
            response = {
                "type": "auth_response",
                "payload": {
                    "success": True,
                    "permissionLevel": validation.permission_level,
                },
            }
            await websocket.send(json.dumps(response))

            # Register agent
            self._agents[agent_id] = agent
            logger.info(f"Agent registered: {agent.hostname} ({agent_id})")

            # Notify callback
            if self._on_agent_connect:
                try:
                    await self._on_agent_connect(agent)
                except Exception as e:
                    logger.error(f"Error in on_agent_connect callback: {e}")

            # Handle messages
            async for message in websocket:
                try:
                    data = json.loads(message)
                    await self._handle_message(agent, data)
                except json.JSONDecodeError:
                    logger.warning(f"Invalid JSON from agent {agent.hostname}")
                except Exception as e:
                    logger.error(f"Error handling message from {agent.hostname}: {e}")

        except asyncio.TimeoutError:
            logger.warning("Authentication timeout")
            await websocket.close(1008, "Authentication timeout")
        except websockets.ConnectionClosed:
            pass
        except Exception as e:
            logger.error(f"WebSocket error: {e}")
        finally:
            if agent:
                # Unregister agent
                self._agents.pop(agent.agent_id, None)
                logger.info(f"Agent unregistered: {agent.hostname} ({agent.agent_id})")

                # Notify callback
                if self._on_agent_disconnect:
                    try:
                        await self._on_agent_disconnect(agent)
                    except Exception as e:
                        logger.error(f"Error in on_agent_disconnect callback: {e}")

    async def _handle_message(self, agent: AgentConnection, data: dict) -> None:
        """Handle incoming message from agent"""
        message_type = data.get("type")

        if message_type == "metrics":
            metrics = Metrics.from_dict(data.get("payload", {}))
            metrics.hostname = agent.hostname
            if self._on_metrics:
                try:
                    await self._on_metrics(metrics)
                except Exception as e:
                    logger.error(f"Error in on_metrics callback: {e}")

        elif message_type == "realtime":
            realtime = RealtimeMetrics.from_dict(data.get("payload", {}))
            realtime.hostname = agent.hostname
            if self._on_realtime_metrics:
                try:
                    await self._on_realtime_metrics(realtime)
                except Exception as e:
                    logger.error(f"Error in on_realtime_metrics callback: {e}")

        elif message_type == "static_info":
            static_info = StaticInfo.from_dict(data.get("payload", {}))
            static_info.hostname = agent.hostname
            if self._on_static_info:
                try:
                    await self._on_static_info(static_info)
                except Exception as e:
                    logger.error(f"Error in on_static_info callback: {e}")

        elif message_type == "periodic":
            periodic = PeriodicData.from_dict(data.get("payload", {}))
            periodic.hostname = agent.hostname
            if self._on_periodic_data:
                try:
                    await self._on_periodic_data(periodic)
                except Exception as e:
                    logger.error(f"Error in on_periodic_data callback: {e}")

        elif message_type == "heartbeat":
            agent.last_heartbeat = datetime.now()

        elif message_type == "command_result":
            agent._handle_command_result(data.get("payload", {}))

        else:
            logger.debug(f"Unknown message type: {message_type}")


# Convenience function for simple usage
async def create_server(
    ws_port: int = DEFAULT_WS_PORT,
    grpc_port: int = DEFAULT_GRPC_PORT,
    on_metrics: Optional[Callable[[Metrics], Awaitable[None]]] = None,
    on_realtime_metrics: Optional[Callable[[RealtimeMetrics], Awaitable[None]]] = None,
    on_static_info: Optional[Callable[[StaticInfo], Awaitable[None]]] = None,
    on_periodic_data: Optional[Callable[[PeriodicData], Awaitable[None]]] = None,
    on_agent_connect: Optional[Callable[[AgentConnection], Awaitable[None]]] = None,
    on_agent_disconnect: Optional[Callable[[AgentConnection], Awaitable[None]]] = None,
    token_validator: Optional[TokenValidator] = None,
) -> NanoLinkServer:
    """
    Create and start a NanoLink server with simple configuration

    Args:
        ws_port: WebSocket server port for dashboard (default: 9100)
        grpc_port: gRPC port for agents (default: 39100)
        on_metrics: Callback for full metrics
        on_realtime_metrics: Callback for realtime metrics (CPU, memory usage)
        on_static_info: Callback for static hardware info
        on_periodic_data: Callback for periodic data (disk usage, network addresses)
        on_agent_connect: Callback for agent connections
        on_agent_disconnect: Callback for agent disconnections
        token_validator: Custom token validator

    Returns:
        Running NanoLinkServer instance
    """
    config = ServerConfig(ws_port=ws_port, grpc_port=grpc_port)
    if token_validator:
        config.token_validator = token_validator

    server = NanoLinkServer(config)

    if on_metrics:
        server._on_metrics = on_metrics
    if on_realtime_metrics:
        server._on_realtime_metrics = on_realtime_metrics
    if on_static_info:
        server._on_static_info = on_static_info
    if on_periodic_data:
        server._on_periodic_data = on_periodic_data
    if on_agent_connect:
        server._on_agent_connect = on_agent_connect
    if on_agent_disconnect:
        server._on_agent_disconnect = on_agent_disconnect

    await server.start()
    return server
