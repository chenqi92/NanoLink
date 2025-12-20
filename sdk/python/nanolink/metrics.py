"""
Metrics data models for NanoLink SDK
"""

from dataclasses import dataclass, field
from enum import IntEnum
from typing import List, Optional


class MetricsType(IntEnum):
    """Type of metrics data"""
    FULL = 0       # Complete data (first connection or on request)
    REALTIME = 1   # Realtime data only (CPU/memory/network IO)
    PERIODIC = 2   # Periodic data (disk usage, user sessions)
    STATIC = 3     # Static data (hardware info)


class DataRequestType(IntEnum):
    """Types of data requests from server to agent"""
    FULL = 0           # Request complete metrics
    STATIC = 1         # Request static hardware/system info
    DISK_USAGE = 2     # Request disk capacity/usage
    NETWORK_INFO = 3   # Request network info (IPs, MACs)
    USER_SESSIONS = 4  # Request user sessions
    GPU_INFO = 5       # Request GPU static info
    HEALTH = 6         # Request disk S.M.A.R.T status


@dataclass
class CpuMetrics:
    """CPU metrics data"""
    usage_percent: float = 0.0
    core_count: int = 0
    per_core_usage: List[float] = field(default_factory=list)
    model: str = ""
    vendor: str = ""
    frequency_mhz: float = 0.0
    max_frequency_mhz: float = 0.0
    temperature_celsius: Optional[float] = None
    architecture: str = ""


@dataclass
class MemoryMetrics:
    """Memory metrics data"""
    total: int = 0
    used: int = 0
    available: int = 0
    swap_total: int = 0
    swap_used: int = 0
    cached: int = 0
    buffers: int = 0
    memory_type: str = ""  # DDR4, DDR5, etc.
    speed_mhz: int = 0

    @property
    def usage_percent(self) -> float:
        """Calculate memory usage percentage"""
        if self.total == 0:
            return 0.0
        return (self.used / self.total) * 100

    @property
    def swap_usage_percent(self) -> float:
        """Calculate swap usage percentage"""
        if self.swap_total == 0:
            return 0.0
        return (self.swap_used / self.swap_total) * 100


@dataclass
class DiskMetrics:
    """Disk metrics data"""
    mount_point: str = ""
    device: str = ""
    fs_type: str = ""
    total: int = 0
    used: int = 0
    available: int = 0
    read_bytes_per_sec: int = 0
    write_bytes_per_sec: int = 0
    read_iops: int = 0
    write_iops: int = 0
    model: str = ""
    serial: str = ""
    disk_type: str = ""  # SSD, HDD, NVMe
    temperature_celsius: Optional[float] = None
    health_status: str = ""

    @property
    def usage_percent(self) -> float:
        """Calculate disk usage percentage"""
        if self.total == 0:
            return 0.0
        return (self.used / self.total) * 100


@dataclass
class NetworkMetrics:
    """Network interface metrics data"""
    interface: str = ""
    rx_bytes_per_sec: int = 0
    tx_bytes_per_sec: int = 0
    rx_packets_per_sec: int = 0
    tx_packets_per_sec: int = 0
    is_up: bool = False
    mac_address: str = ""
    ip_addresses: List[str] = field(default_factory=list)
    link_speed_mbps: int = 0
    interface_type: str = ""  # ethernet, wifi, loopback


@dataclass
class GpuMetrics:
    """GPU metrics data"""
    index: int = 0
    name: str = ""
    vendor: str = ""  # NVIDIA, AMD, Intel
    usage_percent: float = 0.0
    memory_total: int = 0
    memory_used: int = 0
    temperature_celsius: float = 0.0
    fan_speed_percent: float = 0.0
    power_draw_watts: float = 0.0
    power_limit_watts: float = 0.0
    clock_core_mhz: int = 0
    clock_memory_mhz: int = 0
    driver_version: str = ""
    pcie_gen: int = 0
    pcie_width: int = 0
    encoder_usage_percent: float = 0.0
    decoder_usage_percent: float = 0.0

    @property
    def memory_usage_percent(self) -> float:
        """Calculate GPU memory usage percentage"""
        if self.memory_total == 0:
            return 0.0
        return (self.memory_used / self.memory_total) * 100


