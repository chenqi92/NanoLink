package service

import (
	"sync"
	"time"

	"go.uber.org/zap"
)

// MetricsData holds system metrics from an agent
type MetricsData struct {
	AgentID   string    `json:"agentId"`
	Timestamp time.Time `json:"timestamp"`
	CPU       CPUData   `json:"cpu"`
	Memory    MemData   `json:"memory"`
	Disks     []DiskData   `json:"disks"`
	Networks  []NetData    `json:"networks"`
	GPU       *GPUData     `json:"gpu,omitempty"`
}

type CPUData struct {
	UsagePercent float64   `json:"usagePercent"`
	CoreCount    int       `json:"coreCount"`
	PerCoreUsage []float64 `json:"perCoreUsage"`
	LoadAverage  []float64 `json:"loadAverage"`
}

type MemData struct {
	Total     uint64 `json:"total"`
	Used      uint64 `json:"used"`
	Available uint64 `json:"available"`
	SwapTotal uint64 `json:"swapTotal"`
	SwapUsed  uint64 `json:"swapUsed"`
}

type DiskData struct {
	MountPoint    string `json:"mountPoint"`
	Total         uint64 `json:"total"`
	Used          uint64 `json:"used"`
	ReadBytesPS   uint64 `json:"readBytesPerSec"`
	WriteBytesPS  uint64 `json:"writeBytesPerSec"`
}

type NetData struct {
	Interface    string `json:"interface"`
	RxBytesPS    uint64 `json:"rxBytesPerSec"`
	TxBytesPS    uint64 `json:"txBytesPerSec"`
	RxPacketsPS  uint64 `json:"rxPacketsPerSec"`
	TxPacketsPS  uint64 `json:"txPacketsPerSec"`
}

type GPUData struct {
	Name        string  `json:"name"`
	UsagePercent float64 `json:"usagePercent"`
	MemoryTotal uint64  `json:"memoryTotal"`
	MemoryUsed  uint64  `json:"memoryUsed"`
	Temperature float64 `json:"temperature"`
}

// MetricsService manages metrics storage and retrieval
type MetricsService struct {
	// Current metrics per agent
	current map[string]*MetricsData
	// Historical metrics (ring buffer per agent)
	history map[string][]*MetricsData
	// Max history entries per agent
	maxHistory int
	mu         sync.RWMutex
	logger     *zap.SugaredLogger
}

// NewMetricsService creates a new metrics service
func NewMetricsService(logger *zap.SugaredLogger) *MetricsService {
	return &MetricsService{
		current:    make(map[string]*MetricsData),
		history:    make(map[string][]*MetricsData),
		maxHistory: 600, // 10 minutes at 1-second intervals
		logger:     logger,
	}
}

// StoreMetrics stores metrics for an agent
func (s *MetricsService) StoreMetrics(agentID string, data *MetricsData) {
	s.mu.Lock()
	defer s.mu.Unlock()

	data.AgentID = agentID
	data.Timestamp = time.Now()

	// Update current
	s.current[agentID] = data

	// Add to history
	if _, exists := s.history[agentID]; !exists {
		s.history[agentID] = make([]*MetricsData, 0, s.maxHistory)
	}

	history := s.history[agentID]
	if len(history) >= s.maxHistory {
		// Remove oldest entry
		history = history[1:]
	}
	s.history[agentID] = append(history, data)
}

// GetCurrentMetrics returns current metrics for an agent
func (s *MetricsService) GetCurrentMetrics(agentID string) *MetricsData {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.current[agentID]
}

// GetAllCurrentMetrics returns current metrics for all agents
func (s *MetricsService) GetAllCurrentMetrics() map[string]*MetricsData {
	s.mu.RLock()
	defer s.mu.RUnlock()

	result := make(map[string]*MetricsData)
	for id, data := range s.current {
		result[id] = data
	}
	return result
}

// GetMetricsHistory returns historical metrics for an agent
func (s *MetricsService) GetMetricsHistory(agentID string, limit int) []*MetricsData {
	s.mu.RLock()
	defer s.mu.RUnlock()

	history, exists := s.history[agentID]
	if !exists {
		return nil
	}

	if limit <= 0 || limit > len(history) {
		limit = len(history)
	}

	// Return most recent entries
	start := len(history) - limit
	result := make([]*MetricsData, limit)
	copy(result, history[start:])
	return result
}

// GetAllMetricsHistory returns historical metrics for all agents
func (s *MetricsService) GetAllMetricsHistory(limit int) map[string][]*MetricsData {
	s.mu.RLock()
	defer s.mu.RUnlock()

	result := make(map[string][]*MetricsData)
	for id := range s.history {
		result[id] = s.GetMetricsHistory(id, limit)
	}
	return result
}

// RemoveAgent removes metrics for an agent
func (s *MetricsService) RemoveAgent(agentID string) {
	s.mu.Lock()
	defer s.mu.Unlock()

	delete(s.current, agentID)
	delete(s.history, agentID)
}

// GetSummary returns a summary of all metrics
func (s *MetricsService) GetSummary() map[string]interface{} {
	s.mu.RLock()
	defer s.mu.RUnlock()

	totalCPU := 0.0
	totalMem := uint64(0)
	usedMem := uint64(0)
	agentCount := len(s.current)

	for _, data := range s.current {
		totalCPU += data.CPU.UsagePercent
		totalMem += data.Memory.Total
		usedMem += data.Memory.Used
	}

	avgCPU := 0.0
	memPercent := 0.0
	if agentCount > 0 {
		avgCPU = totalCPU / float64(agentCount)
	}
	if totalMem > 0 {
		memPercent = float64(usedMem) / float64(totalMem) * 100
	}

	return map[string]interface{}{
		"agentCount":       agentCount,
		"avgCpuPercent":    avgCPU,
		"totalMemory":      totalMem,
		"usedMemory":       usedMem,
		"memoryPercent":    memPercent,
	}
}
