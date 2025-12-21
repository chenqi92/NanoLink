package service

import (
	"sync"
	"time"

	"go.uber.org/zap"
)

// MetricsData holds system metrics from an agent
type MetricsData struct {
	AgentID      string        `json:"agentId"`
	Timestamp    time.Time     `json:"timestamp"`
	CPU          CPUData       `json:"cpu"`
	Memory       MemData       `json:"memory"`
	Disks        []DiskData    `json:"disks"`
	Networks     []NetData     `json:"networks"`
	GPUs         []GPUData     `json:"gpus"`
	NPUs         []NPUData     `json:"npus"`
	UserSessions []UserSession `json:"userSessions"`
	SystemInfo   *SystemInfo   `json:"systemInfo,omitempty"`
	LoadAverage  []float64     `json:"loadAverage"`
}

type CPUData struct {
	UsagePercent  float64   `json:"usagePercent"`
	CoreCount     int       `json:"coreCount"`
	PerCoreUsage  []float64 `json:"perCoreUsage"`
	LoadAverage   []float64 `json:"loadAverage"`
	Model         string    `json:"model"`
	Vendor        string    `json:"vendor"`
	FrequencyMhz  uint64    `json:"frequencyMhz"`
	FrequencyMax  uint64    `json:"frequencyMaxMhz"`
	PhysicalCores int       `json:"physicalCores"`
	LogicalCores  int       `json:"logicalCores"`
	Architecture  string    `json:"architecture"`
	Temperature   float64   `json:"temperature"`
}

type MemData struct {
	Total          uint64 `json:"total"`
	Used           uint64 `json:"used"`
	Available      uint64 `json:"available"`
	SwapTotal      uint64 `json:"swapTotal"`
	SwapUsed       uint64 `json:"swapUsed"`
	Cached         uint64 `json:"cached"`
	Buffers        uint64 `json:"buffers"`
	MemoryType     string `json:"memoryType"`
	MemorySpeedMhz uint32 `json:"memorySpeedMhz"`
}

type DiskData struct {
	MountPoint   string  `json:"mountPoint"`
	Device       string  `json:"device"`
	FsType       string  `json:"fsType"`
	Total        uint64  `json:"total"`
	Used         uint64  `json:"used"`
	Available    uint64  `json:"available"`
	UsagePercent float64 `json:"usagePercent"`
	ReadBytesPS  uint64  `json:"readBytesPerSec"`
	WriteBytesPS uint64  `json:"writeBytesPerSec"`
	Model        string  `json:"model"`
	Serial       string  `json:"serial"`
	DiskType     string  `json:"diskType"`
	ReadIops     uint64  `json:"readIops"`
	WriteIops    uint64  `json:"writeIops"`
	Temperature  float64 `json:"temperature"`
	HealthStatus string  `json:"healthStatus"`
}

type NetData struct {
	Interface     string   `json:"interface"`
	RxBytesPS     uint64   `json:"rxBytesPerSec"`
	TxBytesPS     uint64   `json:"txBytesPerSec"`
	RxPacketsPS   uint64   `json:"rxPacketsPerSec"`
	TxPacketsPS   uint64   `json:"txPacketsPerSec"`
	IsUp          bool     `json:"isUp"`
	MacAddress    string   `json:"macAddress"`
	IpAddresses   []string `json:"ipAddresses"`
	SpeedMbps     uint64   `json:"speedMbps"`
	InterfaceType string   `json:"interfaceType"`
}

type GPUData struct {
	Index           int     `json:"index"`
	Name            string  `json:"name"`
	Vendor          string  `json:"vendor"`
	UsagePercent    float64 `json:"usagePercent"`
	MemoryTotal     uint64  `json:"memoryTotal"`
	MemoryUsed      uint64  `json:"memoryUsed"`
	Temperature     float64 `json:"temperature"`
	FanSpeedPercent int     `json:"fanSpeedPercent"`
	PowerWatts      int     `json:"powerWatts"`
	PowerLimitWatts int     `json:"powerLimitWatts"`
	ClockCoreMhz    uint64  `json:"clockCoreMhz"`
	ClockMemoryMhz  uint64  `json:"clockMemoryMhz"`
	DriverVersion   string  `json:"driverVersion"`
	PcieGeneration  string  `json:"pcieGeneration"`
	EncoderUsage    float64 `json:"encoderUsage"`
	DecoderUsage    float64 `json:"decoderUsage"`
}

