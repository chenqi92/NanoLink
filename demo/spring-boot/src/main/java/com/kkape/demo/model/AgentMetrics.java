package com.kkape.demo.model;

import com.kkape.sdk.model.Metrics;

import java.time.Instant;
import java.util.List;

/**
 * Simplified metrics from an agent
 */
public record AgentMetrics(
        String hostname,
        Instant timestamp,
        double cpuUsage,
        int cpuCores,
        double memoryUsage,
        long memoryTotal,
        long memoryUsed,
        List<DiskInfo> disks,
        List<NetworkInfo> networks,
        double[] loadAverage
) {

    /**
     * Create AgentMetrics from SDK Metrics
     */
    public static AgentMetrics from(Metrics metrics) {
        var cpu = metrics.getCpu();
        var memory = metrics.getMemory();

        List<DiskInfo> disks = List.of();
        if (metrics.getDisks() != null) {
            disks = metrics.getDisks().stream()
                    .map(d -> new DiskInfo(
                            d.getMountPoint(),
                            d.getDevice(),
                            d.getTotal(),
                            d.getUsed(),
                            d.getUsagePercent(),
                            d.getReadBytesPerSec(),
                            d.getWriteBytesPerSec()
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
                            n.getTxBytesPerSec()
                    ))
                    .toList();
        }

        return new AgentMetrics(
                metrics.getHostname(),
                Instant.ofEpochMilli(metrics.getTimestamp()),
                cpu != null ? cpu.getUsagePercent() : 0.0,
                cpu != null ? cpu.getCoreCount() : 0,
                memory != null ? memory.getUsagePercent() : 0.0,
                memory != null ? memory.getTotal() : 0,
                memory != null ? memory.getUsed() : 0,
                disks,
                networks,
                metrics.getLoadAverage()
        );
    }

    /**
     * Disk information
     */
    public record DiskInfo(
            String mountPoint,
            String device,
            long total,
            long used,
            double usagePercent,
            long readBytesPerSec,
            long writeBytesPerSec
    ) {
    }

    /**
     * Network interface information
     */
    public record NetworkInfo(
            String interfaceName,
            boolean isUp,
            long rxBytesPerSec,
            long txBytesPerSec
    ) {
    }
}
