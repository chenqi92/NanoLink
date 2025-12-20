package com.kkape.demo.model;

import com.kkape.sdk.model.Metrics;
import com.kkape.sdk.model.PeriodicData;
import com.kkape.sdk.model.RealtimeMetrics;
import com.kkape.sdk.model.StaticInfo;

import java.time.Instant;
import java.util.ArrayList;
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

    /**
     * Create AgentMetrics from RealtimeMetrics (lightweight realtime data)
     */
    public static AgentMetrics fromRealtime(RealtimeMetrics realtime) {
        CpuInfo cpuInfo = new CpuInfo(
                realtime.getCpuUsagePercent(),
                realtime.getCpuPerCore() != null ? realtime.getCpuPerCore().length : 0,
                realtime.getCpuPerCore(),
                null, null,
                realtime.getCpuFrequencyMhz(),
                0, 0, 0, null,
                realtime.getCpuTemperature()
        );

        MemoryInfo memoryInfo = new MemoryInfo(
                0, // total from static info
                realtime.getMemoryUsed(),
                0, 0,
                0,
                realtime.getSwapUsed(),
                realtime.getMemoryCached(),
                0, null, 0
        );

        // Convert disk IO
        List<DiskInfo> disks = new ArrayList<>();
        if (realtime.getDiskIo() != null) {
            for (var disk : realtime.getDiskIo()) {
                disks.add(new DiskInfo(
                        null, disk.getDevice(), null,
                        0, 0, 0, 0,
                        disk.getReadBytesSec(), disk.getWriteBytesSec(),
                        null, null, null,
                        disk.getReadIops(), disk.getWriteIops(),
                        0, null
                ));
            }
        }

        // Convert network IO
        List<NetworkInfo> networks = new ArrayList<>();
        if (realtime.getNetworkIo() != null) {
            for (var net : realtime.getNetworkIo()) {
                networks.add(new NetworkInfo(
                        net.getInterfaceName(), net.isUp(),
                        net.getRxBytesSec(), net.getTxBytesSec(),
                        net.getRxPacketsSec(), net.getTxPacketsSec(),
                        null, null, 0, null
                ));
            }
        }

        // Convert GPU usage
        List<GpuInfo> gpus = new ArrayList<>();
        if (realtime.getGpuUsage() != null) {
            for (var gpu : realtime.getGpuUsage()) {
                gpus.add(new GpuInfo(
                        gpu.getIndex(), null, null,
                        gpu.getUsagePercent(), 0, gpu.getMemoryUsed(),
                        gpu.getTemperature(), 0, gpu.getPowerWatts(), 0,
                        gpu.getClockCoreMhz(), 0, null, null,
                        gpu.getEncoderUsage(), gpu.getDecoderUsage()
                ));
            }
        }

        // Convert NPU usage
        List<NpuInfo> npus = new ArrayList<>();
        if (realtime.getNpuUsage() != null) {
            for (var npu : realtime.getNpuUsage()) {
                npus.add(new NpuInfo(
                        npu.getIndex(), null, null,
                        npu.getUsagePercent(), 0, npu.getMemoryUsed(),
                        npu.getTemperature(), npu.getPowerWatts(), null
                ));
            }
        }

        return new AgentMetrics(
                realtime.getHostname(),
                Instant.ofEpochMilli(realtime.getTimestamp()),
                cpuInfo, memoryInfo, disks, networks,
                realtime.getLoadAverage(),
                null, gpus, List.of(), npus
        );
    }

    /**
     * Merge realtime data into existing metrics
     */
    public static AgentMetrics mergeRealtime(AgentMetrics existing, RealtimeMetrics realtime) {
        // Update CPU with realtime values but keep static info
        CpuInfo cpuInfo = existing.cpu() != null ? new CpuInfo(
                realtime.getCpuUsagePercent(),
                existing.cpu().coreCount(),
                realtime.getCpuPerCore(),
                existing.cpu().model(),
                existing.cpu().vendor(),
                realtime.getCpuFrequencyMhz(),
                existing.cpu().frequencyMaxMhz(),
                existing.cpu().physicalCores(),
                existing.cpu().logicalCores(),
                existing.cpu().architecture(),
                realtime.getCpuTemperature()
        ) : new CpuInfo(
                realtime.getCpuUsagePercent(), 0, realtime.getCpuPerCore(),
                null, null, realtime.getCpuFrequencyMhz(), 0, 0, 0, null,
                realtime.getCpuTemperature()
        );

        // Update memory with realtime values but keep total from static
        MemoryInfo memoryInfo = existing.memory() != null ? new MemoryInfo(
                existing.memory().total(),
                realtime.getMemoryUsed(),
                existing.memory().total() - realtime.getMemoryUsed(),
                existing.memory().total() > 0 ? (double) realtime.getMemoryUsed() / existing.memory().total() * 100 : 0,
                existing.memory().swapTotal(),
                realtime.getSwapUsed(),
                realtime.getMemoryCached(),
                existing.memory().buffers(),
                existing.memory().memoryType(),
                existing.memory().memorySpeedMhz()
        ) : new MemoryInfo(0, realtime.getMemoryUsed(), 0, 0, 0,
                realtime.getSwapUsed(), realtime.getMemoryCached(), 0, null, 0);

        // Merge disk IO into existing disks
        List<DiskInfo> disks = new ArrayList<>(existing.disks());
        if (realtime.getDiskIo() != null) {
            for (var io : realtime.getDiskIo()) {
                boolean found = false;
                for (int i = 0; i < disks.size(); i++) {
                    if (disks.get(i).device() != null && disks.get(i).device().equals(io.getDevice())) {
                        var old = disks.get(i);
                        disks.set(i, new DiskInfo(
                                old.mountPoint(), old.device(), old.fsType(),
                                old.total(), old.used(), old.available(), old.usagePercent(),
                                io.getReadBytesSec(), io.getWriteBytesSec(),
                                old.model(), old.serial(), old.diskType(),
                                io.getReadIops(), io.getWriteIops(),
                                old.temperature(), old.healthStatus()
                        ));
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    disks.add(new DiskInfo(null, io.getDevice(), null, 0, 0, 0, 0,
                            io.getReadBytesSec(), io.getWriteBytesSec(), null, null, null,
                            io.getReadIops(), io.getWriteIops(), 0, null));
                }
            }
        }

        // Merge network IO
        List<NetworkInfo> networks = new ArrayList<>(existing.networks());
        if (realtime.getNetworkIo() != null) {
            for (var io : realtime.getNetworkIo()) {
                boolean found = false;
                for (int i = 0; i < networks.size(); i++) {
                    if (networks.get(i).interfaceName() != null && networks.get(i).interfaceName().equals(io.getInterfaceName())) {
                        var old = networks.get(i);
                        networks.set(i, new NetworkInfo(
                                old.interfaceName(), io.isUp(),
                                io.getRxBytesSec(), io.getTxBytesSec(),
                                io.getRxPacketsSec(), io.getTxPacketsSec(),
                                old.macAddress(), old.ipAddresses(), old.speedMbps(), old.interfaceType()
                        ));
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    networks.add(new NetworkInfo(io.getInterfaceName(), io.isUp(),
                            io.getRxBytesSec(), io.getTxBytesSec(), io.getRxPacketsSec(), io.getTxPacketsSec(),
                            null, null, 0, null));
                }
            }
        }

        // Merge GPU usage
        List<GpuInfo> gpus = new ArrayList<>(existing.gpus());
        if (realtime.getGpuUsage() != null) {
            for (var usage : realtime.getGpuUsage()) {
                boolean found = false;
                for (int i = 0; i < gpus.size(); i++) {
                    if (gpus.get(i).index() == usage.getIndex()) {
                        var old = gpus.get(i);
                        gpus.set(i, new GpuInfo(
                                old.index(), old.name(), old.vendor(),
                                usage.getUsagePercent(), old.memoryTotal(), usage.getMemoryUsed(),
                                usage.getTemperature(), old.fanSpeedPercent(), usage.getPowerWatts(),
                                old.powerLimitWatts(), usage.getClockCoreMhz(), old.clockMemoryMhz(),
                                old.driverVersion(), old.pcieGeneration(),
                                usage.getEncoderUsage(), usage.getDecoderUsage()
                        ));
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    gpus.add(new GpuInfo(usage.getIndex(), null, null, usage.getUsagePercent(),
                            0, usage.getMemoryUsed(), usage.getTemperature(), 0, usage.getPowerWatts(),
                            0, usage.getClockCoreMhz(), 0, null, null,
                            usage.getEncoderUsage(), usage.getDecoderUsage()));
                }
            }
        }

        // Merge NPU usage
        List<NpuInfo> npus = new ArrayList<>(existing.npus());
        if (realtime.getNpuUsage() != null) {
            for (var usage : realtime.getNpuUsage()) {
                boolean found = false;
                for (int i = 0; i < npus.size(); i++) {
                    if (npus.get(i).index() == usage.getIndex()) {
                        var old = npus.get(i);
                        npus.set(i, new NpuInfo(
                                old.index(), old.name(), old.vendor(),
                                usage.getUsagePercent(), old.memoryTotal(), usage.getMemoryUsed(),
                                usage.getTemperature(), usage.getPowerWatts(), old.driverVersion()
                        ));
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    npus.add(new NpuInfo(usage.getIndex(), null, null, usage.getUsagePercent(),
                            0, usage.getMemoryUsed(), usage.getTemperature(), usage.getPowerWatts(), null));
                }
            }
        }

        return new AgentMetrics(
                existing.hostname(),
                Instant.ofEpochMilli(realtime.getTimestamp()),
                cpuInfo, memoryInfo, disks, networks,
                realtime.getLoadAverage() != null ? realtime.getLoadAverage() : existing.loadAverage(),
                existing.systemInfo(), gpus, existing.userSessions(), npus
        );
    }

    /**
     * Merge static info into existing metrics
     */
    public static AgentMetrics mergeStaticInfo(AgentMetrics existing, StaticInfo staticInfo) {
        // Update CPU with static info
        CpuInfo cpuInfo = existing.cpu();
        if (staticInfo.getCpu() != null) {
            var sc = staticInfo.getCpu();
            cpuInfo = new CpuInfo(
                    existing.cpu() != null ? existing.cpu().usagePercent() : 0,
                    sc.getLogicalCores(),
                    existing.cpu() != null ? existing.cpu().perCoreUsage() : null,
                    sc.getModel(), sc.getVendor(),
                    existing.cpu() != null ? existing.cpu().frequencyMhz() : 0,
                    sc.getFrequencyMaxMhz(), sc.getPhysicalCores(), sc.getLogicalCores(),
                    sc.getArchitecture(),
                    existing.cpu() != null ? existing.cpu().temperature() : 0
            );
        }

        // Update memory with static info
        MemoryInfo memoryInfo = existing.memory();
        if (staticInfo.getMemory() != null) {
            var sm = staticInfo.getMemory();
            memoryInfo = new MemoryInfo(
                    sm.getTotal(),
                    existing.memory() != null ? existing.memory().used() : 0,
                    existing.memory() != null ? existing.memory().available() : 0,
                    existing.memory() != null ? existing.memory().usagePercent() : 0,
                    sm.getSwapTotal(),
                    existing.memory() != null ? existing.memory().swapUsed() : 0,
                    existing.memory() != null ? existing.memory().cached() : 0,
                    existing.memory() != null ? existing.memory().buffers() : 0,
                    sm.getMemoryType(), sm.getMemorySpeedMhz()
            );
        }

        // Update disks with static info
        List<DiskInfo> disks = new ArrayList<>();
        if (staticInfo.getDisks() != null) {
            for (var sd : staticInfo.getDisks()) {
                // Find existing disk by device
                DiskInfo existingDisk = existing.disks().stream()
                        .filter(d -> d.device() != null && d.device().equals(sd.getDevice()))
                        .findFirst().orElse(null);

                disks.add(new DiskInfo(
                        sd.getMountPoint(), sd.getDevice(), sd.getFsType(),
                        sd.getTotalBytes(),
                        existingDisk != null ? existingDisk.used() : 0,
                        existingDisk != null ? existingDisk.available() : 0,
                        existingDisk != null ? existingDisk.usagePercent() : 0,
                        existingDisk != null ? existingDisk.readBytesPerSec() : 0,
                        existingDisk != null ? existingDisk.writeBytesPerSec() : 0,
                        sd.getModel(), sd.getSerial(), sd.getDiskType(),
                        existingDisk != null ? existingDisk.readIops() : 0,
                        existingDisk != null ? existingDisk.writeIops() : 0,
                        existingDisk != null ? existingDisk.temperature() : 0,
                        sd.getHealthStatus()
                ));
            }
        } else {
            disks = existing.disks();
        }

        // Update networks with static info
        List<NetworkInfo> networks = new ArrayList<>();
        if (staticInfo.getNetworks() != null) {
            for (var sn : staticInfo.getNetworks()) {
                NetworkInfo existingNet = existing.networks().stream()
                        .filter(n -> n.interfaceName() != null && n.interfaceName().equals(sn.getInterfaceName()))
                        .findFirst().orElse(null);

                networks.add(new NetworkInfo(
                        sn.getInterfaceName(),
                        existingNet != null && existingNet.isUp(),
                        existingNet != null ? existingNet.rxBytesPerSec() : 0,
                        existingNet != null ? existingNet.txBytesPerSec() : 0,
                        existingNet != null ? existingNet.rxPacketsPerSec() : 0,
                        existingNet != null ? existingNet.txPacketsPerSec() : 0,
                        sn.getMacAddress(), sn.getIpAddresses(), sn.getSpeedMbps(), sn.getInterfaceType()
                ));
            }
        } else {
            networks = existing.networks();
        }

        // Update GPUs with static info
        List<GpuInfo> gpus = new ArrayList<>();
        if (staticInfo.getGpus() != null) {
            for (var sg : staticInfo.getGpus()) {
                GpuInfo existingGpu = existing.gpus().stream()
                        .filter(g -> g.index() == sg.getIndex())
                        .findFirst().orElse(null);

                gpus.add(new GpuInfo(
                        sg.getIndex(), sg.getName(), sg.getVendor(),
                        existingGpu != null ? existingGpu.usagePercent() : 0,
                        sg.getMemoryTotal(),
                        existingGpu != null ? existingGpu.memoryUsed() : 0,
                        existingGpu != null ? existingGpu.temperature() : 0,
                        existingGpu != null ? existingGpu.fanSpeedPercent() : 0,
                        existingGpu != null ? existingGpu.powerWatts() : 0,
                        sg.getPowerLimitWatts(),
                        existingGpu != null ? existingGpu.clockCoreMhz() : 0,
                        existingGpu != null ? existingGpu.clockMemoryMhz() : 0,
                        sg.getDriverVersion(), sg.getPcieGeneration(),
                        existingGpu != null ? existingGpu.encoderUsage() : 0,
                        existingGpu != null ? existingGpu.decoderUsage() : 0
                ));
            }
        } else {
            gpus = existing.gpus();
        }

        // Update NPUs with static info
        List<NpuInfo> npus = new ArrayList<>();
        if (staticInfo.getNpus() != null) {
            for (var sn : staticInfo.getNpus()) {
                NpuInfo existingNpu = existing.npus().stream()
                        .filter(n -> n.index() == sn.getIndex())
                        .findFirst().orElse(null);

                npus.add(new NpuInfo(
                        sn.getIndex(), sn.getName(), sn.getVendor(),
                        existingNpu != null ? existingNpu.usagePercent() : 0,
                        sn.getMemoryTotal(),
                        existingNpu != null ? existingNpu.memoryUsed() : 0,
                        existingNpu != null ? existingNpu.temperature() : 0,
                        existingNpu != null ? existingNpu.powerWatts() : 0,
                        sn.getDriverVersion()
                ));
            }
        } else {
            npus = existing.npus();
        }

        // System info
        SystemInfo sysInfo = null;
        if (staticInfo.getSystemInfo() != null) {
            var si = staticInfo.getSystemInfo();
            sysInfo = new SystemInfo(
                    si.getOsName(), si.getOsVersion(), si.getKernelVersion(),
                    si.getHostname(), si.getBootTime(), si.getUptimeSeconds(),
                    si.getMotherboardModel(), si.getMotherboardVendor(),
                    si.getBiosVersion(), si.getSystemModel(), si.getSystemVendor()
            );
        } else {
            sysInfo = existing.systemInfo();
        }

        return new AgentMetrics(
                staticInfo.getHostname() != null ? staticInfo.getHostname() : existing.hostname(),
                existing.timestamp(),
                cpuInfo, memoryInfo, disks, networks,
                existing.loadAverage(), sysInfo, gpus, existing.userSessions(), npus
        );
    }

    /**
     * Merge periodic data into existing metrics
     */
    public static AgentMetrics mergePeriodicData(AgentMetrics existing, PeriodicData periodic) {
        // Update disk usage from periodic data
        List<DiskInfo> disks = new ArrayList<>(existing.disks());
        if (periodic.getDiskUsage() != null) {
            for (var du : periodic.getDiskUsage()) {
                boolean found = false;
                for (int i = 0; i < disks.size(); i++) {
                    var old = disks.get(i);
                    if ((old.device() != null && old.device().equals(du.getDevice())) ||
                            (old.mountPoint() != null && old.mountPoint().equals(du.getMountPoint()))) {
                        disks.set(i, new DiskInfo(
                                du.getMountPoint(), du.getDevice(), old.fsType(),
                                du.getTotal(), du.getUsed(), du.getAvailable(),
                                du.getUsagePercent(),
                                old.readBytesPerSec(), old.writeBytesPerSec(),
                                old.model(), old.serial(), old.diskType(),
                                old.readIops(), old.writeIops(),
                                du.getTemperature(), old.healthStatus()
                        ));
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    disks.add(new DiskInfo(
                            du.getMountPoint(), du.getDevice(), null,
                            du.getTotal(), du.getUsed(), du.getAvailable(),
                            du.getUsagePercent(), 0, 0, null, null, null, 0, 0,
                            du.getTemperature(), null
                    ));
                }
            }
        }

        // Update network address updates
        List<NetworkInfo> networks = new ArrayList<>(existing.networks());
        if (periodic.getNetworkUpdates() != null) {
            for (var nu : periodic.getNetworkUpdates()) {
                boolean found = false;
                for (int i = 0; i < networks.size(); i++) {
                    if (networks.get(i).interfaceName() != null && networks.get(i).interfaceName().equals(nu.getInterfaceName())) {
                        var old = networks.get(i);
                        networks.set(i, new NetworkInfo(
                                old.interfaceName(), nu.isUp(),
                                old.rxBytesPerSec(), old.txBytesPerSec(),
                                old.rxPacketsPerSec(), old.txPacketsPerSec(),
                                old.macAddress(), nu.getIpAddresses(), old.speedMbps(), old.interfaceType()
                        ));
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    networks.add(new NetworkInfo(nu.getInterfaceName(), nu.isUp(), 0, 0, 0, 0, null,
                            nu.getIpAddresses(), 0, null));
                }
            }
        }

        // Update user sessions
        List<UserSessionInfo> sessions = new ArrayList<>();
        if (periodic.getUserSessions() != null) {
            for (var s : periodic.getUserSessions()) {
                sessions.add(new UserSessionInfo(
                        s.getUsername(), s.getTty(), s.getLoginTime(),
                        s.getRemoteHost(), s.getIdleSeconds(), s.getSessionType()
                ));
            }
        } else {
            sessions = existing.userSessions();
        }

        return new AgentMetrics(
                existing.hostname(),
                Instant.ofEpochMilli(periodic.getTimestamp()),
                existing.cpu(), existing.memory(), disks, networks,
                existing.loadAverage(), existing.systemInfo(), existing.gpus(), sessions, existing.npus()
        );
    }

    // Convenience methods for compatibility
    public double cpuUsage() {
        return cpu != null ? cpu.usagePercent() : 0;
    }

    public double memoryUsage() {
        return memory != null ? memory.usagePercent() : 0;
    }
}
