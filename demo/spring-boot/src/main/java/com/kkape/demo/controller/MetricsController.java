package com.kkape.demo.controller;

import com.kkape.demo.model.AgentInfo;
import com.kkape.demo.model.AgentMetrics;
import com.kkape.demo.service.MetricsService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Collection;
import java.util.Map;

/**
 * REST API for accessing agent metrics
 *
 * Provides endpoints to query connected agents and their metrics.
 */
@RestController
@RequestMapping("/api")
@CrossOrigin(origins = "*")
public class MetricsController {

    private final MetricsService metricsService;

    public MetricsController(MetricsService metricsService) {
        this.metricsService = metricsService;
    }

    /**
     * Get all connected agents
     */
    @GetMapping("/agents")
    public ResponseEntity<AgentsResponse> getAgents() {
        Collection<AgentInfo> agents = metricsService.getAgents();
        return ResponseEntity.ok(new AgentsResponse(agents, agents.size()));
    }

    /**
     * Get metrics for a specific agent
     */
    @GetMapping("/agents/{agentId}/metrics")
    public ResponseEntity<AgentMetrics> getAgentMetrics(@PathVariable String agentId) {
        AgentMetrics metrics = metricsService.getLatestMetrics(agentId);
        if (metrics == null) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(metrics);
    }

    /**
     * Get all latest metrics
     */
    @GetMapping("/metrics")
    public ResponseEntity<Map<String, AgentMetrics>> getAllMetrics() {
        return ResponseEntity.ok(metricsService.getAllLatestMetrics());
    }

    /**
     * Get cluster summary
     */
    @GetMapping("/summary")
    public ResponseEntity<ClusterSummary> getSummary() {
        return ResponseEntity.ok(new ClusterSummary(
                metricsService.getAgentCount(),
                metricsService.getAverageCpuUsage(),
                metricsService.getAverageMemoryUsage()
        ));
    }

    /**
     * Health check endpoint
     */
    @GetMapping("/health")
    public ResponseEntity<HealthResponse> health() {
        return ResponseEntity.ok(new HealthResponse(
                "ok",
                metricsService.getAgentCount()
        ));
    }

    // Response DTOs

    record AgentsResponse(Collection<AgentInfo> agents, int count) {
    }

    record ClusterSummary(int agentCount, double avgCpuUsage, double avgMemoryUsage) {
    }

    record HealthResponse(String status, int connectedAgents) {
    }
}