type NPUData struct {
	Index         int     `json:"index"`
	Name          string  `json:"name"`
	Vendor        string  `json:"vendor"`
	UsagePercent  float64 `json:"usagePercent"`
	MemoryTotal   uint64  `json:"memoryTotal"`
	MemoryUsed    uint64  `json:"memoryUsed"`
	Temperature   float64 `json:"temperature"`
	PowerWatts    int     `json:"powerWatts"`
	DriverVersion string  `json:"driverVersion"`
}

type UserSession struct {
	Username    string `json:"username"`
	Tty         string `json:"tty"`
	LoginTime   int64  `json:"loginTime"`
	RemoteHost  string `json:"remoteHost"`
	IdleSeconds int64  `json:"idleSeconds"`
	SessionType string `json:"sessionType"`
}

type SystemInfo struct {
	OsName            string `json:"osName"`
	OsVersion         string `json:"osVersion"`
	KernelVersion     string `json:"kernelVersion"`
	Hostname          string `json:"hostname"`
	BootTime          int64  `json:"bootTime"`
	UptimeSeconds     int64  `json:"uptimeSeconds"`
	MotherboardModel  string `json:"motherboardModel"`
	MotherboardVendor string `json:"motherboardVendor"`
	BiosVersion       string `json:"biosVersion"`
	SystemModel       string `json:"systemModel"`
	SystemVendor      string `json:"systemVendor"`
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

	// Broadcast callback for real-time push to dashboard clients
	broadcastCallback func(agentID string, metrics interface{})
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

	// Broadcast to dashboard clients if callback is set
	if s.broadcastCallback != nil {
		go s.broadcastCallback(agentID, data)
	}

	s.history[agentID] = append(history, data)
}

// SetBroadcastCallback sets the callback for broadcasting metrics to dashboard clients
func (s *MetricsService) SetBroadcastCallback(callback func(agentID string, metrics interface{})) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.broadcastCallback = callback
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
		"agentCount":    agentCount,
		"avgCpuPercent": avgCPU,
		"totalMemory":   totalMem,
		"usedMemory":    usedMem,
		"memoryPercent": memPercent,
	}
}

// RealtimeUpdate holds realtime metrics for merging
type RealtimeUpdate struct {
	CPUUsage     float64
	CPUPerCore   []float64
	CPUTemp      float64
	CPUFrequency uint64
	MemoryUsed   uint64
	MemoryCached uint64
	SwapUsed     uint64
	DiskIO       []DiskData
	NetworkIO    []NetData
	LoadAverage  []float64
	GPUUsage     []GPUData
	NPUUsage     []NPUData
}