@dataclass
class NpuMetrics:
    """NPU/AI accelerator metrics data"""
    index: int = 0
    name: str = ""
    vendor: str = ""  # Intel, Huawei, Qualcomm
    usage_percent: float = 0.0
    memory_total: int = 0
    memory_used: int = 0
    temperature_celsius: float = 0.0
    power_watts: int = 0
    driver_version: str = ""

    @property
    def memory_usage_percent(self) -> float:
        """Calculate NPU memory usage percentage"""
        if self.memory_total == 0:
            return 0.0
        return (self.memory_used / self.memory_total) * 100


@dataclass
class UserSession:
    """User session/login information"""
    username: str = ""
    tty: str = ""
    login_time: int = 0
    remote_host: str = ""
    idle_seconds: int = 0
    session_type: str = ""  # local, ssh, rdp, console


@dataclass
class SystemInfo:
    """System information data"""
    os_name: str = ""
    os_version: str = ""
    kernel_version: str = ""
    hostname: str = ""
    boot_time: int = 0
    uptime_seconds: int = 0
    motherboard_model: str = ""
    motherboard_vendor: str = ""
    bios_version: str = ""


@dataclass
class Metrics:
    """Complete system metrics from an agent"""
    timestamp: int = 0
    hostname: str = ""
    cpu: Optional[CpuMetrics] = None
    memory: Optional[MemoryMetrics] = None
    disks: List[DiskMetrics] = field(default_factory=list)
    networks: List[NetworkMetrics] = field(default_factory=list)
    gpus: List[GpuMetrics] = field(default_factory=list)
    npus: List[NpuMetrics] = field(default_factory=list)
    user_sessions: List[UserSession] = field(default_factory=list)
    system: Optional[SystemInfo] = None
    load_average: List[float] = field(default_factory=list)

    @classmethod
    def from_dict(cls, data: dict) -> "Metrics":
        """Create Metrics from dictionary"""
        metrics = cls()
        metrics.timestamp = data.get("timestamp", 0)
        metrics.hostname = data.get("hostname", "")

        if "cpu" in data and data["cpu"]:
            cpu_data = data["cpu"]
            metrics.cpu = CpuMetrics(
                usage_percent=cpu_data.get("usagePercent", 0.0),
                core_count=cpu_data.get("coreCount", 0),
                per_core_usage=cpu_data.get("perCoreUsage", []),
                model=cpu_data.get("model", ""),
                vendor=cpu_data.get("vendor", ""),
                frequency_mhz=cpu_data.get("frequencyMhz", 0.0),
                max_frequency_mhz=cpu_data.get("maxFrequencyMhz", 0.0),
                temperature_celsius=cpu_data.get("temperatureCelsius"),
                architecture=cpu_data.get("architecture", ""),
            )

        if "memory" in data and data["memory"]:
            mem_data = data["memory"]
            metrics.memory = MemoryMetrics(
                total=mem_data.get("total", 0),
                used=mem_data.get("used", 0),
                available=mem_data.get("available", 0),
                swap_total=mem_data.get("swapTotal", 0),
                swap_used=mem_data.get("swapUsed", 0),
                cached=mem_data.get("cached", 0),
                buffers=mem_data.get("buffers", 0),
                memory_type=mem_data.get("memoryType", ""),
                speed_mhz=mem_data.get("speedMhz", 0),
            )

        if "disks" in data:
            for disk_data in data["disks"]:
                metrics.disks.append(DiskMetrics(
                    mount_point=disk_data.get("mountPoint", ""),
                    device=disk_data.get("device", ""),
                    fs_type=disk_data.get("fsType", ""),
                    total=disk_data.get("total", 0),
                    used=disk_data.get("used", 0),
                    available=disk_data.get("available", 0),
                    read_bytes_per_sec=disk_data.get("readBytesPerSec", 0),
                    write_bytes_per_sec=disk_data.get("writeBytesPerSec", 0),
                    read_iops=disk_data.get("readIops", 0),
                    write_iops=disk_data.get("writeIops", 0),
                    model=disk_data.get("model", ""),
                    serial=disk_data.get("serial", ""),
                    disk_type=disk_data.get("diskType", ""),
                    temperature_celsius=disk_data.get("temperatureCelsius"),
                    health_status=disk_data.get("healthStatus", ""),
                ))

        if "networks" in data:
            for net_data in data["networks"]:
                metrics.networks.append(NetworkMetrics(
                    interface=net_data.get("interface", ""),
                    rx_bytes_per_sec=net_data.get("rxBytesPerSec", 0),
                    tx_bytes_per_sec=net_data.get("txBytesPerSec", 0),
                    rx_packets_per_sec=net_data.get("rxPacketsPerSec", 0),
                    tx_packets_per_sec=net_data.get("txPacketsPerSec", 0),
                    is_up=net_data.get("isUp", False),
                    mac_address=net_data.get("macAddress", ""),
                    ip_addresses=net_data.get("ipAddresses", []),
                    link_speed_mbps=net_data.get("linkSpeedMbps", 0),
                    interface_type=net_data.get("interfaceType", ""),
                ))

        if "gpus" in data:
            for gpu_data in data["gpus"]:
                metrics.gpus.append(GpuMetrics(
                    index=gpu_data.get("index", 0),
                    name=gpu_data.get("name", ""),
                    vendor=gpu_data.get("vendor", ""),
                    usage_percent=gpu_data.get("usagePercent", 0.0),
                    memory_total=gpu_data.get("memoryTotal", 0),
                    memory_used=gpu_data.get("memoryUsed", 0),
                    temperature_celsius=gpu_data.get("temperatureCelsius", 0.0),
                    fan_speed_percent=gpu_data.get("fanSpeedPercent", 0.0),
                    power_draw_watts=gpu_data.get("powerDrawWatts", 0.0),
                    power_limit_watts=gpu_data.get("powerLimitWatts", 0.0),
                    clock_core_mhz=gpu_data.get("clockCoreMhz", 0),
                    clock_memory_mhz=gpu_data.get("clockMemoryMhz", 0),
                    driver_version=gpu_data.get("driverVersion", ""),
                    pcie_gen=gpu_data.get("pcieGen", 0),
                    pcie_width=gpu_data.get("pcieWidth", 0),
                    encoder_usage_percent=gpu_data.get("encoderUsagePercent", 0.0),
                    decoder_usage_percent=gpu_data.get("decoderUsagePercent", 0.0),
                ))

        if "npus" in data:
            for npu_data in data["npus"]:
                metrics.npus.append(NpuMetrics(
                    index=npu_data.get("index", 0),
                    name=npu_data.get("name", ""),
                    vendor=npu_data.get("vendor", ""),
                    usage_percent=npu_data.get("usagePercent", 0.0),
                    memory_total=npu_data.get("memoryTotal", 0),
                    memory_used=npu_data.get("memoryUsed", 0),
                    temperature_celsius=npu_data.get("temperatureCelsius", 0.0),
                    power_watts=npu_data.get("powerWatts", 0),
                    driver_version=npu_data.get("driverVersion", ""),
                ))

        if "userSessions" in data:
            for session_data in data["userSessions"]:
                metrics.user_sessions.append(UserSession(
                    username=session_data.get("username", ""),
                    tty=session_data.get("tty", ""),
                    login_time=session_data.get("loginTime", 0),
                    remote_host=session_data.get("remoteHost", ""),
                    idle_seconds=session_data.get("idleSeconds", 0),
                    session_type=session_data.get("sessionType", ""),
                ))

        if "system" in data and data["system"]:
            sys_data = data["system"]
            metrics.system = SystemInfo(
                os_name=sys_data.get("osName", ""),
                os_version=sys_data.get("osVersion", ""),
                kernel_version=sys_data.get("kernelVersion", ""),
                hostname=sys_data.get("hostname", ""),
                boot_time=sys_data.get("bootTime", 0),
                uptime_seconds=sys_data.get("uptimeSeconds", 0),
                motherboard_model=sys_data.get("motherboardModel", ""),
                motherboard_vendor=sys_data.get("motherboardVendor", ""),
                bios_version=sys_data.get("biosVersion", ""),
            )

        metrics.load_average = data.get("loadAverage", [])

        return metrics


