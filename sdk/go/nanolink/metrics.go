package nanolink

// Metrics represents system metrics from an agent
type Metrics struct {
	Timestamp   int64            `json:"timestamp"`
	Hostname    string           `json:"hostname"`
	CPU         *CPUMetrics      `json:"cpu,omitempty"`
	Memory      *MemoryMetrics   `json:"memory,omitempty"`
	Disks       []DiskMetrics    `json:"disks,omitempty"`
	Networks    []NetworkMetrics `json:"networks,omitempty"`
	LoadAverage []float64        `json:"loadAverage,omitempty"`
}

// CPUMetrics represents CPU metrics
type CPUMetrics struct {
	UsagePercent float64   `json:"usagePercent"`
	CoreCount    int       `json:"coreCount"`
	PerCoreUsage []float64 `json:"perCoreUsage,omitempty"`
}

// MemoryMetrics represents memory metrics
type MemoryMetrics struct {
	Total     uint64 `json:"total"`
	Used      uint64 `json:"used"`
	Available uint64 `json:"available"`
	SwapTotal uint64 `json:"swapTotal"`
	SwapUsed  uint64 `json:"swapUsed"`
}

// UsagePercent returns memory usage percentage
func (m *MemoryMetrics) UsagePercent() float64 {
	if m.Total == 0 {
		return 0
	}
	return float64(m.Used) / float64(m.Total) * 100
}

// DiskMetrics represents disk metrics
type DiskMetrics struct {
	MountPoint      string `json:"mountPoint"`
	Device          string `json:"device"`
	FSType          string `json:"fsType"`
	Total           uint64 `json:"total"`
	Used            uint64 `json:"used"`
	Available       uint64 `json:"available"`
	ReadBytesPerSec uint64 `json:"readBytesPerSec"`
	WriteBytesPerSec uint64 `json:"writeBytesPerSec"`
}

// UsagePercent returns disk usage percentage
func (d *DiskMetrics) UsagePercent() float64 {
	if d.Total == 0 {
		return 0
	}
	return float64(d.Used) / float64(d.Total) * 100
}

// NetworkMetrics represents network interface metrics
type NetworkMetrics struct {
	Interface       string `json:"interface"`
	RxBytesPerSec   uint64 `json:"rxBytesPerSec"`
	TxBytesPerSec   uint64 `json:"txBytesPerSec"`
	RxPacketsPerSec uint64 `json:"rxPacketsPerSec"`
	TxPacketsPerSec uint64 `json:"txPacketsPerSec"`
	IsUp            bool   `json:"isUp"`
}

// ProcessInfo represents process information
type ProcessInfo struct {
	PID         int     `json:"pid"`
	Name        string  `json:"name"`
	User        string  `json:"user"`
	CPUPercent  float64 `json:"cpuPercent"`
	MemoryBytes uint64  `json:"memoryBytes"`
	Status      string  `json:"status"`
	StartTime   int64   `json:"startTime"`
}

// ContainerInfo represents Docker container information
type ContainerInfo struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Image   string `json:"image"`
	Status  string `json:"status"`
	State   string `json:"state"`
	Created int64  `json:"created"`
}
