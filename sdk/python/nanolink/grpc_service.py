"""
gRPC Service implementation for NanoLink Python SDK
"""

import logging
import queue
import threading
import time
import uuid
from concurrent import futures
from datetime import datetime
from typing import Callable, Dict, Iterator, Optional, Any

import grpc

from .proto import nanolink_pb2, nanolink_pb2_grpc
from .connection import AgentConnection, ValidationResult, TokenValidator, PermissionLevel
from .sanitize import sanitize_hostname
from .metrics import (
    Metrics, RealtimeMetrics, StaticInfo, PeriodicData,
    CpuMetrics, MemoryMetrics, DiskMetrics, NetworkMetrics,
    GpuMetrics, NpuMetrics, UserSession, SystemInfo,
    DiskIO, NetworkIO, GpuUsage, NpuUsage,
    CpuStaticInfo, MemoryStaticInfo, DiskStaticInfo, NetworkStaticInfo,
    GpuStaticInfo, NpuStaticInfo, DiskUsage, NetworkAddressUpdate
)

logger = logging.getLogger(__name__)


class NanoLinkServicer(nanolink_pb2_grpc.NanoLinkServiceServicer):
    """gRPC service implementation for NanoLink agent communication"""

    def __init__(
        self,
        token_validator: TokenValidator,
        on_agent_connect: Optional[Callable[[AgentConnection], None]] = None,
        on_agent_disconnect: Optional[Callable[[AgentConnection], None]] = None,
        on_metrics: Optional[Callable[[Metrics], None]] = None,
        on_realtime_metrics: Optional[Callable[[RealtimeMetrics], None]] = None,
        on_static_info: Optional[Callable[[StaticInfo], None]] = None,
        on_periodic_data: Optional[Callable[[PeriodicData], None]] = None,
        require_authentication: bool = False,  # P0-3: 可选强制认证
    ):
        self.token_validator = token_validator
        self.on_agent_connect = on_agent_connect
        self.on_agent_disconnect = on_agent_disconnect
        self.on_metrics = on_metrics
        self.on_realtime_metrics = on_realtime_metrics
        self.on_static_info = on_static_info
        self.on_periodic_data = on_periodic_data
        self.require_authentication = require_authentication  # P0-3

        # Map of context to agent connection
        self._agents: Dict[str, AgentConnection] = {}
        self._context_agents: Dict[Any, AgentConnection] = {}
        # Map of agent_id to response queue for sending DataRequest
        self._agent_queues: Dict[str, Any] = {}

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

    def _register_agent(self, agent: AgentConnection, context: Any = None):
        """Register a new agent"""
        # Remove existing agent with same hostname
        existing = self.get_agent_by_hostname(agent.hostname)
        if existing:
            self._unregister_agent(existing)
            logger.info(f"Replacing stale agent for hostname: {agent.hostname}")

        self._agents[agent.agent_id] = agent
        if context:
            self._context_agents[id(context)] = agent

        # Create a queue for sending data requests to this agent
        self._agent_queues[agent.agent_id] = queue.Queue(maxsize=100)

        logger.info(f"Agent registered: {agent.hostname} ({agent.agent_id})")

        if self.on_agent_connect:
            try:
                self.on_agent_connect(agent)
            except Exception as e:
                logger.error(f"Error in on_agent_connect callback: {e}")

    def _unregister_agent(self, agent: AgentConnection):
        """Unregister an agent"""
        self._agents.pop(agent.agent_id, None)

        # Remove from context map
        for ctx_id, a in list(self._context_agents.items()):
            if a.agent_id == agent.agent_id:
                del self._context_agents[ctx_id]

        # Remove the data request queue
        self._agent_queues.pop(agent.agent_id, None)

        logger.info(f"Agent unregistered: {agent.hostname} ({agent.agent_id})")

        if self.on_agent_disconnect:
            try:
                self.on_agent_disconnect(agent)
            except Exception as e:
                logger.error(f"Error in on_agent_disconnect callback: {e}")

    def Authenticate(self, request, context):
        """Handle authentication request"""
        logger.debug(f"Authentication request from: {request.hostname} ({request.agent_version})")

        try:
            result = self.token_validator(request.token)

            if result.valid:
                # Check for existing agent with same hostname
                existing = self.get_agent_by_hostname(request.hostname)
                if existing:
                    self._unregister_agent(existing)
                    logger.info(f"Replacing stale agent for hostname: {request.hostname}")

                # Create agent connection
                agent_id = str(uuid.uuid4())
                agent = AgentConnection(
                    agent_id=agent_id,
                    hostname=request.hostname,
                    os=request.os,
                    arch=request.arch,
                    version=request.agent_version,
                    permission_level=result.permission_level,
                    connected_at=datetime.now(),
                    last_heartbeat=datetime.now(),
                )

                self._register_agent(agent, context)

                logger.info(f"Agent authenticated: {request.hostname} ({agent_id}) "
                           f"with permission level {result.permission_level}")

                return nanolink_pb2.AuthResponse(
                    success=True,
                    permission_level=result.permission_level
                )
            else:
                logger.warning(f"Authentication failed for: {request.hostname}")
                return nanolink_pb2.AuthResponse(
                    success=False,
                    error_message=result.error_message or "Invalid token"
                )
        except Exception as e:
            logger.error(f"Authentication error: {e}")
            context.abort(grpc.StatusCode.INTERNAL, str(e))

    def StreamMetrics(self, request_iterator: Iterator, context):
        """Handle bidirectional metrics stream"""
        logger.debug("New metrics stream connection")

        agent: Optional[AgentConnection] = None
        agent_id: Optional[str] = None

        # Send initial heartbeat ack to establish stream
        yield nanolink_pb2.MetricsStreamResponse(
            heartbeat_ack=nanolink_pb2.HeartbeatAck(
                timestamp=int(time.time() * 1000)
            )
        )
        logger.debug("Sent initial heartbeat ack")

        try:
            for request in request_iterator:
                try:
                    if request.HasField('metrics'):
                        proto_metrics = request.metrics

                        # Register agent from first metrics
                        if agent is None:
                            # P0-3: 强制认证模式检查
                            if self.require_authentication:
                                logger.warning("SECURITY: Rejecting unauthenticated metrics stream (require_authentication=True)")
                                context.abort(grpc.StatusCode.UNAUTHENTICATED, 
                                            "Authentication required: use Authenticate RPC before streaming metrics")
                                return

                            hostname = sanitize_hostname(proto_metrics.hostname)

                            # Check for existing agent
                            existing = self.get_agent_by_hostname(hostname)
                            if existing:
                                self._unregister_agent(existing)

                            agent_id = str(uuid.uuid4())
                            os_name = ""
                            arch = ""
                            if proto_metrics.HasField('system_info'):
                                os_name = proto_metrics.system_info.os_name
                            if proto_metrics.HasField('cpu'):
                                arch = proto_metrics.cpu.architecture

                            agent = AgentConnection(
                                agent_id=agent_id,
                                hostname=hostname,
                                os=os_name,
                                arch=arch,
                                version="0.2.0",
                                permission_level=PermissionLevel.READ_ONLY,  # Default to READ_ONLY for unauthenticated
                                connected_at=datetime.now(),
                                last_heartbeat=datetime.now(),
                            )
                            logger.warning(f"Agent {hostname} registered via stream without authentication - using READ_ONLY permission")
                            self._register_agent(agent, context)

                        # Convert and handle metrics
                        sdk_metrics = self._convert_metrics(proto_metrics)
                        agent.last_metrics_at = datetime.now()

                        if self.on_metrics:
                            try:
                                self.on_metrics(sdk_metrics)
                            except Exception as e:
                                logger.error(f"Error in on_metrics callback: {e}")

                        logger.debug(f"Received metrics from: {proto_metrics.hostname}")

                    elif request.HasField('heartbeat'):
                        # Respond to heartbeat
                        if agent:
                            agent.last_heartbeat = datetime.now()

                        yield nanolink_pb2.MetricsStreamResponse(
                            heartbeat_ack=nanolink_pb2.HeartbeatAck(
                                timestamp=int(time.time() * 1000)
                            )
                        )

                    elif request.HasField('realtime'):
                        proto_realtime = request.realtime

                        if agent is None:
                            continue

                        sdk_realtime = self._convert_realtime_metrics(proto_realtime)
                        sdk_realtime.hostname = agent.hostname
                        agent.last_metrics_at = datetime.now()

                        if self.on_realtime_metrics:
                            try:
                                self.on_realtime_metrics(sdk_realtime)
                            except Exception as e:
                                logger.error(f"Error in on_realtime_metrics callback: {e}")

                        logger.debug(f"Received realtime from: {agent.hostname}")

                    elif request.HasField('static_info'):
                        proto_static = request.static_info

                        # Register agent from static info if not registered
                        if agent is None and proto_static.HasField('system_info'):
                            hostname = sanitize_hostname(proto_static.system_info.hostname)
                            if hostname:
                                existing = self.get_agent_by_hostname(hostname)
                                if existing:
                                    self._unregister_agent(existing)

                                agent_id = str(uuid.uuid4())
                                os_name = proto_static.system_info.os_name
                                arch = proto_static.cpu.architecture if proto_static.HasField('cpu') else ""

                                agent = AgentConnection(
                                    agent_id=agent_id,
                                    hostname=hostname,
                                    os=os_name,
                                    arch=arch,
                                    version=proto_static.agent_version or "unknown",
                                    permission_level=PermissionLevel.READ_ONLY,  # Default to READ_ONLY for unauthenticated
                                    connected_at=datetime.now(),
                                    last_heartbeat=datetime.now(),
                                )
                                logger.warning(f"Agent {hostname} registered via static info without authentication - using READ_ONLY permission")
                                self._register_agent(agent, context)

                        if agent:
                            sdk_static = self._convert_static_info(proto_static)
                            sdk_static.hostname = agent.hostname

                            if self.on_static_info:
                                try:
                                    self.on_static_info(sdk_static)
                                except Exception as e:
                                    logger.error(f"Error in on_static_info callback: {e}")

                            logger.info(f"Received static info from: {agent.hostname}")

                    elif request.HasField('periodic'):
                        proto_periodic = request.periodic

                        if agent:
                            sdk_periodic = self._convert_periodic_data(proto_periodic)
                            sdk_periodic.hostname = agent.hostname

                            if self.on_periodic_data:
                                try:
                                    self.on_periodic_data(sdk_periodic)
                                except Exception as e:
                                    logger.error(f"Error in on_periodic_data callback: {e}")

                            logger.debug(f"Received periodic from: {agent.hostname}")

                    elif request.HasField('command_result'):
                        result = request.command_result
                        logger.info(f"Command result: {result.command_id} success={result.success}")

                    # Check for pending data requests and send them
                    if agent_id and agent_id in self._agent_queues:
                        while True:
                            try:
                                data_request = self._agent_queues[agent_id].get_nowait()
                                yield nanolink_pb2.MetricsStreamResponse(
                                    data_request=data_request
                                )
                                logger.debug(f"Sent data request {data_request.request_type} to {agent_id}")
                            except queue.Empty:
                                break

                except Exception as e:
                    logger.error(f"Error processing stream request: {e}")

        except grpc.RpcError as e:
            logger.warning(f"Stream error: {e}")
        finally:
            if agent:
                self._unregister_agent(agent)

    def ReportMetrics(self, request, context):
        """Handle one-time metrics report"""
        logger.debug(f"Received metrics from: {request.hostname}")

        sdk_metrics = self._convert_metrics(request)

        if self.on_metrics:
            try:
                self.on_metrics(sdk_metrics)
            except Exception as e:
                logger.error(f"Error in on_metrics callback: {e}")

        return nanolink_pb2.MetricsAck(
            success=True,
            timestamp=int(time.time() * 1000)
        )

    def Heartbeat(self, request, context):
        """Handle heartbeat"""
        logger.debug(f"Heartbeat from: {request.agent_id}")

        return nanolink_pb2.HeartbeatResponse(
            server_timestamp=int(time.time() * 1000),
            config_changed=False
        )

    def ExecuteCommand(self, request, context):
        """Handle command execution"""
        logger.info(f"Execute command: {request.command_id} type={request.type}")

        return nanolink_pb2.CommandResult(
            command_id=request.command_id,
            success=False,
            error="Command execution through server not yet implemented"
        )

    def SyncMetrics(self, request, context):
        """Handle metrics sync"""
        logger.debug(f"Metrics sync from: {request.agent_id}")

        return nanolink_pb2.MetricsSyncResponse(
            success=True,
            server_timestamp=int(time.time() * 1000)
        )

    def GetAgentInfo(self, request, context):
        """Handle get agent info"""
        logger.debug(f"Get agent info: {request.agent_id}")

        agent = self.get_agent(request.agent_id)
        if agent:
            return nanolink_pb2.AgentInfoResponse(
                agent_id=agent.agent_id,
                hostname=agent.hostname,
                os=agent.os,
                arch=agent.arch,
                version=agent.version,
                permission_level=agent.permission_level,
                connected_at=int(agent.connected_at.timestamp() * 1000),
                last_metrics_at=int(agent.last_metrics_at.timestamp() * 1000) if agent.last_metrics_at else 0
            )

        return nanolink_pb2.AgentInfoResponse(agent_id=request.agent_id)

    def _convert_metrics(self, proto: nanolink_pb2.Metrics) -> Metrics:
        """Convert proto Metrics to SDK Metrics"""
        metrics = Metrics()
        metrics.timestamp = proto.timestamp
        metrics.hostname = proto.hostname
        metrics.load_average = list(proto.load_average)

        if proto.HasField('cpu'):
            metrics.cpu = CpuMetrics(
                usage_percent=proto.cpu.usage_percent,
                core_count=proto.cpu.core_count,
                model=proto.cpu.model,
                vendor=proto.cpu.vendor,
                frequency_mhz=proto.cpu.frequency_mhz,
                max_frequency_mhz=proto.cpu.frequency_max_mhz,
                architecture=proto.cpu.architecture,
                temperature_celsius=proto.cpu.temperature,
                per_core_usage=list(proto.cpu.per_core_usage),
            )

        if proto.HasField('memory'):
            metrics.memory = MemoryMetrics(
                total=proto.memory.total,
                used=proto.memory.used,
                available=proto.memory.available,
                swap_total=proto.memory.swap_total,
                swap_used=proto.memory.swap_used,
                cached=proto.memory.cached,
                buffers=proto.memory.buffers,
                memory_type=proto.memory.memory_type,
                speed_mhz=proto.memory.memory_speed_mhz,
            )

        metrics.disks = [
            DiskMetrics(
                mount_point=d.mount_point,
                device=d.device,
                fs_type=d.fs_type,
                total=d.total,
                used=d.used,
                available=d.available,
                read_bytes_per_sec=d.read_bytes_sec,
                write_bytes_per_sec=d.write_bytes_sec,
                model=d.model,
                serial=d.serial,
                disk_type=d.disk_type,
                read_iops=d.read_iops,
                write_iops=d.write_iops,
                temperature_celsius=d.temperature,
                health_status=d.health_status,
            )
            for d in proto.disks
        ]

        metrics.networks = [
            NetworkMetrics(
                interface=n.interface,
                rx_bytes_per_sec=n.rx_bytes_sec,
                tx_bytes_per_sec=n.tx_bytes_sec,
                rx_packets_per_sec=n.rx_packets_sec,
                tx_packets_per_sec=n.tx_packets_sec,
                is_up=n.is_up,
                mac_address=n.mac_address,
                ip_addresses=list(n.ip_addresses),
                link_speed_mbps=n.speed_mbps,
                interface_type=n.interface_type,
            )
            for n in proto.networks
        ]

        metrics.gpus = [
            GpuMetrics(
                index=g.index,
                name=g.name,
                vendor=g.vendor,
                usage_percent=g.usage_percent,
                memory_total=g.memory_total,
                memory_used=g.memory_used,
                temperature_celsius=g.temperature,
                fan_speed_percent=g.fan_speed_percent,
                power_draw_watts=g.power_watts,
                power_limit_watts=g.power_limit_watts,
                clock_core_mhz=g.clock_core_mhz,
                clock_memory_mhz=g.clock_memory_mhz,
                driver_version=g.driver_version,
                pcie_gen=int(g.pcie_generation) if g.pcie_generation.isdigit() else 0,
                encoder_usage_percent=g.encoder_usage,
                decoder_usage_percent=g.decoder_usage,
            )
            for g in proto.gpus
        ]

        if proto.HasField('system_info'):
            metrics.system = SystemInfo(
                os_name=proto.system_info.os_name,
                os_version=proto.system_info.os_version,
                kernel_version=proto.system_info.kernel_version,
                hostname=proto.system_info.hostname,
                boot_time=proto.system_info.boot_time,
                uptime_seconds=proto.system_info.uptime_seconds,
                motherboard_model=proto.system_info.motherboard_model,
                motherboard_vendor=proto.system_info.motherboard_vendor,
                bios_version=proto.system_info.bios_version,
            )

        metrics.user_sessions = [
            UserSession(
                username=s.username,
                tty=s.tty,
                login_time=s.login_time,
                remote_host=s.remote_host,
                idle_seconds=s.idle_seconds,
                session_type=s.session_type,
            )
            for s in proto.user_sessions
        ]

        metrics.npus = [
            NpuMetrics(
                index=n.index,
                name=n.name,
                vendor=n.vendor,
                usage_percent=n.usage_percent,
                memory_total=n.memory_total,
                memory_used=n.memory_used,
                temperature_celsius=n.temperature,
                power_watts=n.power_watts,
                driver_version=n.driver_version,
            )
            for n in proto.npus
        ]

        return metrics

    def _convert_realtime_metrics(self, proto: nanolink_pb2.RealtimeMetrics) -> RealtimeMetrics:
        """Convert proto RealtimeMetrics to SDK RealtimeMetrics"""
        realtime = RealtimeMetrics()
        realtime.timestamp = proto.timestamp
        realtime.cpu_usage_percent = proto.cpu_usage_percent
        realtime.cpu_temperature = proto.cpu_temperature
        realtime.cpu_frequency_mhz = proto.cpu_frequency_mhz
        realtime.memory_used = proto.memory_used
        realtime.memory_cached = proto.memory_cached
        realtime.swap_used = proto.swap_used
        realtime.cpu_per_core = list(proto.cpu_per_core)
        realtime.load_average = list(proto.load_average)

        realtime.disk_io = [
            DiskIO(
                device=d.device,
                read_bytes_per_sec=d.read_bytes_sec,
                write_bytes_per_sec=d.write_bytes_sec,
                read_iops=d.read_iops,
                write_iops=d.write_iops,
            )
            for d in proto.disk_io
        ]

        realtime.network_io = [
            NetworkIO(
                interface=n.interface,
                rx_bytes_per_sec=n.rx_bytes_sec,
                tx_bytes_per_sec=n.tx_bytes_sec,
                rx_packets_per_sec=n.rx_packets_sec,
                tx_packets_per_sec=n.tx_packets_sec,
                is_up=n.is_up,
            )
            for n in proto.network_io
        ]

        realtime.gpu_usage = [
            GpuUsage(
                index=g.index,
                usage_percent=g.usage_percent,
                memory_used=g.memory_used,
                temperature_celsius=g.temperature,
                power_watts=g.power_watts,
                clock_core_mhz=g.clock_core_mhz,
                encoder_usage=g.encoder_usage,
                decoder_usage=g.decoder_usage,
            )
            for g in proto.gpu_usage
        ]

        realtime.npu_usage = [
            NpuUsage(
                index=n.index,
                usage_percent=n.usage_percent,
                memory_used=n.memory_used,
                temperature_celsius=n.temperature,
                power_watts=n.power_watts,
            )
            for n in proto.npu_usage
        ]

        return realtime

    def _convert_static_info(self, proto: nanolink_pb2.StaticInfo) -> StaticInfo:
        """Convert proto StaticInfo to SDK StaticInfo"""
        static_info = StaticInfo()
        static_info.timestamp = proto.timestamp

        if proto.HasField('cpu'):
            static_info.cpu = CpuStaticInfo(
                model=proto.cpu.model,
                vendor=proto.cpu.vendor,
                physical_cores=proto.cpu.physical_cores,
                logical_cores=proto.cpu.logical_cores,
                architecture=proto.cpu.architecture,
                frequency_max_mhz=proto.cpu.frequency_max_mhz,
                l1_cache_kb=proto.cpu.l1_cache_kb,
                l2_cache_kb=proto.cpu.l2_cache_kb,
                l3_cache_kb=proto.cpu.l3_cache_kb,
            )

        if proto.HasField('memory'):
            static_info.memory = MemoryStaticInfo(
                total=proto.memory.total,
                swap_total=proto.memory.swap_total,
                memory_type=proto.memory.memory_type,
                speed_mhz=proto.memory.memory_speed_mhz,
                slots=proto.memory.memory_slots,
            )

        static_info.disks = [
            DiskStaticInfo(
                device=d.device,
                mount_point=d.mount_point,
                fs_type=d.fs_type,
                model=d.model,
                serial=d.serial,
                disk_type=d.disk_type,
                total_bytes=d.total_bytes,
                health_status=d.health_status,
            )
            for d in proto.disks
        ]

        static_info.networks = [
            NetworkStaticInfo(
                interface=n.interface,
                mac_address=n.mac_address,
                ip_addresses=list(n.ip_addresses),
                speed_mbps=n.speed_mbps,
                interface_type=n.interface_type,
                is_virtual=n.is_virtual,
            )
            for n in proto.networks
        ]

        static_info.gpus = [
            GpuStaticInfo(
                index=g.index,
                name=g.name,
                vendor=g.vendor,
                memory_total=g.memory_total,
                driver_version=g.driver_version,
                pcie_generation=g.pcie_generation,
                power_limit_watts=g.power_limit_watts,
            )
            for g in proto.gpus
        ]

        static_info.npus = [
            NpuStaticInfo(
                index=n.index,
                name=n.name,
                vendor=n.vendor,
                memory_total=n.memory_total,
                driver_version=n.driver_version,
            )
            for n in proto.npus
        ]

        if proto.HasField('system_info'):
            static_info.system = SystemInfo(
                os_name=proto.system_info.os_name,
                os_version=proto.system_info.os_version,
                kernel_version=proto.system_info.kernel_version,
                hostname=proto.system_info.hostname,
                boot_time=proto.system_info.boot_time,
                uptime_seconds=proto.system_info.uptime_seconds,
                motherboard_model=proto.system_info.motherboard_model,
                motherboard_vendor=proto.system_info.motherboard_vendor,
                bios_version=proto.system_info.bios_version,
            )

        return static_info

    def _convert_periodic_data(self, proto: nanolink_pb2.PeriodicData) -> PeriodicData:
        """Convert proto PeriodicData to SDK PeriodicData"""
        periodic = PeriodicData()
        periodic.timestamp = proto.timestamp

        periodic.disk_usage = [
            DiskUsage(
                device=d.device,
                mount_point=d.mount_point,
                total=d.total,
                used=d.used,
                available=d.available,
                temperature_celsius=d.temperature,
            )
            for d in proto.disk_usage
        ]

        periodic.user_sessions = [
            UserSession(
                username=s.username,
                tty=s.tty,
                login_time=s.login_time,
                remote_host=s.remote_host,
                idle_seconds=s.idle_seconds,
                session_type=s.session_type,
            )
            for s in proto.user_sessions
        ]

        periodic.network_updates = [
            NetworkAddressUpdate(
                interface=n.interface,
                ip_addresses=list(n.ip_addresses),
                is_up=n.is_up,
            )
            for n in proto.network_updates
        ]

        return periodic

    def send_data_request(
        self,
        agent_id: str,
        request_type: int,
        target: Optional[str] = None
    ) -> bool:
        """
        Send a data request to a specific agent.

        Args:
            agent_id: The agent ID to send the request to
            request_type: The type of data to request (use nanolink_pb2.DataRequestType values)
            target: Optional target (e.g., specific device name)

        Returns:
            True if the request was queued successfully
        """
        if agent_id not in self._agent_queues:
            logger.warning(f"Agent {agent_id} not found for data request")
            return False

        request = nanolink_pb2.DataRequest(
            request_type=request_type,
            target=target or ""
        )

        try:
            self._agent_queues[agent_id].put_nowait(request)
            logger.info(f"Queued data request {request_type} for agent {agent_id}")
            return True
        except queue.Full:
            logger.warning(f"Queue full for agent {agent_id}")
            return False

    def broadcast_data_request(self, request_type: int) -> int:
        """
        Send a data request to all connected agents.

        Args:
            request_type: The type of data to request

        Returns:
            Number of agents the request was sent to
        """
        request = nanolink_pb2.DataRequest(request_type=request_type)
        count = 0

        for agent_id, q in self._agent_queues.items():
            try:
                q.put_nowait(request)
                count += 1
            except queue.Full:
                logger.warning(f"Queue full for agent {agent_id}")

        logger.info(f"Broadcast data request {request_type} to {count} agents")
        return count


def create_grpc_server(
    servicer: NanoLinkServicer,
    port: int = 39100,
    max_workers: int = 10,
) -> grpc.Server:
    """Create a gRPC server with the NanoLink servicer"""
    server = grpc.server(
        futures.ThreadPoolExecutor(max_workers=max_workers),
        options=[
            ('grpc.keepalive_time_ms', 30000),
            ('grpc.keepalive_timeout_ms', 10000),
            ('grpc.keepalive_permit_without_calls', True),
            ('grpc.max_receive_message_length', 16 * 1024 * 1024),
        ]
    )
    nanolink_pb2_grpc.add_NanoLinkServiceServicer_to_server(servicer, server)
    server.add_insecure_port(f'[::]:{port}')
    return server
