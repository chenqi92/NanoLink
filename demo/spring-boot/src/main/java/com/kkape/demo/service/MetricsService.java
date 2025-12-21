package com.kkape.demo.service;

import com.kkape.sdk.AgentConnection;
import com.kkape.sdk.model.Metrics;
import com.kkape.sdk.model.PeriodicData;
import com.kkape.sdk.model.RealtimeMetrics;
import com.kkape.sdk.model.StaticInfo;
import com.kkape.demo.model.AgentInfo;
import com.kkape.demo.model.AgentMetrics;
import com.kkape.demo.websocket.MetricsWebSocketHandler;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.Collection;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Service for managing agent metrics
 *
 * Stores the latest metrics from each connected agent and provides
 * methods to query and aggregate metrics data.
 */
@Service
public class MetricsService {

    private static final Logger log = LoggerFactory.getLogger(MetricsService.class);

    private final MetricsWebSocketHandler webSocketHandler;

    // Store agent info
    private final Map<String, AgentInfo> agents = new ConcurrentHashMap<>();

    // Store latest metrics per agent
    private final Map<String, AgentMetrics> latestMetrics = new ConcurrentHashMap<>();

    // Store static info per agent (hardware info, rarely changes)
    private final Map<String, StaticInfo> staticInfoMap = new ConcurrentHashMap<>();

    // Store latest periodic data per agent (disk usage, sessions)
    private final Map<String, PeriodicData> periodicDataMap = new ConcurrentHashMap<>();

    public MetricsService(MetricsWebSocketHandler webSocketHandler) {
        this.webSocketHandler = webSocketHandler;
    }

    /**
     * Register a new agent connection
     */
    public void registerAgent(AgentConnection agent) {
        AgentInfo info = new AgentInfo(
                agent.getAgentId(),
                agent.getHostname(),
                agent.getOs(),
                agent.getArch(),
                agent.getAgentVersion(),
                Instant.now());
        agents.put(agent.getAgentId(), info);
        log.debug("Registered agent: {}", info);

        // Broadcast agent connect event
        webSocketHandler.broadcastAgentConnect(info);
    }

    /**
     * Unregister an agent
     */
    public void unregisterAgent(AgentConnection agent) {
        AgentInfo info = agents.remove(agent.getAgentId());
        latestMetrics.remove(agent.getAgentId());
        log.debug("Unregistered agent: {}", agent.getHostname());

        // Broadcast agent disconnect event
        if (info != null) {
            webSocketHandler.broadcastAgentDisconnect(info);
        }
    }

    /**
     * Process incoming metrics from an agent
     */
    public void processMetrics(Metrics metrics) {
        String hostname = metrics.getHostname();

        // Find agent by hostname
        String agentId = agents.entrySet().stream()
                .filter(e -> e.getValue().hostname().equals(hostname))
                .map(Map.Entry::getKey)
                .findFirst()
                .orElse(hostname);

        // Extract key metrics
        AgentMetrics agentMetrics = AgentMetrics.from(metrics);
        latestMetrics.put(agentId, agentMetrics);

        // Log metrics summary
        if (log.isDebugEnabled()) {
            log.debug("Metrics from {}: CPU={:.1f}%, Memory={:.1f}%",
                    hostname,
                    agentMetrics.cpuUsage(),
                    agentMetrics.memoryUsage());
        }

        // Check for alerts
        checkAlerts(hostname, agentMetrics);
    }

    /**
     * Check for alert conditions
     */
    private void checkAlerts(String hostname, AgentMetrics metrics) {
        // CPU alert threshold
        if (metrics.cpuUsage() > 90) {
            log.warn("HIGH CPU ALERT: {} - CPU usage at {:.1f}%", hostname, metrics.cpuUsage());
        }

        // Memory alert threshold
        if (metrics.memoryUsage() > 90) {
            log.warn("HIGH MEMORY ALERT: {} - Memory usage at {:.1f}%", hostname, metrics.memoryUsage());
        }

        // Disk alert threshold
        for (var disk : metrics.disks()) {
            if (disk.usagePercent() > 90) {
                log.warn("HIGH DISK ALERT: {} - Disk {} usage at {:.1f}%",
                        hostname, disk.mountPoint(), disk.usagePercent());
            }
        }
    }

