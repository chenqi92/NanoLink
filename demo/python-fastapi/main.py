"""
NanoLink FastAPI Demo

This demo shows how to integrate NanoLink SDK with FastAPI to create a
monitoring server that receives metrics from agents.
"""

import asyncio
import logging
import os
import secrets
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Dict, List, Optional

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel

# Import NanoLink SDK (use local path for development)
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "sdk" / "python"))

from nanolink import NanoLinkServer, ServerConfig
from nanolink.connection import AgentConnection, ValidationResult
from nanolink.command import Command
from nanolink.metrics import Metrics, RealtimeMetrics, StaticInfo, PeriodicData

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger(__name__)


# === Models ===

class AgentInfo(BaseModel):
    agent_id: str
    hostname: str
    os: str
    arch: str
    version: str
    connected_at: datetime


class AgentMetrics(BaseModel):
    hostname: str
    cpu_usage: float
    memory_usage: float
    memory_total: int
    memory_used: int
    timestamp: datetime


class ServiceRequest(BaseModel):
    service_name: str


class ProcessRequest(BaseModel):
    pid: int
    target: Optional[str] = None


class DockerRequest(BaseModel):
    container_name: str


class CommandResponse(BaseModel):
    success: bool
    message: str


class ClusterSummary(BaseModel):
    agent_count: int
    avg_cpu_usage: float
    avg_memory_usage: float


class HealthResponse(BaseModel):
    status: str
    connected_agents: int


# === Metrics Service ===