# ========== Layered Metrics Types ==========

@dataclass
class DiskIO:
    """Disk IO metrics (realtime)"""
    device: str = ""
    read_bytes_per_sec: int = 0
    write_bytes_per_sec: int = 0
    read_iops: int = 0
    write_iops: int = 0


@dataclass
class NetworkIO:
    """Network IO metrics (realtime)"""
    interface: str = ""
    rx_bytes_per_sec: int = 0
    tx_bytes_per_sec: int = 0
    rx_packets_per_sec: int = 0
    tx_packets_per_sec: int = 0
    is_up: bool = False


@dataclass
class GpuUsage:
    """GPU usage metrics (realtime)"""
    index: int = 0
    usage_percent: float = 0.0
    memory_used: int = 0
    temperature_celsius: float = 0.0
    power_watts: int = 0
    clock_core_mhz: int = 0
    encoder_usage: float = 0.0
    decoder_usage: float = 0.0


@dataclass
class NpuUsage:
    """NPU usage metrics (realtime)"""
    index: int = 0
    usage_percent: float = 0.0
    memory_used: int = 0
    temperature_celsius: float = 0.0
    power_watts: int = 0


@dataclass
class RealtimeMetrics:
    """Realtime metrics sent every second (lightweight)"""
    timestamp: int = 0
    hostname: str = ""
    cpu_usage_percent: float = 0.0
    cpu_per_core: List[float] = field(default_factory=list)
    cpu_temperature: float = 0.0
    cpu_frequency_mhz: int = 0
    memory_used: int = 0
    memory_cached: int = 0
    swap_used: int = 0
    disk_io: List[DiskIO] = field(default_factory=list)
    network_io: List[NetworkIO] = field(default_factory=list)
    load_average: List[float] = field(default_factory=list)
    gpu_usage: List[GpuUsage] = field(default_factory=list)
    npu_usage: List[NpuUsage] = field(default_factory=list)

    @classmethod
    def from_dict(cls, data: dict) -> "RealtimeMetrics":
        """Create RealtimeMetrics from dictionary"""
        metrics = cls()
        metrics.timestamp = data.get("timestamp", 0)
        metrics.hostname = data.get("hostname", "")
        metrics.cpu_usage_percent = data.get("cpuUsagePercent", 0.0)
        metrics.cpu_per_core = data.get("cpuPerCore", [])
        metrics.cpu_temperature = data.get("cpuTemperature", 0.0)
        metrics.cpu_frequency_mhz = data.get("cpuFrequencyMhz", 0)
        metrics.memory_used = data.get("memoryUsed", 0)
        metrics.memory_cached = data.get("memoryCached", 0)
        metrics.swap_used = data.get("swapUsed", 0)
        metrics.load_average = data.get("loadAverage", [])

        for d in data.get("diskIo", []):
            metrics.disk_io.append(DiskIO(
                device=d.get("device", ""),
                read_bytes_per_sec=d.get("readBytesSec", 0),
                write_bytes_per_sec=d.get("writeBytesSec", 0),
                read_iops=d.get("readIops", 0),
                write_iops=d.get("writeIops", 0),
            ))

        for n in data.get("networkIo", []):
            metrics.network_io.append(NetworkIO(
                interface=n.get("interface", ""),
                rx_bytes_per_sec=n.get("rxBytesSec", 0),
                tx_bytes_per_sec=n.get("txBytesSec", 0),
                rx_packets_per_sec=n.get("rxPacketsSec", 0),
                tx_packets_per_sec=n.get("txPacketsSec", 0),
                is_up=n.get("isUp", False),
            ))

        for g in data.get("gpuUsage", []):
            metrics.gpu_usage.append(GpuUsage(
                index=g.get("index", 0),
                usage_percent=g.get("usagePercent", 0.0),
                memory_used=g.get("memoryUsed", 0),
                temperature_celsius=g.get("temperature", 0.0),
                power_watts=g.get("powerWatts", 0),
                clock_core_mhz=g.get("clockCoreMhz", 0),
                encoder_usage=g.get("encoderUsage", 0.0),
                decoder_usage=g.get("decoderUsage", 0.0),
            ))

        for n in data.get("npuUsage", []):
            metrics.npu_usage.append(NpuUsage(
                index=n.get("index", 0),
                usage_percent=n.get("usagePercent", 0.0),
                memory_used=n.get("memoryUsed", 0),
                temperature_celsius=n.get("temperature", 0.0),
                power_watts=n.get("powerWatts", 0),
            ))

        return metrics


