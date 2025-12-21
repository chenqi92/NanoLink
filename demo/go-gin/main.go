package main

import (
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/chenqi92/NanoLink/sdk/go/nanolink"
	"github.com/gin-gonic/gin"
)

// MetricsService stores agent information and metrics
type MetricsService struct {
	mu            sync.RWMutex
	agents        map[string]*AgentInfo
	latestMetrics map[string]*AgentMetrics
	staticInfo    map[string]*nanolink.StaticInfo
	periodicData  map[string]*nanolink.PeriodicData
}

// AgentInfo stores agent connection info
type AgentInfo struct {
	AgentID     string    `json:"agentId"`
	Hostname    string    `json:"hostname"`
	OS          string    `json:"os"`
	Arch        string    `json:"arch"`
	Version     string    `json:"version"`
	ConnectedAt time.Time `json:"connectedAt"`
}

// AgentMetrics stores metrics data
type AgentMetrics struct {
	Hostname    string    `json:"hostname"`
	CPUUsage    float64   `json:"cpuUsage"`
	MemoryUsage float64   `json:"memoryUsage"`
	MemoryTotal uint64    `json:"memoryTotal"`
	MemoryUsed  uint64    `json:"memoryUsed"`
	Timestamp   time.Time `json:"timestamp"`
}

// NewMetricsService creates a new metrics service
func NewMetricsService() *MetricsService {
	return &MetricsService{
		agents:        make(map[string]*AgentInfo),
		latestMetrics: make(map[string]*AgentMetrics),
		staticInfo:    make(map[string]*nanolink.StaticInfo),
		periodicData:  make(map[string]*nanolink.PeriodicData),
	}
}

// RegisterAgent registers a new agent
func (s *MetricsService) RegisterAgent(agent *nanolink.AgentConnection) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.agents[agent.AgentID] = &AgentInfo{
		AgentID:     agent.AgentID,
		Hostname:    agent.Hostname,
		OS:          agent.OS,
		Arch:        agent.Arch,
		Version:     agent.Version,
		ConnectedAt: agent.ConnectedAt,
	}
	log.Printf("Agent registered: %s (%s)", agent.Hostname, agent.AgentID)
}

// UnregisterAgent unregisters an agent
func (s *MetricsService) UnregisterAgent(agent *nanolink.AgentConnection) {
	s.mu.Lock()
	defer s.mu.Unlock()

	delete(s.agents, agent.AgentID)
	delete(s.latestMetrics, agent.AgentID)
	log.Printf("Agent unregistered: %s (%s)", agent.Hostname, agent.AgentID)
}

// ProcessMetrics processes incoming metrics
func (s *MetricsService) ProcessMetrics(metrics *nanolink.Metrics) {
	s.mu.Lock()
	defer s.mu.Unlock()

	// Find agent by hostname
	var agentID string
	for id, agent := range s.agents {
		if agent.Hostname == metrics.Hostname {
			agentID = id
			break
		}
	}
	if agentID == "" {
		agentID = metrics.Hostname
	}

	s.latestMetrics[agentID] = &AgentMetrics{
		Hostname:    metrics.Hostname,
		CPUUsage:    metrics.CPU.UsagePercent,
		MemoryUsage: metrics.Memory.UsagePercent(),
		MemoryTotal: metrics.Memory.Total,
		MemoryUsed:  metrics.Memory.Used,
		Timestamp:   time.Now(),
	}

	// Check for alerts
	if metrics.CPU.UsagePercent > 90 {
		log.Printf("HIGH CPU ALERT: %s - CPU usage at %.1f%%", metrics.Hostname, metrics.CPU.UsagePercent)
	}
	if metrics.Memory.UsagePercent() > 90 {
		log.Printf("HIGH MEMORY ALERT: %s - Memory usage at %.1f%%", metrics.Hostname, metrics.Memory.UsagePercent())
	}
}

// GetAgents returns all agents
func (s *MetricsService) GetAgents() []*AgentInfo {
	s.mu.RLock()
	defer s.mu.RUnlock()

	result := make([]*AgentInfo, 0, len(s.agents))
	for _, agent := range s.agents {
		result = append(result, agent)
	}
	return result
}

// GetMetrics returns metrics for an agent
func (s *MetricsService) GetMetrics(agentID string) *AgentMetrics {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.latestMetrics[agentID]
}

// GetAllMetrics returns all metrics
func (s *MetricsService) GetAllMetrics() map[string]*AgentMetrics {
	s.mu.RLock()
	defer s.mu.RUnlock()

	result := make(map[string]*AgentMetrics)
	for k, v := range s.latestMetrics {
		result[k] = v
	}
	return result
}

// GetAverageCPU returns average CPU usage
func (s *MetricsService) GetAverageCPU() float64 {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if len(s.latestMetrics) == 0 {
		return 0
	}
	var total float64
	for _, m := range s.latestMetrics {
		total += m.CPUUsage
	}
	return total / float64(len(s.latestMetrics))
}