class MetricsService:
    """Service for managing agent metrics"""

    def __init__(self):
        self.agents: Dict[str, AgentInfo] = {}
        self.latest_metrics: Dict[str, AgentMetrics] = {}
        self.static_info: Dict[str, StaticInfo] = {}
        self.periodic_data: Dict[str, PeriodicData] = {}
        self._websocket_clients: List = []  # WebSocket clients for broadcasting

    def register_agent(self, agent: AgentConnection) -> None:
        """Register a new agent connection"""
        info = AgentInfo(
            agent_id=agent.agent_id,
            hostname=agent.hostname,
            os=agent.os,
            arch=agent.arch,
            version=agent.version,
            connected_at=agent.connected_at
        )
        self.agents[agent.agent_id] = info
        logger.info(f"Agent registered: {agent.hostname} ({agent.agent_id})")

    def unregister_agent(self, agent: AgentConnection) -> None:
        """Unregister an agent"""
        self.agents.pop(agent.agent_id, None)
        self.latest_metrics.pop(agent.agent_id, None)
        logger.info(f"Agent unregistered: {agent.hostname} ({agent.agent_id})")

    def process_metrics(self, metrics: Metrics) -> None:
        """Process incoming metrics from an agent"""
        # Find agent by hostname
        agent_id = metrics.hostname
        for aid, agent in self.agents.items():
            if agent.hostname == metrics.hostname:
                agent_id = aid
                break

        # Calculate memory usage percentage
        memory_usage = 0.0
        if metrics.memory and metrics.memory.total > 0:
            memory_usage = (metrics.memory.used / metrics.memory.total) * 100

        agent_metrics = AgentMetrics(
            hostname=metrics.hostname,
            cpu_usage=metrics.cpu.usage_percent if metrics.cpu else 0.0,
            memory_usage=memory_usage,
            memory_total=metrics.memory.total if metrics.memory else 0,
            memory_used=metrics.memory.used if metrics.memory else 0,
            timestamp=datetime.now()
        )
        self.latest_metrics[agent_id] = agent_metrics

        # Check for alerts
        if agent_metrics.cpu_usage > 90:
            logger.warning(
                f"HIGH CPU ALERT: {metrics.hostname} - CPU usage at {agent_metrics.cpu_usage:.1f}%"
            )
        if agent_metrics.memory_usage > 90:
            logger.warning(
                f"HIGH MEMORY ALERT: {metrics.hostname} - Memory usage at {agent_metrics.memory_usage:.1f}%"
            )

    def get_agents(self) -> List[AgentInfo]:
        """Get all connected agents"""
        return list(self.agents.values())

    def get_metrics(self, agent_id: str) -> Optional[AgentMetrics]:
        """Get metrics for an agent"""
        return self.latest_metrics.get(agent_id)

    def get_all_metrics(self) -> Dict[str, AgentMetrics]:
        """Get all latest metrics"""
        return dict(self.latest_metrics)

    def get_average_cpu(self) -> float:
        """Get average CPU usage across all agents"""
        if not self.latest_metrics:
            return 0.0
        return sum(m.cpu_usage for m in self.latest_metrics.values()) / len(self.latest_metrics)

    def get_average_memory(self) -> float:
        """Get average memory usage across all agents"""
        if not self.latest_metrics:
            return 0.0
        return sum(m.memory_usage for m in self.latest_metrics.values()) / len(self.latest_metrics)

    def process_realtime(self, realtime: RealtimeMetrics) -> None:
        """Process incoming realtime metrics (high-frequency, lightweight)"""
        # Find agent by hostname
        agent_id = realtime.hostname
        for aid, agent in self.agents.items():
            if agent.hostname == realtime.hostname:
                agent_id = aid
                break

        # Update only the realtime fields
        if agent_id in self.latest_metrics:
            current = self.latest_metrics[agent_id]
            current.cpu_usage = realtime.cpu_usage
            current.memory_usage = realtime.memory_percent
            current.memory_used = realtime.memory_used
            current.timestamp = datetime.now()
        else:
            # Create new entry with realtime data
            self.latest_metrics[agent_id] = AgentMetrics(
                hostname=realtime.hostname,
                cpu_usage=realtime.cpu_usage,
                memory_usage=realtime.memory_percent,
                memory_total=0,
                memory_used=realtime.memory_used,
                timestamp=datetime.now()
            )

        # Check for alerts
        if realtime.cpu_usage > 90:
            logger.warning(
                f"HIGH CPU ALERT: {realtime.hostname} - CPU usage at {realtime.cpu_usage:.1f}%"
            )

    def process_static_info(self, static_info: StaticInfo) -> None:
        """Process static hardware info (received once on connect)"""
        # Find agent by hostname
        agent_id = static_info.hostname
        for aid, agent in self.agents.items():
            if agent.hostname == static_info.hostname:
                agent_id = aid
                break

        # Store static info
        self.static_info[agent_id] = static_info

        logger.info(
            f"Static info received from {static_info.hostname}: "
            f"OS={static_info.os_name} {static_info.os_version}, "
            f"Kernel={static_info.kernel_version}"
        )
        # Update memory_total if available
        if static_info.memory and static_info.memory.total_physical > 0:
            for aid, agent in self.agents.items():
                if agent.hostname == static_info.hostname:
                    if aid in self.latest_metrics:
                        self.latest_metrics[aid].memory_total = static_info.memory.total_physical
                    break

    def process_periodic(self, periodic: PeriodicData) -> None:
        """Process periodic data (disk usage, user sessions, etc.)"""
        # Find agent by hostname
        agent_id = periodic.hostname
        for aid, agent in self.agents.items():
            if agent.hostname == periodic.hostname:
                agent_id = aid
                break

        # Store periodic data
        self.periodic_data[agent_id] = periodic

        logger.debug(
            f"Periodic data received from {periodic.hostname}: "
            f"uptime={periodic.uptime_seconds}s, "
            f"disks={len(periodic.disk_usage) if periodic.disk_usage else 0}, "
            f"sessions={len(periodic.user_sessions) if periodic.user_sessions else 0}"
        )

    def get_static_info(self, agent_id: str) -> Optional[StaticInfo]:
        """Get static info for an agent"""
        return self.static_info.get(agent_id)

    def get_periodic_data(self, agent_id: str) -> Optional[PeriodicData]:
        """Get periodic data for an agent"""
        return self.periodic_data.get(agent_id)

    def add_websocket_client(self, client) -> None:
        """Add a WebSocket client for broadcasting"""
        self._websocket_clients.append(client)

    def remove_websocket_client(self, client) -> None:
        """Remove a WebSocket client"""
        if client in self._websocket_clients:
            self._websocket_clients.remove(client)

    async def broadcast_metrics(self, agent_id: str, metrics: AgentMetrics) -> None:
        """Broadcast metrics update to all WebSocket clients"""
        import json
        message = json.dumps({
            "type": "metrics",
            "agentId": agent_id,
            "metrics": {
                "hostname": metrics.hostname,
                "cpuUsage": metrics.cpu_usage,
                "memoryUsage": metrics.memory_usage,
                "memoryTotal": metrics.memory_total,
                "memoryUsed": metrics.memory_used,
                "timestamp": metrics.timestamp.isoformat()
            }
        })
        for client in list(self._websocket_clients):
            try:
                await client.send(message)
            except Exception:
                self._websocket_clients.remove(client)

    async def broadcast_agent_event(self, event_type: str, agent: AgentInfo) -> None:
        """Broadcast agent connect/disconnect event"""
        import json
        message = json.dumps({
            "type": event_type,
            "agent": {
                "agentId": agent.agent_id,
                "hostname": agent.hostname,
                "os": agent.os,
                "arch": agent.arch,
                "version": agent.version,
                "connectedAt": agent.connected_at.isoformat()
            }
        })
        for client in list(self._websocket_clients):
            try:
                await client.send(message)
            except Exception:
                self._websocket_clients.remove(client)


