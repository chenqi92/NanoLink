package com.kkape.demo.model;

import com.kkape.sdk.model.Metrics;

import java.time.Instant;
import java.util.List;

/**
 * Complete metrics from an agent including system info, GPU, and user sessions
 */
public record AgentMetrics(
        String hostname,
        Instant timestamp,
        CpuInfo cpu,
        MemoryInfo memory,
        List<DiskInfo> disks,
        List<NetworkInfo> networks,
        double[] loadAverage,
        SystemInfo systemInfo,
        List<GpuInfo> gpus,
        List<UserSessionInfo> userSessions,
        List<NpuInfo> npus
) {

    /**
     * Create AgentMetrics from SDK Metrics
     */
    public static AgentMetrics from(Metrics metrics) {
        var cpu = metrics.getCpu();
        var memory = metrics.getMemory();

        CpuInfo cpuInfo = null;
        if (cpu != null) {
            cpuInfo = new CpuInfo(
                    cpu.getUsagePercent(),
                    cpu.getCoreCount(),
                    cpu.getPerCoreUsage(),
                    cpu.getModel(),
                    cpu.getVendor(),
                    cpu.getFrequencyMhz(),
                    cpu.getFrequencyMaxMhz(),
                    cpu.getPhysicalCores(),
                    cpu.getLogicalCores(),
                    cpu.getArchitecture(),
                    cpu.getTemperature()
            );
        }

        MemoryInfo memoryInfo = null;
        if (memory != null) {
            memoryInfo = new MemoryInfo(
                    memory.getTotal(),
                    memory.getUsed(),
                    memory.getAvailable(),
                    memory.getUsagePercent(),
                    memory.getSwapTotal(),
                    memory.getSwapUsed(),
                    memory.getCached(),
                    memory.getBuffers(),
                    memory.getMemoryType(),
                    memory.getMemorySpeedMhz()
            );
        }

        List<DiskInfo> disks = List.of();
        if (metrics.getDisks() != null) {
            disks = metrics.getDisks().stream()
                    .map(d -> new DiskInfo(
                            d.getMountPoint(),
                            d.getDevice(),
                            d.getFsType(),
                            d.getTotal(),
                            d.getUsed(),
                            d.getAvailable(),
                            d.getUsagePercent(),
                            d.getReadBytesPerSec(),
                            d.getWriteBytesPerSec(),
                            d.getModel(),
                            d.getSerial(),
                            d.getDiskType(),
                            d.getReadIops(),
                            d.getWriteIops(),
                            d.getTemperature(),
                            d.getHealthStatus()
                    ))
                    .toList();
        }

        List<NetworkInfo> networks = List.of();
        if (metrics.getNetworks() != null) {
            networks = metrics.getNetworks().stream()
                    .map(n -> new NetworkInfo(
                            n.getInterfaceName(),
                            n.isUp(),
                            n.getRxBytesPerSec(),
                            n.getTxBytesPerSec(),
                            n.getRxPacketsPerSec(),
                            n.getTxPacketsPerSec(),
                            n.getMacAddress(),
                            n.getIpAddresses(),
                            n.getSpeedMbps(),
                            n.getInterfaceType()
                    ))
                    .toList();
        }

        SystemInfo sysInfo = null;
        if (metrics.getSystemInfo() != null) {
            var si = metrics.getSystemInfo();
            sysInfo = new SystemInfo(
                    si.getOsName(),
                    si.getOsVersion(),
                    si.getKernelVersion(),
                    si.getHostname(),
                    si.getBootTime(),
                    si.getUptimeSeconds(),
                    si.getMotherboardModel(),
                    si.getMotherboardVendor(),
                    si.getBiosVersion(),
                    si.getSystemModel(),
                    si.getSystemVendor()
            );
        }

        List<GpuInfo> gpus = List.of();
        if (metrics.getGpus() != null) {
            gpus = metrics.getGpus().stream()
                    .map(g -> new GpuInfo(
                            g.getIndex(),
                            g.getName(),
                            g.getVendor(),
                            g.getUsagePercent(),
                            g.getMemoryTotal(),
                            g.getMemoryUsed(),
                            g.getTemperature(),
                            g.getFanSpeedPercent(),
                            g.getPowerWatts(),
                            g.getPowerLimitWatts(),
                            g.getClockCoreMhz(),
                            g.getClockMemoryMhz(),
                            g.getDriverVersion(),
                            g.getPcieGeneration(),
                            g.getEncoderUsage(),
                            g.getDecoderUsage()
                    ))
                    .toList();
        }

        List<UserSessionInfo> sessions = List.of();
        if (metrics.getUserSessions() != null) {
            sessions = metrics.getUserSessions().stream()
                    .map(s -> new UserSessionInfo(
                            s.getUsername(),
                            s.getTty(),
                            s.getLoginTime(),
                            s.getRemoteHost(),
                            s.getIdleSeconds(),
                            s.getSessionType()
                    ))
                    .toList();
        }

        List<NpuInfo> npus = List.of();
        if (metrics.getNpus() != null) {
            npus = metrics.getNpus().stream()
                    .map(n -> new NpuInfo(
                            n.getIndex(),
                            n.getName(),
                            n.getVendor(),
                            n.getUsagePercent(),
                            n.getMemoryTotal(),
                            n.getMemoryUsed(),
                            n.getTemperature(),
                            n.getPowerWatts(),
                            n.getDriverVersion()
                    ))
                    .toList();
        }

        return new AgentMetrics(
                metrics.getHostname(),
                Instant.ofEpochMilli(metrics.getTimestamp()),
                cpuInfo,
                memoryInfo,
                disks,
                networks,
                metrics.getLoadAverage(),
                sysInfo,
                gpus,
                sessions,
                npus
        );
    }

    // CPU information
    public record CpuInfo(
            double usagePercent,
            int coreCount,
            double[] perCoreUsage,
            String model,
            String vendor,
            long frequencyMhz,
            long frequencyMaxMhz,
            int physicalCores,
            int logicalCores,
            String architecture,
            double temperature
    ) {}

    // Memory information
    public record MemoryInfo(
            long total,
            long used,
            long available,
            double usagePercent,
            long swapTotal,
            long swapUsed,
            long cached,
            long buffers,
            String memoryType,
            int memorySpeedMhz
    ) {}

    // Disk information
    public record DiskInfo(
            String mountPoint,
            String device,
            String fsType,
            long total,
            long used,
            long available,
            double usagePercent,
            long readBytesPerSec,
            long writeBytesPerSec,
            String model,
            String serial,
            String diskType,
            long readIops,
            long writeIops,
            double temperature,
            String healthStatus
    ) {}

    // Network interface information
    public record NetworkInfo(
            String interfaceName,
            boolean isUp,
            long rxBytesPerSec,
            long txBytesPerSec,
            long rxPacketsPerSec,
            long txPacketsPerSec,
            String macAddress,
            List<String> ipAddresses,
            long speedMbps,
            String interfaceType
    ) {}

    // System information
    public record SystemInfo(
            String osName,
            String osVersion,
            String kernelVersion,
            String hostname,
            long bootTime,
            long uptimeSeconds,
            String motherboardModel,
            String motherboardVendor,
            String biosVersion,
            String systemModel,
            String systemVendor
    ) {}

    // GPU information
    public record GpuInfo(
            int index,
            String name,
            String vendor,
            double usagePercent,
            long memoryTotal,
            long memoryUsed,
            double temperature,
            int fanSpeedPercent,
            int powerWatts,
            int powerLimitWatts,
            long clockCoreMhz,
            long clockMemoryMhz,
            String driverVersion,
            String pcieGeneration,
            double encoderUsage,
            double decoderUsage
    ) {}

    // User session information
    public record UserSessionInfo(
            String username,
            String tty,
            long loginTime,
            String remoteHost,
            long idleSeconds,
            String sessionType
    ) {}

    // NPU/AI accelerator information
    public record NpuInfo(
            int index,
            String name,
            String vendor,
            double usagePercent,
            long memoryTotal,
            long memoryUsed,
            double temperature,
            int powerWatts,
            String driverVersion
    ) {}
}