// GetAverageMemory returns average memory usage
func (s *MetricsService) GetAverageMemory() float64 {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if len(s.latestMetrics) == 0 {
		return 0
	}
	var total float64
	for _, m := range s.latestMetrics {
		total += m.MemoryUsage
	}
	return total / float64(len(s.latestMetrics))
}

// ProcessRealtime processes realtime metrics (high-frequency, lightweight)
func (s *MetricsService) ProcessRealtime(realtime *nanolink.RealtimeMetrics) {
	s.mu.Lock()
	defer s.mu.Unlock()

	// Find agent by hostname
	var agentID string
	for id, agent := range s.agents {
		if agent.Hostname == realtime.Hostname {
			agentID = id
			break
		}
	}
	if agentID == "" {
		agentID = realtime.Hostname
	}

	// Update or create metrics with realtime data
	if existing, ok := s.latestMetrics[agentID]; ok {
		existing.CPUUsage = realtime.CPUUsage
		existing.MemoryUsage = realtime.MemoryPercent
		existing.MemoryUsed = realtime.MemoryUsed
		existing.Timestamp = time.Now()
	} else {
		s.latestMetrics[agentID] = &AgentMetrics{
			Hostname:    realtime.Hostname,
			CPUUsage:    realtime.CPUUsage,
			MemoryUsage: realtime.MemoryPercent,
			MemoryUsed:  realtime.MemoryUsed,
			Timestamp:   time.Now(),
		}
	}

	// Check for alerts
	if realtime.CPUUsage > 90 {
		log.Printf("HIGH CPU ALERT: %s - CPU usage at %.1f%%", realtime.Hostname, realtime.CPUUsage)
	}
}

// ProcessStaticInfo processes static hardware info (received once on connect)
func (s *MetricsService) ProcessStaticInfo(staticInfo *nanolink.StaticInfo) {
	s.mu.Lock()
	defer s.mu.Unlock()

	// Find agent by hostname
	var agentID string
	for id, agent := range s.agents {
		if agent.Hostname == staticInfo.Hostname {
			agentID = id
			break
		}
	}
	if agentID == "" {
		agentID = staticInfo.Hostname
	}

	// Store static info
	s.staticInfo[agentID] = staticInfo

	log.Printf("Static info received from %s: OS=%s %s, Kernel=%s",
		staticInfo.Hostname, staticInfo.OSName, staticInfo.OSVersion, staticInfo.KernelVersion)

	// Update memory_total if available
	if staticInfo.Memory != nil && staticInfo.Memory.TotalPhysical > 0 {
		if existing, ok := s.latestMetrics[agentID]; ok {
			existing.MemoryTotal = staticInfo.Memory.TotalPhysical
		}
	}
}

// ProcessPeriodic processes periodic data (disk usage, user sessions, etc.)
func (s *MetricsService) ProcessPeriodic(periodic *nanolink.PeriodicData) {
	s.mu.Lock()
	defer s.mu.Unlock()

	// Find agent by hostname
	var agentID string
	for id, agent := range s.agents {
		if agent.Hostname == periodic.Hostname {
			agentID = id
			break
		}
	}
	if agentID == "" {
		agentID = periodic.Hostname
	}

	// Store periodic data
	s.periodicData[agentID] = periodic

	diskCount := 0
	if periodic.DiskUsage != nil {
		diskCount = len(periodic.DiskUsage)
	}
	sessionCount := 0
	if periodic.UserSessions != nil {
		sessionCount = len(periodic.UserSessions)
	}
	log.Printf("Periodic data received from %s: uptime=%ds, disks=%d, sessions=%d",
		periodic.Hostname, periodic.UptimeSeconds, diskCount, sessionCount)
}

// GetStaticInfo returns static info for an agent
func (s *MetricsService) GetStaticInfo(agentID string) *nanolink.StaticInfo {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.staticInfo[agentID]
}

// GetPeriodicData returns periodic data for an agent
func (s *MetricsService) GetPeriodicData(agentID string) *nanolink.PeriodicData {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.periodicData[agentID]
}

