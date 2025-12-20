"""Tests for metrics module"""

import pytest
from nanolink.metrics import (
    Metrics,
    CpuMetrics,
    MemoryMetrics,
    DiskMetrics,
    NetworkMetrics,
    GpuMetrics,
    NpuMetrics,
    UserSession,
    SystemInfo,
)


class TestCpuMetrics:
    def test_default_values(self):
        cpu = CpuMetrics()
        assert cpu.usage_percent == 0.0
        assert cpu.core_count == 0
        assert cpu.per_core_usage == []
        assert cpu.model == ""

    def test_with_values(self):
        cpu = CpuMetrics(
            usage_percent=75.5,
            core_count=8,
            per_core_usage=[70.0, 80.0, 75.0, 77.0, 72.0, 78.0, 74.0, 76.0],
            model="Intel Core i7-9700K",
            vendor="Intel",
            frequency_mhz=3600.0,
        )
        assert cpu.usage_percent == 75.5
        assert cpu.core_count == 8
        assert len(cpu.per_core_usage) == 8
        assert cpu.model == "Intel Core i7-9700K"
        assert cpu.vendor == "Intel"


class TestMemoryMetrics:
    def test_usage_percent(self):
        memory = MemoryMetrics(total=16000000000, used=8000000000)
        assert memory.usage_percent == 50.0

    def test_usage_percent_zero_total(self):
        memory = MemoryMetrics(total=0, used=100)
        assert memory.usage_percent == 0.0

    def test_swap_usage_percent(self):
        memory = MemoryMetrics(swap_total=8000000000, swap_used=2000000000)
        assert memory.swap_usage_percent == 25.0

    def test_swap_usage_percent_zero_total(self):
        memory = MemoryMetrics(swap_total=0, swap_used=100)
        assert memory.swap_usage_percent == 0.0


class TestDiskMetrics:
    def test_usage_percent(self):
        disk = DiskMetrics(total=500000000000, used=250000000000)
        assert disk.usage_percent == 50.0

    def test_usage_percent_zero_total(self):
        disk = DiskMetrics(total=0, used=100)
        assert disk.usage_percent == 0.0

    def test_with_all_fields(self):
        disk = DiskMetrics(
            mount_point="/",
            device="/dev/sda1",
            fs_type="ext4",
            total=500000000000,
            used=100000000000,
            available=400000000000,
            read_bytes_per_sec=1048576,
            write_bytes_per_sec=524288,
            model="Samsung SSD 970 EVO",
            disk_type="NVMe",
        )
        assert disk.mount_point == "/"
        assert disk.model == "Samsung SSD 970 EVO"
        assert disk.disk_type == "NVMe"


class TestNetworkMetrics:
    def test_default_values(self):
        network = NetworkMetrics()
        assert network.interface == ""
        assert network.is_up is False
        assert network.ip_addresses == []

    def test_with_values(self):
        network = NetworkMetrics(
            interface="eth0",
            rx_bytes_per_sec=1000000,
            tx_bytes_per_sec=500000,
            is_up=True,
            mac_address="00:11:22:33:44:55",
            ip_addresses=["192.168.1.100", "fe80::1"],
            link_speed_mbps=1000,
        )
        assert network.interface == "eth0"
        assert network.is_up is True
        assert len(network.ip_addresses) == 2


class TestGpuMetrics:
    def test_memory_usage_percent(self):
        gpu = GpuMetrics(memory_total=8000000000, memory_used=4000000000)
        assert gpu.memory_usage_percent == 50.0

    def test_memory_usage_percent_zero_total(self):
        gpu = GpuMetrics(memory_total=0, memory_used=100)
        assert gpu.memory_usage_percent == 0.0

    def test_with_all_fields(self):
        gpu = GpuMetrics(
            index=0,
            name="NVIDIA GeForce RTX 3080",
            vendor="NVIDIA",
            usage_percent=85.0,
            memory_total=10737418240,
            memory_used=8589934592,
            temperature_celsius=75.0,
            power_draw_watts=320.0,
        )
        assert gpu.name == "NVIDIA GeForce RTX 3080"
        assert gpu.usage_percent == 85.0
        assert gpu.temperature_celsius == 75.0


