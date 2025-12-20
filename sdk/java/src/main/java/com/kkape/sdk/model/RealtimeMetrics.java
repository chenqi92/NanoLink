package com.kkape.sdk.model;

import java.util.List;

/**
 * Realtime metrics sent every second.
 * Contains lightweight, frequently changing data.
 */
public class RealtimeMetrics {
    private long timestamp;
    private String hostname;
    private double cpuUsagePercent;
    private double[] cpuPerCore;
    private double cpuTemperature;
    private long cpuFrequencyMhz;
    private long memoryUsed;
    private long memoryCached;
    private long swapUsed;
    private List<DiskIO> diskIo;
    private List<NetworkIO> networkIo;
    private double[] loadAverage;
    private List<GpuUsage> gpuUsage;
    private List<NpuUsage> npuUsage;

    // Disk IO metrics
    public static class DiskIO {
        private String device;
        private long readBytesSec;
        private long writeBytesSec;
        private long readIops;
        private long writeIops;

        public String getDevice() { return device; }
        public void setDevice(String device) { this.device = device; }
        public long getReadBytesSec() { return readBytesSec; }
        public void setReadBytesSec(long readBytesSec) { this.readBytesSec = readBytesSec; }
        public long getWriteBytesSec() { return writeBytesSec; }
        public void setWriteBytesSec(long writeBytesSec) { this.writeBytesSec = writeBytesSec; }
        public long getReadIops() { return readIops; }
        public void setReadIops(long readIops) { this.readIops = readIops; }
        public long getWriteIops() { return writeIops; }
        public void setWriteIops(long writeIops) { this.writeIops = writeIops; }
    }

    // Network IO metrics
    public static class NetworkIO {
        private String interfaceName;
        private long rxBytesSec;
        private long txBytesSec;
        private long rxPacketsSec;
        private long txPacketsSec;
        private boolean up;

        public String getInterfaceName() { return interfaceName; }
        public void setInterfaceName(String interfaceName) { this.interfaceName = interfaceName; }
        public long getRxBytesSec() { return rxBytesSec; }
        public void setRxBytesSec(long rxBytesSec) { this.rxBytesSec = rxBytesSec; }
        public long getTxBytesSec() { return txBytesSec; }
        public void setTxBytesSec(long txBytesSec) { this.txBytesSec = txBytesSec; }
        public long getRxPacketsSec() { return rxPacketsSec; }
        public void setRxPacketsSec(long rxPacketsSec) { this.rxPacketsSec = rxPacketsSec; }
        public long getTxPacketsSec() { return txPacketsSec; }
        public void setTxPacketsSec(long txPacketsSec) { this.txPacketsSec = txPacketsSec; }
        public boolean isUp() { return up; }
        public void setUp(boolean up) { this.up = up; }
    }

    // GPU usage metrics
    public static class GpuUsage {
        private int index;
        private double usagePercent;
        private long memoryUsed;
        private double temperature;
        private int powerWatts;
        private long clockCoreMhz;
        private double encoderUsage;
        private double decoderUsage;

        public int getIndex() { return index; }
        public void setIndex(int index) { this.index = index; }
        public double getUsagePercent() { return usagePercent; }
        public void setUsagePercent(double usagePercent) { this.usagePercent = usagePercent; }
        public long getMemoryUsed() { return memoryUsed; }
        public void setMemoryUsed(long memoryUsed) { this.memoryUsed = memoryUsed; }
        public double getTemperature() { return temperature; }
        public void setTemperature(double temperature) { this.temperature = temperature; }
        public int getPowerWatts() { return powerWatts; }
        public void setPowerWatts(int powerWatts) { this.powerWatts = powerWatts; }
        public long getClockCoreMhz() { return clockCoreMhz; }
        public void setClockCoreMhz(long clockCoreMhz) { this.clockCoreMhz = clockCoreMhz; }
        public double getEncoderUsage() { return encoderUsage; }
        public void setEncoderUsage(double encoderUsage) { this.encoderUsage = encoderUsage; }
        public double getDecoderUsage() { return decoderUsage; }
        public void setDecoderUsage(double decoderUsage) { this.decoderUsage = decoderUsage; }
    }

    // NPU usage metrics
    public static class NpuUsage {
        private int index;
        private double usagePercent;
        private long memoryUsed;
        private double temperature;
        private int powerWatts;

        public int getIndex() { return index; }
        public void setIndex(int index) { this.index = index; }
        public double getUsagePercent() { return usagePercent; }
        public void setUsagePercent(double usagePercent) { this.usagePercent = usagePercent; }
        public long getMemoryUsed() { return memoryUsed; }
        public void setMemoryUsed(long memoryUsed) { this.memoryUsed = memoryUsed; }
        public double getTemperature() { return temperature; }
        public void setTemperature(double temperature) { this.temperature = temperature; }
        public int getPowerWatts() { return powerWatts; }
        public void setPowerWatts(int powerWatts) { this.powerWatts = powerWatts; }
    }

    // Getters and setters
    public long getTimestamp() { return timestamp; }
    public void setTimestamp(long timestamp) { this.timestamp = timestamp; }
    public String getHostname() { return hostname; }
    public void setHostname(String hostname) { this.hostname = hostname; }
    public double getCpuUsagePercent() { return cpuUsagePercent; }
    public void setCpuUsagePercent(double cpuUsagePercent) { this.cpuUsagePercent = cpuUsagePercent; }
    public double[] getCpuPerCore() { return cpuPerCore; }
    public void setCpuPerCore(double[] cpuPerCore) { this.cpuPerCore = cpuPerCore; }
    public double getCpuTemperature() { return cpuTemperature; }
    public void setCpuTemperature(double cpuTemperature) { this.cpuTemperature = cpuTemperature; }
    public long getCpuFrequencyMhz() { return cpuFrequencyMhz; }
    public void setCpuFrequencyMhz(long cpuFrequencyMhz) { this.cpuFrequencyMhz = cpuFrequencyMhz; }
    public long getMemoryUsed() { return memoryUsed; }
    public void setMemoryUsed(long memoryUsed) { this.memoryUsed = memoryUsed; }
    public long getMemoryCached() { return memoryCached; }
    public void setMemoryCached(long memoryCached) { this.memoryCached = memoryCached; }
    public long getSwapUsed() { return swapUsed; }
    public void setSwapUsed(long swapUsed) { this.swapUsed = swapUsed; }
    public List<DiskIO> getDiskIo() { return diskIo; }
    public void setDiskIo(List<DiskIO> diskIo) { this.diskIo = diskIo; }
    public List<NetworkIO> getNetworkIo() { return networkIo; }
    public void setNetworkIo(List<NetworkIO> networkIo) { this.networkIo = networkIo; }
    public double[] getLoadAverage() { return loadAverage; }
    public void setLoadAverage(double[] loadAverage) { this.loadAverage = loadAverage; }
    public List<GpuUsage> getGpuUsage() { return gpuUsage; }
    public void setGpuUsage(List<GpuUsage> gpuUsage) { this.gpuUsage = gpuUsage; }
    public List<NpuUsage> getNpuUsage() { return npuUsage; }
    public void setNpuUsage(List<NpuUsage> npuUsage) { this.npuUsage = npuUsage; }
}