func main() {
	// Initialize metrics service
	metricsService := NewMetricsService()

	// Initialize NanoLink server
	// WsPort: for dashboard WebSocket connections (default: 9100)
	// GrpcPort: for agent gRPC connections (default: 39100)
	server := nanolink.NewServer(nanolink.Config{
		WsPort:   9100,
		GrpcPort: 39100,
		// StaticFilesPath: "/path/to/dashboard", // Optional: serve dashboard static files
	})

	// Set callbacks
	server.OnAgentConnect(func(agent *nanolink.AgentConnection) {
		log.Printf("Agent connected: %s (%s/%s)", agent.Hostname, agent.OS, agent.Arch)
		metricsService.RegisterAgent(agent)
	})

	server.OnAgentDisconnect(func(agent *nanolink.AgentConnection) {
		log.Printf("Agent disconnected: %s", agent.Hostname)
		metricsService.UnregisterAgent(agent)
	})

	server.OnMetrics(func(metrics *nanolink.Metrics) {
		metricsService.ProcessMetrics(metrics)
	})

	server.OnRealtimeMetrics(func(realtime *nanolink.RealtimeMetrics) {
		metricsService.ProcessRealtime(realtime)
	})

	server.OnStaticInfo(func(staticInfo *nanolink.StaticInfo) {
		metricsService.ProcessStaticInfo(staticInfo)
	})

	server.OnPeriodicData(func(periodic *nanolink.PeriodicData) {
		metricsService.ProcessPeriodic(periodic)
	})

	// Start NanoLink server in background
	go func() {
		log.Printf("NanoLink Server starting - WebSocket port 9100, gRPC port 39100")
		if err := server.Start(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Failed to start NanoLink server: %v", err)
		}
	}()

	// Initialize Gin router
	router := gin.Default()

	// CORS middleware
	router.Use(func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	})

	// API routes
	api := router.Group("/api")
	{
		// Agent endpoints
		api.GET("/agents", func(c *gin.Context) {
			agents := metricsService.GetAgents()
			c.JSON(http.StatusOK, gin.H{
				"agents": agents,
				"count":  len(agents),
			})
		})

		api.GET("/agents/:agentId/metrics", func(c *gin.Context) {
			agentID := c.Param("agentId")
			metrics := metricsService.GetMetrics(agentID)
			if metrics == nil {
				c.JSON(http.StatusNotFound, gin.H{"error": "Agent not found"})
				return
			}
			c.JSON(http.StatusOK, metrics)
		})

		// Metrics endpoints
		api.GET("/metrics", func(c *gin.Context) {
			c.JSON(http.StatusOK, metricsService.GetAllMetrics())
		})

		api.GET("/summary", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{
				"agentCount":     len(metricsService.GetAgents()),
				"avgCpuUsage":    metricsService.GetAverageCPU(),
				"avgMemoryUsage": metricsService.GetAverageMemory(),
			})
		})

		// Health check
		api.GET("/health", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{
				"status":          "ok",
				"connectedAgents": len(metricsService.GetAgents()),
			})
		})

		// Command endpoints
		api.POST("/commands/agents/:hostname/service/restart", func(c *gin.Context) {
			hostname := c.Param("hostname")
			var req struct {
				ServiceName string `json:"serviceName"`
			}
			if err := c.ShouldBindJSON(&req); err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
				return
			}

			agent := server.GetAgentByHostname(hostname)
			if agent == nil {
				c.JSON(http.StatusNotFound, gin.H{"error": "Agent not found"})
				return
			}

			log.Printf("Restarting service %s on %s", req.ServiceName, hostname)
			if _, err := agent.RestartService(req.ServiceName); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"success": false, "message": err.Error()})
				return
			}
			c.JSON(http.StatusOK, gin.H{"success": true, "message": "Service restart command sent"})
		})

		api.POST("/commands/agents/:hostname/process/kill", func(c *gin.Context) {
			hostname := c.Param("hostname")
			var req struct {
				PID    int    `json:"pid"`
				Target string `json:"target"`
			}
			if err := c.ShouldBindJSON(&req); err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
				return
			}

			agent := server.GetAgentByHostname(hostname)
			if agent == nil {
				c.JSON(http.StatusNotFound, gin.H{"error": "Agent not found"})
				return
			}

			// Use target if provided, otherwise convert PID to string
			target := req.Target
			if target == "" {
				target = fmt.Sprintf("%d", req.PID)
			}

			log.Printf("Killing process %s on %s", target, hostname)
			if _, err := agent.KillProcess(target); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"success": false, "message": err.Error()})
				return
			}
			c.JSON(http.StatusOK, gin.H{"success": true, "message": "Process kill command sent"})
		})

		api.POST("/commands/agents/:hostname/docker/restart", func(c *gin.Context) {
			hostname := c.Param("hostname")
			var req struct {
				ContainerName string `json:"containerName"`
			}
			if err := c.ShouldBindJSON(&req); err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
				return
			}

			agent := server.GetAgentByHostname(hostname)
			if agent == nil {
				c.JSON(http.StatusNotFound, gin.H{"error": "Agent not found"})
				return
			}

			log.Printf("Restarting container %s on %s", req.ContainerName, hostname)
			if _, err := agent.RestartContainer(req.ContainerName); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"success": false, "message": err.Error()})
				return
			}
			c.JSON(http.StatusOK, gin.H{"success": true, "message": "Container restart command sent"})
		})
	}

	// Start HTTP server
	log.Printf("REST API server starting on http://localhost:8080")
	if err := router.Run(":8080"); err != nil {
		log.Fatalf("Failed to start HTTP server: %v", err)
	}
}
