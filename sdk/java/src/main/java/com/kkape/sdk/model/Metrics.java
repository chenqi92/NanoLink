package com.kkape.sdk.model;

import java.util.List;

/**
 * System metrics data from an agent.
 * Contains comprehensive system information including CPU, memory, disk, network, GPU, and system info.
 */
public class Metrics {
    private long timestamp;
    private String hostname;
    private CpuMetrics cpu;
    private MemoryMetrics memory;
    private List<DiskMetrics> disks;
    private List<NetworkMetrics> networks;
    private double[] loadAverage;
    private List<GpuMetrics> gpus;
    private SystemInfo systemInfo;
    private List<UserSession> userSessions;
    private List<NpuMetrics> npus;

    // CPU metrics with extended information
    public static class CpuMetrics {
        private double usagePercent;
        private int coreCount;
        private double[] perCoreUsage;
        private String model;
        private String vendor;
        private long frequencyMhz;
        private long frequencyMaxMhz;
        private int physicalCores;
        private int logicalCores;
        private String architecture;
        private double temperature;

        public double getUsagePercent() { return usagePercent; }
        public void setUsagePercent(double usagePercent) { this.usagePercent = usagePercent; }
        public int getCoreCount() { return coreCount; }
        public void setCoreCount(int coreCount) { this.coreCount = coreCount; }
        public double[] getPerCoreUsage() { return perCoreUsage; }
        public void setPerCoreUsage(double[] perCoreUsage) { this.perCoreUsage = perCoreUsage; }
        public String getModel() { return model; }
        public void setModel(String model) { this.model = model; }
        public String getVendor() { return vendor; }
        public void setVendor(String vendor) { this.vendor = vendor; }
        public long getFrequencyMhz() { return frequencyMhz; }
        public void setFrequencyMhz(long frequencyMhz) { this.frequencyMhz = frequencyMhz; }
        public long getFrequencyMaxMhz() { return frequencyMaxMhz; }
        public void setFrequencyMaxMhz(long frequencyMaxMhz) { this.frequencyMaxMhz = frequencyMaxMhz; }
        public int getPhysicalCores() { return physicalCores; }
        public void setPhysicalCores(int physicalCores) { this.physicalCores = physicalCores; }
        public int getLogicalCores() { return logicalCores; }
        public void setLogicalCores(int logicalCores) { this.logicalCores = logicalCores; }
        public String getArchitecture() { return architecture; }
        public void setArchitecture(String architecture) { this.architecture = architecture; }
        public double getTemperature() { return temperature; }
        public void setTemperature(double temperature) { this.temperature = temperature; }
    }

    // Memory metrics with extended information
    public static class MemoryMetrics {
        private long total;
        private long used;
        private long available;
        private long swapTotal;
        private long swapUsed;
        private long cached;
        private long buffers;
        private String memoryType;
        private int memorySpeedMhz;

        public long getTotal() { return total; }
        public void setTotal(long total) { this.total = total; }
        public long getUsed() { return used; }
        public void setUsed(long used) { this.used = used; }
        public long getAvailable() { return available; }
        public void setAvailable(long available) { this.available = available; }
        public long getSwapTotal() { return swapTotal; }
        public void setSwapTotal(long swapTotal) { this.swapTotal = swapTotal; }
        public long getSwapUsed() { return swapUsed; }
        public void setSwapUsed(long swapUsed) { this.swapUsed = swapUsed; }
        public long getCached() { return cached; }
        public void setCached(long cached) { this.cached = cached; }
        public long getBuffers() { return buffers; }
        public void setBuffers(long buffers) { this.buffers = buffers; }
        public String getMemoryType() { return memoryType; }
        public void setMemoryType(String memoryType) { this.memoryType = memoryType; }
        public int getMemorySpeedMhz() { return memorySpeedMhz; }
        public void setMemorySpeedMhz(int memorySpeedMhz) { this.memorySpeedMhz = memorySpeedMhz; }
        public double getUsagePercent() { return total > 0 ? (double) used / total * 100 : 0; }
    }

    // Disk metrics with extended information
    public static class DiskMetrics {
        private String mountPoint;
        private String device;
        private String fsType;
        private long total;
        private long used;
        private long available;
        private long readBytesPerSec;
        private long writeBytesPerSec;
        private String model;
        private String serial;
        private String diskType;  // SSD, HDD, NVMe
        private long readIops;
        private long writeIops;
        private double temperature;
        private String healthStatus;

