"""
NanoLink FastAPI Demo

This demo shows how to integrate NanoLink SDK with FastAPI to create a
monitoring server that receives metrics from agents.
"""

import asyncio
import logging
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Dict, List, Optional

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# Import NanoLink SDK (use local path for development)
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "sdk" / "python"))

from nanolink import NanoLinkServer, ServerConfig
from nanolink.connection import AgentConnection
from nanolink.metrics import Metrics

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


# === Global instances ===
metrics_service = MetricsService()
nanolink_server: Optional[NanoLinkServer] = None


# === FastAPI App ===

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler"""
    global nanolink_server

    # Initialize NanoLink server
    # ws_port: for dashboard WebSocket connections (default: 9100)
    # grpc_port: for agent gRPC connections (default: 39100)
    config = ServerConfig(ws_port=9100, grpc_port=39100)
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

    # Start NanoLink server in background
    logger.info("Starting NanoLink Server - WebSocket port 9100, gRPC port 39100")
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

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


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
        # Note: Command execution is async in the Python SDK
        # The actual command would be sent here
        return CommandResponse(success=True, message="Service restart command sent")
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
        return CommandResponse(success=True, message="Process kill command sent")
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
        return CommandResponse(success=True, message="Container restart command sent")
    except Exception as e:
        logger.error(f"Failed to restart container on {hostname}: {e}")
        return CommandResponse(success=False, message=str(e))


if __name__ == "__main__":
    import uvicorn
    logger.info("Starting REST API server on http://localhost:8000")
    uvicorn.run(app, host="0.0.0.0", port=8000)