// MergeRealtimeMetrics merges realtime data into existing metrics
func (s *MetricsService) MergeRealtimeMetrics(agentID string, update interface{}) {
	s.mu.Lock()
	defer s.mu.Unlock()

	// Get or create current metrics
	current := s.current[agentID]
	if current == nil {
		current = &MetricsData{AgentID: agentID}
		s.current[agentID] = current
	}
	current.Timestamp = time.Now()

	// Type assert and merge
	if rt, ok := update.(*RealtimeUpdate); ok && rt != nil {
		current.CPU.UsagePercent = rt.CPUUsage
		if len(rt.CPUPerCore) > 0 {
			current.CPU.PerCoreUsage = rt.CPUPerCore
		}
		current.CPU.Temperature = rt.CPUTemp
		current.CPU.FrequencyMhz = rt.CPUFrequency
		current.Memory.Used = rt.MemoryUsed
		current.Memory.Cached = rt.MemoryCached
		current.Memory.SwapUsed = rt.SwapUsed
		if len(rt.LoadAverage) > 0 {
			current.LoadAverage = rt.LoadAverage
		}

		// Merge disk IO by device
		for _, io := range rt.DiskIO {
			found := false
			for i, d := range current.Disks {
				if d.Device == io.Device {
					current.Disks[i].ReadBytesPS = io.ReadBytesPS
					current.Disks[i].WriteBytesPS = io.WriteBytesPS
					current.Disks[i].ReadIops = io.ReadIops
					current.Disks[i].WriteIops = io.WriteIops
					found = true
					break
				}
			}
			if !found {
				current.Disks = append(current.Disks, io)
			}
		}

		// Merge network IO by interface
		for _, io := range rt.NetworkIO {
			found := false
			for i, n := range current.Networks {
				if n.Interface == io.Interface {
					current.Networks[i].RxBytesPS = io.RxBytesPS
					current.Networks[i].TxBytesPS = io.TxBytesPS
					current.Networks[i].RxPacketsPS = io.RxPacketsPS
					current.Networks[i].TxPacketsPS = io.TxPacketsPS
					current.Networks[i].IsUp = io.IsUp
					found = true
					break
				}
			}
			if !found {
				current.Networks = append(current.Networks, io)
			}
		}

		// Merge GPU usage by index
		for _, g := range rt.GPUUsage {
			found := false
			for i, gpu := range current.GPUs {
				if gpu.Index == g.Index {
					current.GPUs[i].UsagePercent = g.UsagePercent
					current.GPUs[i].MemoryUsed = g.MemoryUsed
					current.GPUs[i].Temperature = g.Temperature
					current.GPUs[i].PowerWatts = g.PowerWatts
					current.GPUs[i].ClockCoreMhz = g.ClockCoreMhz
					current.GPUs[i].EncoderUsage = g.EncoderUsage
					current.GPUs[i].DecoderUsage = g.DecoderUsage
					found = true
					break
				}
			}
			if !found {
				current.GPUs = append(current.GPUs, g)
			}
		}

		// Merge NPU usage by index
		for _, n := range rt.NPUUsage {
			found := false
			for i, npu := range current.NPUs {
				if npu.Index == n.Index {
					current.NPUs[i].UsagePercent = n.UsagePercent
					current.NPUs[i].MemoryUsed = n.MemoryUsed
					current.NPUs[i].Temperature = n.Temperature
					current.NPUs[i].PowerWatts = n.PowerWatts
					found = true
					break
				}
			}
			if !found {
				current.NPUs = append(current.NPUs, n)
			}
		}
	}

	// Add to history
	s.addToHistory(agentID, current)
}

// StaticUpdate holds static hardware info for merging
type StaticUpdate struct {
	CPU        *CPUData
	Memory     *MemData
	Disks      []DiskData
	Networks   []NetData
	GPUs       []GPUData
	NPUs       []NPUData
	SystemInfo *SystemInfo
}

