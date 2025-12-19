"""
Metrics data models for NanoLink SDK
"""

from dataclasses import dataclass, field
from typing import List, Optional


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