# === Global instances ===
metrics_service = MetricsService()
nanolink_server: Optional[NanoLinkServer] = None


def require_secret_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if len(value.encode("utf-8")) < 32:
        raise RuntimeError(f"{name} must be configured with at least 32 bytes")
    return value


# === FastAPI App ===

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler"""
    global nanolink_server

    # Initialize NanoLink server
    agent_token = require_secret_env("NANOLINK_AGENT_TOKEN")
    require_secret_env("NANOLINK_API_TOKEN")

    def validate_agent_token(token: str) -> ValidationResult:
        if secrets.compare_digest(agent_token, token):
            return ValidationResult(valid=True, permission_level=3)
        return ValidationResult(valid=False, error_message="Invalid token")

    config = ServerConfig(
        grpc_port=39100,
        host=os.environ.get("NANOLINK_GRPC_BIND_ADDRESS", "127.0.0.1"),
        tls_cert_path=os.environ.get("NANOLINK_TLS_CERT") or None,
        tls_key_path=os.environ.get("NANOLINK_TLS_KEY") or None,
        token_validator=validate_agent_token,
    )
    nanolink_server = NanoLinkServer(config)

    @nanolink_server.on_agent_connect
    async def on_connect(agent: AgentConnection):
        logger.info(f"Agent connected: {agent.hostname} ({agent.os}/{agent.arch})")
        metrics_service.register_agent(agent)

    @nanolink_server.on_agent_disconnect
    async def on_disconnect(agent: AgentConnection):
        logger.info(f"Agent disconnected: {agent.hostname}")
        metrics_service.unregister_agent(agent)

    @nanolink_server.on_metrics
    async def on_metrics(metrics: Metrics):
        metrics_service.process_metrics(metrics)

    @nanolink_server.on_realtime_metrics
    async def on_realtime(realtime: RealtimeMetrics):
        metrics_service.process_realtime(realtime)

    @nanolink_server.on_static_info
    async def on_static(static_info: StaticInfo):
        metrics_service.process_static_info(static_info)

    @nanolink_server.on_periodic_data
    async def on_periodic(periodic: PeriodicData):
        metrics_service.process_periodic(periodic)

    # Start NanoLink server in background
    logger.info("Starting NanoLink Server - gRPC port 39100")
    await nanolink_server.start()

    yield

    # Shutdown
    logger.info("Stopping NanoLink Server...")
    await nanolink_server.stop()


app = FastAPI(
    title="NanoLink FastAPI Demo",
    description="Demo server showing NanoLink SDK integration with FastAPI",
    version="0.1.0",
    lifespan=lifespan
)

@app.middleware("http")
async def authenticate_api(request: Request, call_next):
    if request.url.path.startswith("/api/"):
        expected = os.environ.get("NANOLINK_API_TOKEN", "").strip()
        authorization = request.headers.get("authorization", "")
        scheme, separator, token = authorization.partition(" ")
        if (
            len(expected.encode("utf-8")) < 32
            or not separator
            or scheme.lower() != "bearer"
            or not secrets.compare_digest(expected, token)
        ):
            return JSONResponse(
                status_code=401,
                content={"detail": "Unauthorized"},
                headers={"WWW-Authenticate": 'Bearer realm="nanolink-demo"'},
            )
    return await call_next(request)


# === API Routes ===

@app.get("/api/agents", response_model=Dict)
async def get_agents():
    """Get all connected agents"""
    agents = metrics_service.get_agents()
    return {"agents": agents, "count": len(agents)}


@app.get("/api/agents/{agent_id}/metrics", response_model=AgentMetrics)
async def get_agent_metrics(agent_id: str):
    """Get metrics for a specific agent"""
    metrics = metrics_service.get_metrics(agent_id)
    if metrics is None:
        raise HTTPException(status_code=404, detail="Agent not found")
    return metrics


@app.get("/api/metrics", response_model=Dict[str, AgentMetrics])
async def get_all_metrics():
    """Get all latest metrics"""
    return metrics_service.get_all_metrics()


@app.get("/api/summary", response_model=ClusterSummary)
async def get_summary():
    """Get cluster summary"""
    return ClusterSummary(
        agent_count=len(metrics_service.get_agents()),
        avg_cpu_usage=metrics_service.get_average_cpu(),
        avg_memory_usage=metrics_service.get_average_memory()
    )


@app.get("/api/health", response_model=HealthResponse)
async def health():
    """Health check endpoint"""
    return HealthResponse(
        status="ok",
        connected_agents=len(metrics_service.get_agents())
    )


@app.post("/api/commands/agents/{hostname}/service/restart", response_model=CommandResponse)
async def restart_service(hostname: str, request: ServiceRequest):
    """Restart a service on an agent"""
    if nanolink_server is None:
        raise HTTPException(status_code=500, detail="NanoLink server not initialized")

    agent = nanolink_server.get_agent_by_hostname(hostname)
    if agent is None:
        raise HTTPException(status_code=404, detail="Agent not found")

    try:
        logger.info(f"Restarting service {request.service_name} on {hostname}")
        result = await agent.send_command(Command.service_restart(request.service_name))
        return CommandResponse(
            success=result.success,
            message=result.output or result.error or "Service restart command sent",
        )
    except Exception as e:
        logger.error(f"Failed to restart service on {hostname}: {e}")
        return CommandResponse(success=False, message=str(e))


@app.post("/api/commands/agents/{hostname}/process/kill", response_model=CommandResponse)
async def kill_process(hostname: str, request: ProcessRequest):
    """Kill a process on an agent"""
    if nanolink_server is None:
        raise HTTPException(status_code=500, detail="NanoLink server not initialized")

    agent = nanolink_server.get_agent_by_hostname(hostname)
    if agent is None:
        raise HTTPException(status_code=404, detail="Agent not found")

    try:
        target = request.target if request.target else str(request.pid)
        logger.info(f"Killing process {target} on {hostname}")
        result = await agent.send_command(Command.process_kill(request.pid))
        return CommandResponse(
            success=result.success,
            message=result.output or result.error or "Process kill command sent",
        )
    except Exception as e:
        logger.error(f"Failed to kill process on {hostname}: {e}")
        return CommandResponse(success=False, message=str(e))


@app.post("/api/commands/agents/{hostname}/docker/restart", response_model=CommandResponse)
async def restart_container(hostname: str, request: DockerRequest):
    """Restart a Docker container on an agent"""
    if nanolink_server is None:
        raise HTTPException(status_code=500, detail="NanoLink server not initialized")

    agent = nanolink_server.get_agent_by_hostname(hostname)
    if agent is None:
        raise HTTPException(status_code=404, detail="Agent not found")

    try:
        logger.info(f"Restarting container {request.container_name} on {hostname}")
        result = await agent.send_command(Command.docker_restart(request.container_name))
        return CommandResponse(
            success=result.success,
            message=result.output or result.error or "Container restart command sent",
        )
    except Exception as e:
        logger.error(f"Failed to restart container on {hostname}: {e}")
        return CommandResponse(success=False, message=str(e))


if __name__ == "__main__":
    import uvicorn
    logger.info("Starting REST API server on http://localhost:8000")
    uvicorn.run(
        app,
        host=os.environ.get("NANOLINK_HTTP_BIND_ADDRESS", "127.0.0.1"),
        port=8000,
        timeout_keep_alive=30,
    )