@dataclass
class CpuStaticInfo:
    """CPU static information"""
    model: str = ""
    vendor: str = ""
    physical_cores: int = 0
    logical_cores: int = 0
    architecture: str = ""
    frequency_max_mhz: int = 0
    l1_cache_kb: int = 0
    l2_cache_kb: int = 0
    l3_cache_kb: int = 0


@dataclass
class MemoryStaticInfo:
    """Memory static information"""
    total: int = 0
    swap_total: int = 0
    memory_type: str = ""
    speed_mhz: int = 0
    slots: int = 0


@dataclass
class DiskStaticInfo:
    """Disk static information"""
    device: str = ""
    mount_point: str = ""
    fs_type: str = ""
    model: str = ""
    serial: str = ""
    disk_type: str = ""
    total_bytes: int = 0
    health_status: str = ""


@dataclass
class NetworkStaticInfo:
    """Network static information"""
    interface: str = ""
    mac_address: str = ""
    ip_addresses: List[str] = field(default_factory=list)
    speed_mbps: int = 0
    interface_type: str = ""
    is_virtual: bool = False


@dataclass
class GpuStaticInfo:
    """GPU static information"""
    index: int = 0
    name: str = ""
    vendor: str = ""
    memory_total: int = 0
    driver_version: str = ""
    pcie_generation: str = ""
    power_limit_watts: int = 0


