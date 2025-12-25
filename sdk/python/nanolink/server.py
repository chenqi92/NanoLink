"""
NanoLink Server implementation for Python SDK

This module provides a gRPC server for receiving metrics from NanoLink agents.
WebSocket/HTTP API should be implemented separately based on your application needs.
"""

import asyncio
import logging
import threading
from concurrent import futures
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Callable, Dict, Optional, Awaitable

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

# Default timeouts
DEFAULT_HEARTBEAT_TIMEOUT = timedelta(seconds=90)  # Agent considered dead after this
DEFAULT_HEARTBEAT_CHECK_INTERVAL = timedelta(seconds=30)  # Check interval


@dataclass
class ServerConfig:
    """
    Server configuration

    Attributes:
        grpc_port: gRPC port for agent connections (default: 39100)
        host: Host to bind to
        tls_cert_path: Path to TLS certificate (for gRPC TLS)
        tls_key_path: Path to TLS key (for gRPC TLS)
        token_validator: Token validation function
        heartbeat_timeout: Duration after which an agent is considered dead (default: 90s)
        heartbeat_check_interval: Interval for checking heartbeat timeouts (default: 30s)
    """
    grpc_port: int = DEFAULT_GRPC_PORT
    host: str = "0.0.0.0"
    tls_cert_path: Optional[str] = None
    tls_key_path: Optional[str] = None
    token_validator: TokenValidator = default_token_validator
    heartbeat_timeout: timedelta = DEFAULT_HEARTBEAT_TIMEOUT
    heartbeat_check_interval: timedelta = DEFAULT_HEARTBEAT_CHECK_INTERVAL


class NanoLinkServer:
    """
    NanoLink Server - receives metrics from agents via gRPC

    This server only handles gRPC connections from agents.
    For WebSocket/HTTP API functionality, implement your own server using
    the callbacks and agent data provided by this class.

    Example usage:
        server = NanoLinkServer(ServerConfig(grpc_port=39100))

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
        self._grpc_server = None
        self._grpc_servicer = None
        self._heartbeat_task: Optional[asyncio.Task] = None
        self._running = False

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
        """Start the gRPC server for agent connections"""
        if not GRPC_AVAILABLE:
            raise RuntimeError("gRPC is not available. Install grpcio and grpcio-tools.")

        self._running = True
        self._start_grpc_server()

        # Start heartbeat checker
        self._start_heartbeat_checker()

        logger.info(f"NanoLink gRPC Server started on port {self.config.grpc_port}")

    def _start_heartbeat_checker(self) -> None:
        """Start the heartbeat checker background task"""
        async def heartbeat_loop():
            interval = self.config.heartbeat_check_interval.total_seconds()
            logger.info(
                f"Heartbeat checker started (timeout: {self.config.heartbeat_timeout.total_seconds()}s, "
                f"interval: {interval}s)"
            )
            while self._running:
                try:
                    await asyncio.sleep(interval)
                    await self._check_heartbeat_timeouts()
                except asyncio.CancelledError:
                    break
                except Exception as e:
                    logger.error(f"Error in heartbeat checker: {e}")

        try:
            loop = asyncio.get_running_loop()
            self._heartbeat_task = loop.create_task(heartbeat_loop())
        except RuntimeError:
            # No event loop running, skip heartbeat checker
            logger.warning("No event loop available, heartbeat checker not started")

    async def _check_heartbeat_timeouts(self) -> None:
        """Check for agents that have timed out"""
        threshold = datetime.now() - self.config.heartbeat_timeout
        dead_agents = []

        for agent in list(self._agents.values()):
            if agent.last_heartbeat < threshold:
                dead_agents.append(agent)

        for agent in dead_agents:
            logger.warning(
                f"Agent {agent.hostname} ({agent.agent_id}) heartbeat timeout, disconnecting"
            )
            await agent.close()
            self._agents.pop(agent.agent_id, None)
            if self._on_agent_disconnect:
                try:
                    await self._on_agent_disconnect(agent)
                except Exception as e:
                    logger.error(f"Error in on_agent_disconnect callback: {e}")

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

        self._running = False

        # Stop heartbeat checker
        if self._heartbeat_task:
            self._heartbeat_task.cancel()
            try:
                await self._heartbeat_task
            except asyncio.CancelledError:
                pass
            self._heartbeat_task = None

        # Stop gRPC server
        if self._grpc_server:
            self._grpc_server.stop(grace=5)
            logger.info("gRPC server stopped")

        # Close all agent connections
        for agent in list(self._agents.values()):
            await agent.close()
        self._agents.clear()

        logger.info("NanoLink Server stopped")

    async def run_forever(self) -> None:
        """Run the server forever"""
        await self.start()
        try:
            await asyncio.Future()  # Run forever
        except asyncio.CancelledError:
            await self.stop()

    def request_data(
        self,
        agent_id: str,
        request_type: DataRequestType,
        target: Optional[str] = None
    ) -> bool:
        """
        Request specific data from an agent.
        Use this to fetch static info, disk usage, network info etc. on demand.

        Args:
            agent_id: The agent ID to request data from
            request_type: The type of data to request (use DataRequestType enum)
            target: Optional target (e.g., specific device or mount point)

        Returns:
            True if request was queued successfully
        """
        if self._grpc_servicer is not None:
            return self._grpc_servicer.send_data_request(
                agent_id,
                request_type.value,
                target
            )
        logger.warning("Cannot send data request - gRPC service not available")
        return False

    def broadcast_data_request(self, request_type: DataRequestType) -> int:
        """
        Request data from all connected agents.

        Args:
            request_type: The type of data to request

        Returns:
            Number of agents the request was sent to
        """
        if self._grpc_servicer is not None:
            return self._grpc_servicer.broadcast_data_request(request_type.value)
        logger.warning("Cannot broadcast data request - gRPC service not available")
        return 0


# Convenience function for simple usage
async def create_server(
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
    Create and start a NanoLink gRPC server with simple configuration

    Args:
        grpc_port: gRPC port for agent connections (default: 39100)
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
    config = ServerConfig(grpc_port=grpc_port)
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