    /**
     * Get all connected agents
     */
    public Collection<AgentInfo> getAgents() {
        return agents.values();
    }

    /**
     * Get agent count
     */
    public int getAgentCount() {
        return agents.size();
    }

    /**
     * Get latest metrics for an agent
     */
    public AgentMetrics getLatestMetrics(String agentId) {
        return latestMetrics.get(agentId);
    }

    /**
     * Get all latest metrics
     */
    public Map<String, AgentMetrics> getAllLatestMetrics() {
        return Map.copyOf(latestMetrics);
    }

    /**
     * Get average CPU usage across all agents
     */
    public double getAverageCpuUsage() {
        return latestMetrics.values().stream()
                .mapToDouble(AgentMetrics::cpuUsage)
                .average()
                .orElse(0.0);
    }

    /**
     * Get average memory usage across all agents
     */
    public double getAverageMemoryUsage() {
        return latestMetrics.values().stream()
                .mapToDouble(AgentMetrics::memoryUsage)
                .average()
                .orElse(0.0);
    }

    /**
     * Process incoming realtime metrics (lightweight, sent every second)
     */
    public void processRealtimeMetrics(RealtimeMetrics realtime) {
        String hostname = realtime.getHostname();

        // Find agent by hostname
        String agentId = findAgentIdByHostname(hostname);

        // Update existing metrics with realtime data
        AgentMetrics existing = latestMetrics.get(agentId);
        AgentMetrics updated;
        if (existing != null) {
            // Merge realtime data into existing metrics
            updated = AgentMetrics.mergeRealtime(existing, realtime);
        } else {
            // Create new metrics from realtime data
            updated = AgentMetrics.fromRealtime(realtime);
        }
        latestMetrics.put(agentId, updated);

        // Broadcast metrics to WebSocket clients
        webSocketHandler.broadcastMetrics(agentId, updated);

        if (log.isTraceEnabled()) {
            log.trace("Realtime from {}: CPU={:.1f}%", hostname, realtime.getCpuUsagePercent());
        }
    }

    /**
     * Process incoming static info (hardware info, sent once or on request)
     */
    public void processStaticInfo(StaticInfo staticInfo) {
        String hostname = staticInfo.getHostname();
        String agentId = findAgentIdByHostname(hostname);

        staticInfoMap.put(agentId, staticInfo);

        // Merge static info into existing metrics
        AgentMetrics existing = latestMetrics.get(agentId);
        if (existing != null) {
            AgentMetrics updated = AgentMetrics.mergeStaticInfo(existing, staticInfo);
            latestMetrics.put(agentId, updated);
        }

        log.info("Received static info from {}: CPU={}, Memory={}GB",
                hostname,
                staticInfo.getCpu() != null ? staticInfo.getCpu().getModel() : "unknown",
                staticInfo.getMemory() != null ? staticInfo.getMemory().getTotal() / (1024 * 1024 * 1024) : 0);
    }

    /**
     * Process incoming periodic data (disk usage, user sessions)
     */
    public void processPeriodicData(PeriodicData periodicData) {
        String hostname = periodicData.getHostname();
        String agentId = findAgentIdByHostname(hostname);

        periodicDataMap.put(agentId, periodicData);

        // Merge periodic data into existing metrics
        AgentMetrics existing = latestMetrics.get(agentId);
        if (existing != null) {
            AgentMetrics updated = AgentMetrics.mergePeriodicData(existing, periodicData);
            latestMetrics.put(agentId, updated);
        }

        log.debug("Received periodic data from {}: {} disks, {} sessions",
                hostname,
                periodicData.getDiskUsage() != null ? periodicData.getDiskUsage().size() : 0,
                periodicData.getUserSessions() != null ? periodicData.getUserSessions().size() : 0);
    }

    /**
     * Find agent ID by hostname
     */
    private String findAgentIdByHostname(String hostname) {
        return agents.entrySet().stream()
                .filter(e -> e.getValue().hostname().equals(hostname))
                .map(Map.Entry::getKey)
                .findFirst()
                .orElse(hostname);
    }

    /**
     * Get static info for an agent
     */
    public StaticInfo getStaticInfo(String agentId) {
        return staticInfoMap.get(agentId);
    }

    /**
     * Get periodic data for an agent
     */
    public PeriodicData getPeriodicData(String agentId) {
        return periodicDataMap.get(agentId);
    }
}