        public String getMountPoint() { return mountPoint; }
        public void setMountPoint(String mountPoint) { this.mountPoint = mountPoint; }
        public String getDevice() { return device; }
        public void setDevice(String device) { this.device = device; }
        public String getFsType() { return fsType; }
        public void setFsType(String fsType) { this.fsType = fsType; }
        public long getTotal() { return total; }
        public void setTotal(long total) { this.total = total; }
        public long getUsed() { return used; }
        public void setUsed(long used) { this.used = used; }
        public long getAvailable() { return available; }
        public void setAvailable(long available) { this.available = available; }
        public long getReadBytesPerSec() { return readBytesPerSec; }
        public void setReadBytesPerSec(long readBytesPerSec) { this.readBytesPerSec = readBytesPerSec; }
        public long getWriteBytesPerSec() { return writeBytesPerSec; }
        public void setWriteBytesPerSec(long writeBytesPerSec) { this.writeBytesPerSec = writeBytesPerSec; }
        public String getModel() { return model; }
        public void setModel(String model) { this.model = model; }
        public String getSerial() { return serial; }
        public void setSerial(String serial) { this.serial = serial; }
        public String getDiskType() { return diskType; }
        public void setDiskType(String diskType) { this.diskType = diskType; }
        public long getReadIops() { return readIops; }
        public void setReadIops(long readIops) { this.readIops = readIops; }
        public long getWriteIops() { return writeIops; }
        public void setWriteIops(long writeIops) { this.writeIops = writeIops; }
        public double getTemperature() { return temperature; }
        public void setTemperature(double temperature) { this.temperature = temperature; }
        public String getHealthStatus() { return healthStatus; }
        public void setHealthStatus(String healthStatus) { this.healthStatus = healthStatus; }
        public double getUsagePercent() { return total > 0 ? (double) used / total * 100 : 0; }
    }

    // Network metrics with extended information
    public static class NetworkMetrics {
        private String interfaceName;
        private long rxBytesPerSec;
        private long txBytesPerSec;
        private long rxPacketsPerSec;
        private long txPacketsPerSec;
        private boolean isUp;
        private String macAddress;
        private List<String> ipAddresses;
        private long speedMbps;
        private String interfaceType;

        public String getInterfaceName() { return interfaceName; }
        public void setInterfaceName(String interfaceName) { this.interfaceName = interfaceName; }
        public long getRxBytesPerSec() { return rxBytesPerSec; }
        public void setRxBytesPerSec(long rxBytesPerSec) { this.rxBytesPerSec = rxBytesPerSec; }
        public long getTxBytesPerSec() { return txBytesPerSec; }
        public void setTxBytesPerSec(long txBytesPerSec) { this.txBytesPerSec = txBytesPerSec; }
        public long getRxPacketsPerSec() { return rxPacketsPerSec; }
        public void setRxPacketsPerSec(long rxPacketsPerSec) { this.rxPacketsPerSec = rxPacketsPerSec; }
        public long getTxPacketsPerSec() { return txPacketsPerSec; }
        public void setTxPacketsPerSec(long txPacketsPerSec) { this.txPacketsPerSec = txPacketsPerSec; }
        public boolean isUp() { return isUp; }
        public void setUp(boolean up) { isUp = up; }
        public String getMacAddress() { return macAddress; }
        public void setMacAddress(String macAddress) { this.macAddress = macAddress; }
        public List<String> getIpAddresses() { return ipAddresses; }
        public void setIpAddresses(List<String> ipAddresses) { this.ipAddresses = ipAddresses; }
        public long getSpeedMbps() { return speedMbps; }
        public void setSpeedMbps(long speedMbps) { this.speedMbps = speedMbps; }
        public String getInterfaceType() { return interfaceType; }
        public void setInterfaceType(String interfaceType) { this.interfaceType = interfaceType; }
    }

