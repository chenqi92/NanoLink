package com.kkape.demo.service;

import com.kkape.sdk.AgentConnection;
import com.kkape.sdk.model.Metrics;
import com.kkape.demo.model.AgentInfo;
import com.kkape.demo.model.AgentMetrics;
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

    // Store agent info
    private final Map<String, AgentInfo> agents = new ConcurrentHashMap<>();

    // Store latest metrics per agent
    private final Map<String, AgentMetrics> latestMetrics = new ConcurrentHashMap<>();

    /**
     * Register a new agent connection
     */
    public void registerAgent(AgentConnection agent) {
        AgentInfo info = new AgentInfo(
                agent.getAgentId(),
                agent.getHostname(),
                agent.getOs(),
                agent.getArch(),
                agent.getVersion(),
                Instant.now()
        );
        agents.put(agent.getAgentId(), info);
        log.debug("Registered agent: {}", info);
    }

    /**
     * Unregister an agent
     */
    public void unregisterAgent(AgentConnection agent) {
        agents.remove(agent.getAgentId());
        latestMetrics.remove(agent.getAgentId());
        log.debug("Unregistered agent: {}", agent.getHostname());
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
}
