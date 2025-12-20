package com.kkape.sdk.model;

import java.util.List;

/**
 * Periodic data sent at longer intervals (30s-5min).
 * Contains data that changes occasionally but doesn't need realtime updates.
 */
public class PeriodicData {
    private long timestamp;
    private String hostname;
    private List<DiskUsage> diskUsage;
    private List<Metrics.UserSession> userSessions;
    private List<NetworkAddressUpdate> networkUpdates;

    // Disk usage data
    public static class DiskUsage {
        private String device;
        private String mountPoint;
        private long total;
        private long used;
        private long available;
        private double temperature;

        public String getDevice() { return device; }
        public void setDevice(String device) { this.device = device; }
        public String getMountPoint() { return mountPoint; }
        public void setMountPoint(String mountPoint) { this.mountPoint = mountPoint; }
        public long getTotal() { return total; }
        public void setTotal(long total) { this.total = total; }
        public long getUsed() { return used; }
        public void setUsed(long used) { this.used = used; }
        public long getAvailable() { return available; }
        public void setAvailable(long available) { this.available = available; }
        public double getTemperature() { return temperature; }
        public void setTemperature(double temperature) { this.temperature = temperature; }
        public double getUsagePercent() { return total > 0 ? (double) used / total * 100 : 0; }
    }

    // Network address update
    public static class NetworkAddressUpdate {
        private String interfaceName;
        private List<String> ipAddresses;
        private boolean up;

        public String getInterfaceName() { return interfaceName; }
        public void setInterfaceName(String interfaceName) { this.interfaceName = interfaceName; }
        public List<String> getIpAddresses() { return ipAddresses; }
        public void setIpAddresses(List<String> ipAddresses) { this.ipAddresses = ipAddresses; }
        public boolean isUp() { return up; }
        public void setUp(boolean up) { this.up = up; }
    }

    // Getters and setters
    public long getTimestamp() { return timestamp; }
    public void setTimestamp(long timestamp) { this.timestamp = timestamp; }
    public String getHostname() { return hostname; }
    public void setHostname(String hostname) { this.hostname = hostname; }
    public List<DiskUsage> getDiskUsage() { return diskUsage; }
    public void setDiskUsage(List<DiskUsage> diskUsage) { this.diskUsage = diskUsage; }
    public List<Metrics.UserSession> getUserSessions() { return userSessions; }
    public void setUserSessions(List<Metrics.UserSession> userSessions) { this.userSessions = userSessions; }
    public List<NetworkAddressUpdate> getNetworkUpdates() { return networkUpdates; }
    public void setNetworkUpdates(List<NetworkAddressUpdate> networkUpdates) { this.networkUpdates = networkUpdates; }
}