@dataclass
class NpuStaticInfo:
    """NPU static information"""
    index: int = 0
    name: str = ""
    vendor: str = ""
    memory_total: int = 0
    driver_version: str = ""


@dataclass
class StaticInfo:
    """Static hardware information (sent once on connect or on request)"""
    timestamp: int = 0
    hostname: str = ""
    cpu: Optional[CpuStaticInfo] = None
    memory: Optional[MemoryStaticInfo] = None
    disks: List[DiskStaticInfo] = field(default_factory=list)
    networks: List[NetworkStaticInfo] = field(default_factory=list)
    gpus: List[GpuStaticInfo] = field(default_factory=list)
    npus: List[NpuStaticInfo] = field(default_factory=list)
    system: Optional[SystemInfo] = None

    @classmethod
    def from_dict(cls, data: dict) -> "StaticInfo":
        """Create StaticInfo from dictionary"""
        info = cls()
        info.timestamp = data.get("timestamp", 0)
        info.hostname = data.get("hostname", "")

        if "cpu" in data and data["cpu"]:
            c = data["cpu"]
            info.cpu = CpuStaticInfo(
                model=c.get("model", ""),
                vendor=c.get("vendor", ""),
                physical_cores=c.get("physicalCores", 0),
                logical_cores=c.get("logicalCores", 0),
                architecture=c.get("architecture", ""),
                frequency_max_mhz=c.get("frequencyMaxMhz", 0),
                l1_cache_kb=c.get("l1CacheKb", 0),
                l2_cache_kb=c.get("l2CacheKb", 0),
                l3_cache_kb=c.get("l3CacheKb", 0),
            )

        if "memory" in data and data["memory"]:
            m = data["memory"]
            info.memory = MemoryStaticInfo(
                total=m.get("total", 0),
                swap_total=m.get("swapTotal", 0),
                memory_type=m.get("memoryType", ""),
                speed_mhz=m.get("memorySpeedMhz", 0),
                slots=m.get("memorySlots", 0),
            )

        for d in data.get("disks", []):
            info.disks.append(DiskStaticInfo(
                device=d.get("device", ""),
                mount_point=d.get("mountPoint", ""),
                fs_type=d.get("fsType", ""),
                model=d.get("model", ""),
                serial=d.get("serial", ""),
                disk_type=d.get("diskType", ""),
                total_bytes=d.get("totalBytes", 0),
                health_status=d.get("healthStatus", ""),
            ))

        for n in data.get("networks", []):
            info.networks.append(NetworkStaticInfo(
                interface=n.get("interface", ""),
                mac_address=n.get("macAddress", ""),
                ip_addresses=n.get("ipAddresses", []),
                speed_mbps=n.get("speedMbps", 0),
                interface_type=n.get("interfaceType", ""),
                is_virtual=n.get("isVirtual", False),
            ))

        for g in data.get("gpus", []):
            info.gpus.append(GpuStaticInfo(
                index=g.get("index", 0),
                name=g.get("name", ""),
                vendor=g.get("vendor", ""),
                memory_total=g.get("memoryTotal", 0),
                driver_version=g.get("driverVersion", ""),
                pcie_generation=g.get("pcieGeneration", ""),
                power_limit_watts=g.get("powerLimitWatts", 0),
            ))

        for n in data.get("npus", []):
            info.npus.append(NpuStaticInfo(
                index=n.get("index", 0),
                name=n.get("name", ""),
                vendor=n.get("vendor", ""),
                memory_total=n.get("memoryTotal", 0),
                driver_version=n.get("driverVersion", ""),
            ))

        if "systemInfo" in data and data["systemInfo"]:
            s = data["systemInfo"]
            info.system = SystemInfo(
                os_name=s.get("osName", ""),
                os_version=s.get("osVersion", ""),
                kernel_version=s.get("kernelVersion", ""),
                hostname=s.get("hostname", ""),
                boot_time=s.get("bootTime", 0),
                uptime_seconds=s.get("uptimeSeconds", 0),
                motherboard_model=s.get("motherboardModel", ""),
                motherboard_vendor=s.get("motherboardVendor", ""),
                bios_version=s.get("biosVersion", ""),
            )

        return info