    // GPU metrics
    public static class GpuMetrics {
        private int index;
        private String name;
        private String vendor;
        private double usagePercent;
        private long memoryTotal;
        private long memoryUsed;
        private double temperature;
        private int fanSpeedPercent;
        private int powerWatts;
        private int powerLimitWatts;
        private long clockCoreMhz;
        private long clockMemoryMhz;
        private String driverVersion;
        private String pcieGeneration;
        private double encoderUsage;
        private double decoderUsage;

        public int getIndex() { return index; }
        public void setIndex(int index) { this.index = index; }
        public String getName() { return name; }
        public void setName(String name) { this.name = name; }
        public String getVendor() { return vendor; }
        public void setVendor(String vendor) { this.vendor = vendor; }
        public double getUsagePercent() { return usagePercent; }
        public void setUsagePercent(double usagePercent) { this.usagePercent = usagePercent; }
        public long getMemoryTotal() { return memoryTotal; }
        public void setMemoryTotal(long memoryTotal) { this.memoryTotal = memoryTotal; }
        public long getMemoryUsed() { return memoryUsed; }
        public void setMemoryUsed(long memoryUsed) { this.memoryUsed = memoryUsed; }
        public double getTemperature() { return temperature; }
        public void setTemperature(double temperature) { this.temperature = temperature; }
        public int getFanSpeedPercent() { return fanSpeedPercent; }
        public void setFanSpeedPercent(int fanSpeedPercent) { this.fanSpeedPercent = fanSpeedPercent; }
        public int getPowerWatts() { return powerWatts; }
        public void setPowerWatts(int powerWatts) { this.powerWatts = powerWatts; }
        public int getPowerLimitWatts() { return powerLimitWatts; }
        public void setPowerLimitWatts(int powerLimitWatts) { this.powerLimitWatts = powerLimitWatts; }
        public long getClockCoreMhz() { return clockCoreMhz; }
        public void setClockCoreMhz(long clockCoreMhz) { this.clockCoreMhz = clockCoreMhz; }
        public long getClockMemoryMhz() { return clockMemoryMhz; }
        public void setClockMemoryMhz(long clockMemoryMhz) { this.clockMemoryMhz = clockMemoryMhz; }
        public String getDriverVersion() { return driverVersion; }
        public void setDriverVersion(String driverVersion) { this.driverVersion = driverVersion; }
        public String getPcieGeneration() { return pcieGeneration; }
        public void setPcieGeneration(String pcieGeneration) { this.pcieGeneration = pcieGeneration; }
        public double getEncoderUsage() { return encoderUsage; }
        public void setEncoderUsage(double encoderUsage) { this.encoderUsage = encoderUsage; }
        public double getDecoderUsage() { return decoderUsage; }
        public void setDecoderUsage(double decoderUsage) { this.decoderUsage = decoderUsage; }
        public double getMemoryUsagePercent() { return memoryTotal > 0 ? (double) memoryUsed / memoryTotal * 100 : 0; }
    }

    // System information
    public static class SystemInfo {
        private String osName;
        private String osVersion;
        private String kernelVersion;
        private String hostname;
        private long bootTime;
        private long uptimeSeconds;
        private String motherboardModel;
        private String motherboardVendor;
        private String biosVersion;
        private String systemModel;
        private String systemVendor;

        public String getOsName() { return osName; }
        public void setOsName(String osName) { this.osName = osName; }
        public String getOsVersion() { return osVersion; }
        public void setOsVersion(String osVersion) { this.osVersion = osVersion; }
        public String getKernelVersion() { return kernelVersion; }
        public void setKernelVersion(String kernelVersion) { this.kernelVersion = kernelVersion; }
        public String getHostname() { return hostname; }
        public void setHostname(String hostname) { this.hostname = hostname; }
        public long getBootTime() { return bootTime; }
        public void setBootTime(long bootTime) { this.bootTime = bootTime; }
        public long getUptimeSeconds() { return uptimeSeconds; }
        public void setUptimeSeconds(long uptimeSeconds) { this.uptimeSeconds = uptimeSeconds; }
        public String getMotherboardModel() { return motherboardModel; }
        public void setMotherboardModel(String motherboardModel) { this.motherboardModel = motherboardModel; }
        public String getMotherboardVendor() { return motherboardVendor; }
        public void setMotherboardVendor(String motherboardVendor) { this.motherboardVendor = motherboardVendor; }
        public String getBiosVersion() { return biosVersion; }
        public void setBiosVersion(String biosVersion) { this.biosVersion = biosVersion; }
        public String getSystemModel() { return systemModel; }
        public void setSystemModel(String systemModel) { this.systemModel = systemModel; }
        public String getSystemVendor() { return systemVendor; }
        public void setSystemVendor(String systemVendor) { this.systemVendor = systemVendor; }
    }

