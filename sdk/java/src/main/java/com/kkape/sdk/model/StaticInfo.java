package com.kkape.sdk.model;

import java.util.List;

/**
 * Static hardware information sent once on connection or on request.
 * Contains information that rarely or never changes.
 */
public class StaticInfo {
    private long timestamp;
    private String hostname;
    private CpuStaticInfo cpu;
    private MemoryStaticInfo memory;
    private List<DiskStaticInfo> disks;
    private List<NetworkStaticInfo> networks;
    private List<GpuStaticInfo> gpus;
    private List<NpuStaticInfo> npus;
    private Metrics.SystemInfo systemInfo;

    // CPU static information
    public static class CpuStaticInfo {
        private String model;
        private String vendor;
        private int physicalCores;
        private int logicalCores;
        private String architecture;
        private long frequencyMaxMhz;
        private long l1CacheKb;
        private long l2CacheKb;
        private long l3CacheKb;

        public String getModel() { return model; }
        public void setModel(String model) { this.model = model; }
        public String getVendor() { return vendor; }
        public void setVendor(String vendor) { this.vendor = vendor; }
        public int getPhysicalCores() { return physicalCores; }
        public void setPhysicalCores(int physicalCores) { this.physicalCores = physicalCores; }
        public int getLogicalCores() { return logicalCores; }
        public void setLogicalCores(int logicalCores) { this.logicalCores = logicalCores; }
        public String getArchitecture() { return architecture; }
        public void setArchitecture(String architecture) { this.architecture = architecture; }
        public long getFrequencyMaxMhz() { return frequencyMaxMhz; }
        public void setFrequencyMaxMhz(long frequencyMaxMhz) { this.frequencyMaxMhz = frequencyMaxMhz; }
        public long getL1CacheKb() { return l1CacheKb; }
        public void setL1CacheKb(long l1CacheKb) { this.l1CacheKb = l1CacheKb; }
        public long getL2CacheKb() { return l2CacheKb; }
        public void setL2CacheKb(long l2CacheKb) { this.l2CacheKb = l2CacheKb; }
        public long getL3CacheKb() { return l3CacheKb; }
        public void setL3CacheKb(long l3CacheKb) { this.l3CacheKb = l3CacheKb; }
    }

    // Memory static information
    public static class MemoryStaticInfo {
        private long total;
        private long swapTotal;
        private String memoryType;
        private int memorySpeedMhz;
        private int memorySlots;

        public long getTotal() { return total; }
        public void setTotal(long total) { this.total = total; }
        public long getSwapTotal() { return swapTotal; }
        public void setSwapTotal(long swapTotal) { this.swapTotal = swapTotal; }
        public String getMemoryType() { return memoryType; }
        public void setMemoryType(String memoryType) { this.memoryType = memoryType; }
        public int getMemorySpeedMhz() { return memorySpeedMhz; }
        public void setMemorySpeedMhz(int memorySpeedMhz) { this.memorySpeedMhz = memorySpeedMhz; }
        public int getMemorySlots() { return memorySlots; }
        public void setMemorySlots(int memorySlots) { this.memorySlots = memorySlots; }
    }

    // Disk static information
    public static class DiskStaticInfo {
        private String device;
        private String mountPoint;
        private String fsType;
        private String model;
        private String serial;
        private String diskType;
        private long totalBytes;
        private String healthStatus;

        public String getDevice() { return device; }
        public void setDevice(String device) { this.device = device; }
        public String getMountPoint() { return mountPoint; }
        public void setMountPoint(String mountPoint) { this.mountPoint = mountPoint; }
        public String getFsType() { return fsType; }
        public void setFsType(String fsType) { this.fsType = fsType; }
        public String getModel() { return model; }
        public void setModel(String model) { this.model = model; }
        public String getSerial() { return serial; }
        public void setSerial(String serial) { this.serial = serial; }
        public String getDiskType() { return diskType; }
        public void setDiskType(String diskType) { this.diskType = diskType; }
        public long getTotalBytes() { return totalBytes; }
        public void setTotalBytes(long totalBytes) { this.totalBytes = totalBytes; }
        public String getHealthStatus() { return healthStatus; }
        public void setHealthStatus(String healthStatus) { this.healthStatus = healthStatus; }
    }