// MergeStaticInfo merges static hardware info into existing metrics
func (s *MetricsService) MergeStaticInfo(agentID string, update interface{}) {
	s.mu.Lock()
	defer s.mu.Unlock()

	current := s.current[agentID]
	if current == nil {
		current = &MetricsData{AgentID: agentID}
		s.current[agentID] = current
	}

	if st, ok := update.(*StaticUpdate); ok && st != nil {
		if st.CPU != nil {
			current.CPU.Model = st.CPU.Model
			current.CPU.Vendor = st.CPU.Vendor
			current.CPU.PhysicalCores = st.CPU.PhysicalCores
			current.CPU.LogicalCores = st.CPU.LogicalCores
			current.CPU.Architecture = st.CPU.Architecture
			current.CPU.FrequencyMax = st.CPU.FrequencyMax
		}

		if st.Memory != nil {
			current.Memory.Total = st.Memory.Total
			current.Memory.SwapTotal = st.Memory.SwapTotal
			current.Memory.MemoryType = st.Memory.MemoryType
			current.Memory.MemorySpeedMhz = st.Memory.MemorySpeedMhz
		}

		// Merge disk static info
		for _, d := range st.Disks {
			found := false
			for i, disk := range current.Disks {
				if disk.Device == d.Device || disk.MountPoint == d.MountPoint {
					current.Disks[i].Model = d.Model
					current.Disks[i].Serial = d.Serial
					current.Disks[i].DiskType = d.DiskType
					current.Disks[i].FsType = d.FsType
					current.Disks[i].HealthStatus = d.HealthStatus
					if d.Total > 0 {
						current.Disks[i].Total = d.Total
					}
					found = true
					break
				}
			}
			if !found {
				current.Disks = append(current.Disks, d)
			}
		}

		// Merge network static info
		for _, n := range st.Networks {
			found := false
			for i, net := range current.Networks {
				if net.Interface == n.Interface {
					current.Networks[i].MacAddress = n.MacAddress
					current.Networks[i].IpAddresses = n.IpAddresses
					current.Networks[i].SpeedMbps = n.SpeedMbps
					current.Networks[i].InterfaceType = n.InterfaceType
					found = true
					break
				}
			}
			if !found {
				current.Networks = append(current.Networks, n)
			}
		}

		// Merge GPU static info
		for _, g := range st.GPUs {
			found := false
			for i, gpu := range current.GPUs {
				if gpu.Index == g.Index {
					current.GPUs[i].Name = g.Name
					current.GPUs[i].Vendor = g.Vendor
					current.GPUs[i].MemoryTotal = g.MemoryTotal
					current.GPUs[i].DriverVersion = g.DriverVersion
					current.GPUs[i].PcieGeneration = g.PcieGeneration
					current.GPUs[i].PowerLimitWatts = g.PowerLimitWatts
					found = true
					break
				}
			}
			if !found {
				current.GPUs = append(current.GPUs, g)
			}
		}

		// Merge NPU static info
		for _, n := range st.NPUs {
			found := false
			for i, npu := range current.NPUs {
				if npu.Index == n.Index {
					current.NPUs[i].Name = n.Name
					current.NPUs[i].Vendor = n.Vendor
					current.NPUs[i].MemoryTotal = n.MemoryTotal
					current.NPUs[i].DriverVersion = n.DriverVersion
					found = true
					break
				}
			}
			if !found {
				current.NPUs = append(current.NPUs, n)
			}
		}

		if st.SystemInfo != nil {
			current.SystemInfo = st.SystemInfo
		}
	}
}

// PeriodicUpdate holds periodic data for merging
type PeriodicUpdate struct {
	DiskUsage      []DiskData
	UserSessions   []UserSession
	NetworkUpdates []NetData
}

// MergePeriodicData merges periodic data into existing metrics
func (s *MetricsService) MergePeriodicData(agentID string, update interface{}) {
	s.mu.Lock()
	defer s.mu.Unlock()

	current := s.current[agentID]
	if current == nil {
		current = &MetricsData{AgentID: agentID}
		s.current[agentID] = current
	}

	if p, ok := update.(*PeriodicUpdate); ok && p != nil {
		// Merge disk usage
		for _, d := range p.DiskUsage {
			found := false
			for i, disk := range current.Disks {
				if disk.Device == d.Device || disk.MountPoint == d.MountPoint {
					current.Disks[i].Used = d.Used
					current.Disks[i].Available = d.Available
					current.Disks[i].UsagePercent = d.UsagePercent
					if d.Total > 0 {
						current.Disks[i].Total = d.Total
					}
					if d.Temperature > 0 {
						current.Disks[i].Temperature = d.Temperature
					}
					found = true
					break
				}
			}
			if !found {
				current.Disks = append(current.Disks, d)
			}
		}

		// Replace user sessions
		if len(p.UserSessions) > 0 {
			current.UserSessions = p.UserSessions
		}

		// Merge network updates (IP changes, status)
		for _, n := range p.NetworkUpdates {
			for i, net := range current.Networks {
				if net.Interface == n.Interface {
					if len(n.IpAddresses) > 0 {
						current.Networks[i].IpAddresses = n.IpAddresses
					}
					current.Networks[i].IsUp = n.IsUp
					break
				}
			}
		}
	}
}

// addToHistory adds metrics to history (internal, must hold lock)
func (s *MetricsService) addToHistory(agentID string, data *MetricsData) {
	if _, exists := s.history[agentID]; !exists {
		s.history[agentID] = make([]*MetricsData, 0, s.maxHistory)
	}

	// Make a copy for history
	copy := *data
	history := s.history[agentID]
	if len(history) >= s.maxHistory {
		history = history[1:]
	}
	s.history[agentID] = append(history, &copy)
}