@dataclass
class DiskUsage:
    """Disk usage data (periodic)"""
    device: str = ""
    mount_point: str = ""
    total: int = 0
    used: int = 0
    available: int = 0
    temperature_celsius: float = 0.0

    @property
    def usage_percent(self) -> float:
        if self.total == 0:
            return 0.0
        return (self.used / self.total) * 100


@dataclass
class NetworkAddressUpdate:
    """Network address update (periodic)"""
    interface: str = ""
    ip_addresses: List[str] = field(default_factory=list)
    is_up: bool = False


@dataclass
class PeriodicData:
    """Periodic data (disk usage, user sessions - sent less frequently)"""
    timestamp: int = 0
    hostname: str = ""
    disk_usage: List[DiskUsage] = field(default_factory=list)
    user_sessions: List[UserSession] = field(default_factory=list)
    network_updates: List[NetworkAddressUpdate] = field(default_factory=list)

    @classmethod
    def from_dict(cls, data: dict) -> "PeriodicData":
        """Create PeriodicData from dictionary"""
        periodic = cls()
        periodic.timestamp = data.get("timestamp", 0)
        periodic.hostname = data.get("hostname", "")

        for d in data.get("diskUsage", []):
            periodic.disk_usage.append(DiskUsage(
                device=d.get("device", ""),
                mount_point=d.get("mountPoint", ""),
                total=d.get("total", 0),
                used=d.get("used", 0),
                available=d.get("available", 0),
                temperature_celsius=d.get("temperature", 0.0),
            ))

        for s in data.get("userSessions", []):
            periodic.user_sessions.append(UserSession(
                username=s.get("username", ""),
                tty=s.get("tty", ""),
                login_time=s.get("loginTime", 0),
                remote_host=s.get("remoteHost", ""),
                idle_seconds=s.get("idleSeconds", 0),
                session_type=s.get("sessionType", ""),
            ))

        for n in data.get("networkUpdates", []):
            periodic.network_updates.append(NetworkAddressUpdate(
                interface=n.get("interface", ""),
                ip_addresses=n.get("ipAddresses", []),
                is_up=n.get("isUp", False),
            ))

        return periodic