    // Network static information
    public static class NetworkStaticInfo {
        private String interfaceName;
        private String macAddress;
        private List<String> ipAddresses;
        private long speedMbps;
        private String interfaceType;
        private boolean virtual;

        public String getInterfaceName() { return interfaceName; }
        public void setInterfaceName(String interfaceName) { this.interfaceName = interfaceName; }
        public String getMacAddress() { return macAddress; }
        public void setMacAddress(String macAddress) { this.macAddress = macAddress; }
        public List<String> getIpAddresses() { return ipAddresses; }
        public void setIpAddresses(List<String> ipAddresses) { this.ipAddresses = ipAddresses; }
        public long getSpeedMbps() { return speedMbps; }
        public void setSpeedMbps(long speedMbps) { this.speedMbps = speedMbps; }
        public String getInterfaceType() { return interfaceType; }
        public void setInterfaceType(String interfaceType) { this.interfaceType = interfaceType; }
        public boolean isVirtual() { return virtual; }
        public void setVirtual(boolean virtual) { this.virtual = virtual; }
    }

    // GPU static information
    public static class GpuStaticInfo {
        private int index;
        private String name;
        private String vendor;
        private long memoryTotal;
        private String driverVersion;
        private String pcieGeneration;
        private int powerLimitWatts;

        public int getIndex() { return index; }
        public void setIndex(int index) { this.index = index; }
        public String getName() { return name; }
        public void setName(String name) { this.name = name; }
        public String getVendor() { return vendor; }
        public void setVendor(String vendor) { this.vendor = vendor; }
        public long getMemoryTotal() { return memoryTotal; }
        public void setMemoryTotal(long memoryTotal) { this.memoryTotal = memoryTotal; }
        public String getDriverVersion() { return driverVersion; }
        public void setDriverVersion(String driverVersion) { this.driverVersion = driverVersion; }
        public String getPcieGeneration() { return pcieGeneration; }
        public void setPcieGeneration(String pcieGeneration) { this.pcieGeneration = pcieGeneration; }
        public int getPowerLimitWatts() { return powerLimitWatts; }
        public void setPowerLimitWatts(int powerLimitWatts) { this.powerLimitWatts = powerLimitWatts; }
    }

    // NPU static information
    public static class NpuStaticInfo {
        private int index;
        private String name;
        private String vendor;
        private long memoryTotal;
        private String driverVersion;

        public int getIndex() { return index; }
        public void setIndex(int index) { this.index = index; }
        public String getName() { return name; }
        public void setName(String name) { this.name = name; }
        public String getVendor() { return vendor; }
        public void setVendor(String vendor) { this.vendor = vendor; }
        public long getMemoryTotal() { return memoryTotal; }
        public void setMemoryTotal(long memoryTotal) { this.memoryTotal = memoryTotal; }
        public String getDriverVersion() { return driverVersion; }
        public void setDriverVersion(String driverVersion) { this.driverVersion = driverVersion; }
    }

    // Getters and setters
    public long getTimestamp() { return timestamp; }
    public void setTimestamp(long timestamp) { this.timestamp = timestamp; }
    public String getHostname() { return hostname; }
    public void setHostname(String hostname) { this.hostname = hostname; }
    public CpuStaticInfo getCpu() { return cpu; }
    public void setCpu(CpuStaticInfo cpu) { this.cpu = cpu; }
    public MemoryStaticInfo getMemory() { return memory; }
    public void setMemory(MemoryStaticInfo memory) { this.memory = memory; }
    public List<DiskStaticInfo> getDisks() { return disks; }
    public void setDisks(List<DiskStaticInfo> disks) { this.disks = disks; }
    public List<NetworkStaticInfo> getNetworks() { return networks; }
    public void setNetworks(List<NetworkStaticInfo> networks) { this.networks = networks; }
    public List<GpuStaticInfo> getGpus() { return gpus; }
    public void setGpus(List<GpuStaticInfo> gpus) { this.gpus = gpus; }
    public List<NpuStaticInfo> getNpus() { return npus; }
    public void setNpus(List<NpuStaticInfo> npus) { this.npus = npus; }
    public Metrics.SystemInfo getSystemInfo() { return systemInfo; }
    public void setSystemInfo(Metrics.SystemInfo systemInfo) { this.systemInfo = systemInfo; }
}
