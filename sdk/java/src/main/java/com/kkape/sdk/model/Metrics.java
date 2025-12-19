package com.kkape.sdk.model;

import java.util.List;

/**
 * System metrics data from an agent
 */
public class Metrics {
    private long timestamp;
    private String hostname;
    private CpuMetrics cpu;
    private MemoryMetrics memory;
    private List<DiskMetrics> disks;
    private List<NetworkMetrics> networks;
    private double[] loadAverage;

    // CPU metrics
    public static class CpuMetrics {
        private double usagePercent;
        private int coreCount;
        private double[] perCoreUsage;

        public double getUsagePercent() {
            return usagePercent;
        }

        public void setUsagePercent(double usagePercent) {
            this.usagePercent = usagePercent;
        }

        public int getCoreCount() {
            return coreCount;
        }

        public void setCoreCount(int coreCount) {
            this.coreCount = coreCount;
        }

        public double[] getPerCoreUsage() {
            return perCoreUsage;
        }

        public void setPerCoreUsage(double[] perCoreUsage) {
            this.perCoreUsage = perCoreUsage;
        }
    }

    // Memory metrics
    public static class MemoryMetrics {
        private long total;
        private long used;
        private long available;
        private long swapTotal;
        private long swapUsed;

        public long getTotal() {
            return total;
        }

        public void setTotal(long total) {
            this.total = total;
        }

        public long getUsed() {
            return used;
        }

        public void setUsed(long used) {
            this.used = used;
        }

        public long getAvailable() {
            return available;
        }

        public void setAvailable(long available) {
            this.available = available;
        }

        public long getSwapTotal() {
            return swapTotal;
        }

        public void setSwapTotal(long swapTotal) {
            this.swapTotal = swapTotal;
        }

        public long getSwapUsed() {
            return swapUsed;
        }

        public void setSwapUsed(long swapUsed) {
            this.swapUsed = swapUsed;
        }

        public double getUsagePercent() {
            return total > 0 ? (double) used / total * 100 : 0;
        }
    }

    // Disk metrics
    public static class DiskMetrics {
        private String mountPoint;
        private String device;
        private String fsType;
        private long total;
        private long used;
        private long available;
        private long readBytesPerSec;
        private long writeBytesPerSec;

        public String getMountPoint() {
            return mountPoint;
        }

        public void setMountPoint(String mountPoint) {
            this.mountPoint = mountPoint;
        }

        public String getDevice() {
            return device;
        }

        public void setDevice(String device) {
            this.device = device;
        }

        public String getFsType() {
            return fsType;
        }

        public void setFsType(String fsType) {
            this.fsType = fsType;
        }

        public long getTotal() {
            return total;
        }

        public void setTotal(long total) {
            this.total = total;
        }

        public long getUsed() {
            return used;
        }

        public void setUsed(long used) {
            this.used = used;
        }

        public long getAvailable() {
            return available;
        }

        public void setAvailable(long available) {
            this.available = available;
        }

        public long getReadBytesPerSec() {
            return readBytesPerSec;
        }

        public void setReadBytesPerSec(long readBytesPerSec) {
            this.readBytesPerSec = readBytesPerSec;
        }

        public long getWriteBytesPerSec() {
            return writeBytesPerSec;
        }

        public void setWriteBytesPerSec(long writeBytesPerSec) {
            this.writeBytesPerSec = writeBytesPerSec;
        }

        public double getUsagePercent() {
            return total > 0 ? (double) used / total * 100 : 0;
        }
    }

    // Network metrics
    public static class NetworkMetrics {
        private String interfaceName;
        private long rxBytesPerSec;
        private long txBytesPerSec;
        private long rxPacketsPerSec;
        private long txPacketsPerSec;
        private boolean isUp;

        public String getInterfaceName() {
            return interfaceName;
        }

        public void setInterfaceName(String interfaceName) {
            this.interfaceName = interfaceName;
        }

        public long getRxBytesPerSec() {
            return rxBytesPerSec;
        }

        public void setRxBytesPerSec(long rxBytesPerSec) {
            this.rxBytesPerSec = rxBytesPerSec;
        }

        public long getTxBytesPerSec() {
            return txBytesPerSec;
        }

        public void setTxBytesPerSec(long txBytesPerSec) {
            this.txBytesPerSec = txBytesPerSec;
        }

        public long getRxPacketsPerSec() {
            return rxPacketsPerSec;
        }

        public void setRxPacketsPerSec(long rxPacketsPerSec) {
            this.rxPacketsPerSec = rxPacketsPerSec;
        }

        public long getTxPacketsPerSec() {
            return txPacketsPerSec;
        }

        public void setTxPacketsPerSec(long txPacketsPerSec) {
            this.txPacketsPerSec = txPacketsPerSec;
        }

        public boolean isUp() {
            return isUp;
        }

        public void setUp(boolean up) {
            isUp = up;
        }
    }

    // Getters and setters

    public long getTimestamp() {
        return timestamp;
    }

    public void setTimestamp(long timestamp) {
        this.timestamp = timestamp;
    }

    public String getHostname() {
        return hostname;
    }

    public void setHostname(String hostname) {
        this.hostname = hostname;
    }

    public CpuMetrics getCpu() {
        return cpu;
    }

    public void setCpu(CpuMetrics cpu) {
        this.cpu = cpu;
    }

    public MemoryMetrics getMemory() {
        return memory;
    }

    public void setMemory(MemoryMetrics memory) {
        this.memory = memory;
    }

    public List<DiskMetrics> getDisks() {
        return disks;
    }

    public void setDisks(List<DiskMetrics> disks) {
        this.disks = disks;
    }

    public List<NetworkMetrics> getNetworks() {
        return networks;
    }

    public void setNetworks(List<NetworkMetrics> networks) {
        this.networks = networks;
    }

    public double[] getLoadAverage() {
        return loadAverage;
    }

    public void setLoadAverage(double[] loadAverage) {
        this.loadAverage = loadAverage;
    }
}