class TestMetrics:
    def test_default_values(self):
        metrics = Metrics()
        assert metrics.timestamp == 0
        assert metrics.hostname == ""
        assert metrics.cpu is None
        assert metrics.memory is None
        assert metrics.disks == []
        assert metrics.networks == []
        assert metrics.gpus == []

    def test_from_dict_basic(self):
        data = {
            "timestamp": 1234567890,
            "hostname": "test-server",
        }
        metrics = Metrics.from_dict(data)
        assert metrics.timestamp == 1234567890
        assert metrics.hostname == "test-server"

    def test_from_dict_with_cpu(self):
        data = {
            "timestamp": 1234567890,
            "hostname": "test-server",
            "cpu": {
                "usagePercent": 45.5,
                "coreCount": 8,
                "model": "Intel Core i7",
            },
        }
        metrics = Metrics.from_dict(data)
        assert metrics.cpu is not None
        assert metrics.cpu.usage_percent == 45.5
        assert metrics.cpu.core_count == 8
        assert metrics.cpu.model == "Intel Core i7"

    def test_from_dict_with_memory(self):
        data = {
            "timestamp": 1234567890,
            "hostname": "test-server",
            "memory": {
                "total": 16000000000,
                "used": 8000000000,
                "available": 8000000000,
            },
        }
        metrics = Metrics.from_dict(data)
        assert metrics.memory is not None
        assert metrics.memory.total == 16000000000
        assert metrics.memory.usage_percent == 50.0

    def test_from_dict_with_disks(self):
        data = {
            "timestamp": 1234567890,
            "hostname": "test-server",
            "disks": [
                {
                    "mountPoint": "/",
                    "device": "/dev/sda1",
                    "total": 500000000000,
                    "used": 100000000000,
                },
                {
                    "mountPoint": "/home",
                    "device": "/dev/sda2",
                    "total": 1000000000000,
                    "used": 500000000000,
                },
            ],
        }
        metrics = Metrics.from_dict(data)
        assert len(metrics.disks) == 2
        assert metrics.disks[0].mount_point == "/"
        assert metrics.disks[1].mount_point == "/home"

    def test_from_dict_with_gpus(self):
        data = {
            "timestamp": 1234567890,
            "hostname": "test-server",
            "gpus": [
                {
                    "index": 0,
                    "name": "NVIDIA RTX 3080",
                    "usagePercent": 75.0,
                    "memoryTotal": 10737418240,
                    "memoryUsed": 5368709120,
                },
            ],
        }
        metrics = Metrics.from_dict(data)
        assert len(metrics.gpus) == 1
        assert metrics.gpus[0].name == "NVIDIA RTX 3080"
        assert metrics.gpus[0].usage_percent == 75.0

    def test_from_dict_with_system(self):
        data = {
            "timestamp": 1234567890,
            "hostname": "test-server",
            "system": {
                "osName": "Ubuntu",
                "osVersion": "22.04",
                "kernelVersion": "5.15.0",
                "uptimeSeconds": 86400,
            },
        }
        metrics = Metrics.from_dict(data)
        assert metrics.system is not None
        assert metrics.system.os_name == "Ubuntu"
        assert metrics.system.os_version == "22.04"
        assert metrics.system.uptime_seconds == 86400

    def test_from_dict_with_load_average(self):
        data = {
            "timestamp": 1234567890,
            "hostname": "test-server",
            "loadAverage": [1.5, 2.0, 1.8],
        }
        metrics = Metrics.from_dict(data)
        assert len(metrics.load_average) == 3
        assert metrics.load_average[0] == 1.5

    def test_from_dict_with_npus(self):
        data = {
            "timestamp": 1234567890,
            "hostname": "test-server",
            "npus": [
                {
                    "index": 0,
                    "name": "Intel NPU",
                    "vendor": "Intel",
                    "usagePercent": 45.0,
                    "memoryTotal": 4000000000,
                    "memoryUsed": 2000000000,
                    "temperatureCelsius": 55.0,
                    "powerWatts": 15,
                },
            ],
        }
        metrics = Metrics.from_dict(data)
        assert len(metrics.npus) == 1
        assert metrics.npus[0].name == "Intel NPU"
        assert metrics.npus[0].vendor == "Intel"
        assert metrics.npus[0].usage_percent == 45.0

    def test_from_dict_with_user_sessions(self):
        data = {
            "timestamp": 1234567890,
            "hostname": "test-server",
            "userSessions": [
                {
                    "username": "admin",
                    "tty": "pts/0",
                    "loginTime": 1234567800,
                    "remoteHost": "192.168.1.100",
                    "idleSeconds": 60,
                    "sessionType": "ssh",
                },
            ],
        }
        metrics = Metrics.from_dict(data)
        assert len(metrics.user_sessions) == 1
        assert metrics.user_sessions[0].username == "admin"
        assert metrics.user_sessions[0].session_type == "ssh"


class TestNpuMetrics:
    def test_default_values(self):
        npu = NpuMetrics()
        assert npu.index == 0
        assert npu.name == ""
        assert npu.vendor == ""
        assert npu.usage_percent == 0.0

    def test_memory_usage_percent(self):
        npu = NpuMetrics(memory_total=4000000000, memory_used=2000000000)
        assert npu.memory_usage_percent == 50.0

    def test_memory_usage_percent_zero_total(self):
        npu = NpuMetrics(memory_total=0, memory_used=100)
        assert npu.memory_usage_percent == 0.0

    def test_with_all_fields(self):
        npu = NpuMetrics(
            index=0,
            name="Huawei Ascend 910B",
            vendor="Huawei",
            usage_percent=80.0,
            memory_total=32000000000,
            memory_used=24000000000,
            temperature_celsius=65.0,
            power_watts=300,
            driver_version="23.0.1",
        )
        assert npu.name == "Huawei Ascend 910B"
        assert npu.power_watts == 300


class TestUserSession:
    def test_default_values(self):
        session = UserSession()
        assert session.username == ""
        assert session.tty == ""
        assert session.login_time == 0
        assert session.session_type == ""

    def test_with_all_fields(self):
        session = UserSession(
            username="root",
            tty="console",
            login_time=1234567890,
            remote_host="",
            idle_seconds=120,
            session_type="local",
        )
        assert session.username == "root"
        assert session.tty == "console"
        assert session.session_type == "local"