    // User session information
    public static class UserSession {
        private String username;
        private String tty;
        private long loginTime;
        private String remoteHost;
        private long idleSeconds;
        private String sessionType;

        public String getUsername() { return username; }
        public void setUsername(String username) { this.username = username; }
        public String getTty() { return tty; }
        public void setTty(String tty) { this.tty = tty; }
        public long getLoginTime() { return loginTime; }
        public void setLoginTime(long loginTime) { this.loginTime = loginTime; }
        public String getRemoteHost() { return remoteHost; }
        public void setRemoteHost(String remoteHost) { this.remoteHost = remoteHost; }
        public long getIdleSeconds() { return idleSeconds; }
        public void setIdleSeconds(long idleSeconds) { this.idleSeconds = idleSeconds; }
        public String getSessionType() { return sessionType; }
        public void setSessionType(String sessionType) { this.sessionType = sessionType; }
    }

    // NPU/AI accelerator metrics
    public static class NpuMetrics {
        private int index;
        private String name;
        private String vendor;
        private double usagePercent;
        private long memoryTotal;
        private long memoryUsed;
        private double temperature;
        private int powerWatts;
        private String driverVersion;

        public int getIndex() { return index; }
        public void setIndex(int index) { this.index = index; }
        public String getName() { return name; }
        public void setName(String name) { this.name = name; }
        public String getVendor() { return vendor; }
        public void setVendor(String vendor) { this.vendor = vendor; }
        public double getUsagePercent() { return usagePercent; }
        public void setUsagePercent(double usagePercent) { this.usagePercent = usagePercent; }
        public long getMemoryTotal() { return memoryTotal; }
        public void setMemoryTotal(long memoryTotal) { this.memoryTotal = memoryTotal; }
        public long getMemoryUsed() { return memoryUsed; }
        public void setMemoryUsed(long memoryUsed) { this.memoryUsed = memoryUsed; }
        public double getTemperature() { return temperature; }
        public void setTemperature(double temperature) { this.temperature = temperature; }
        public int getPowerWatts() { return powerWatts; }
        public void setPowerWatts(int powerWatts) { this.powerWatts = powerWatts; }
        public String getDriverVersion() { return driverVersion; }
        public void setDriverVersion(String driverVersion) { this.driverVersion = driverVersion; }
    }

    // Main class getters and setters
    public long getTimestamp() { return timestamp; }
    public void setTimestamp(long timestamp) { this.timestamp = timestamp; }
    public String getHostname() { return hostname; }
    public void setHostname(String hostname) { this.hostname = hostname; }
    public CpuMetrics getCpu() { return cpu; }
    public void setCpu(CpuMetrics cpu) { this.cpu = cpu; }
    public MemoryMetrics getMemory() { return memory; }
    public void setMemory(MemoryMetrics memory) { this.memory = memory; }
    public List<DiskMetrics> getDisks() { return disks; }
    public void setDisks(List<DiskMetrics> disks) { this.disks = disks; }
    public List<NetworkMetrics> getNetworks() { return networks; }
    public void setNetworks(List<NetworkMetrics> networks) { this.networks = networks; }
    public double[] getLoadAverage() { return loadAverage; }
    public void setLoadAverage(double[] loadAverage) { this.loadAverage = loadAverage; }
    public List<GpuMetrics> getGpus() { return gpus; }
    public void setGpus(List<GpuMetrics> gpus) { this.gpus = gpus; }
    public SystemInfo getSystemInfo() { return systemInfo; }
    public void setSystemInfo(SystemInfo systemInfo) { this.systemInfo = systemInfo; }
    public List<UserSession> getUserSessions() { return userSessions; }
    public void setUserSessions(List<UserSession> userSessions) { this.userSessions = userSessions; }
    public List<NpuMetrics> getNpus() { return npus; }
    public void setNpus(List<NpuMetrics> npus) { this.npus = npus; }
}
