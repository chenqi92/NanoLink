package nanolink

// Metrics represents system metrics from an agent
type Metrics struct {
	Timestamp    int64            `json:"timestamp"`
	Hostname     string           `json:"hostname"`
	CPU          *CPUMetrics      `json:"cpu,omitempty"`
	Memory       *MemoryMetrics   `json:"memory,omitempty"`
	Disks        []DiskMetrics    `json:"disks,omitempty"`
	Networks     []NetworkMetrics `json:"networks,omitempty"`
	GPUs         []GPUMetrics     `json:"gpus,omitempty"`
	NPUs         []NPUMetrics     `json:"npus,omitempty"`
	UserSessions []UserSession    `json:"userSessions,omitempty"`
	SystemInfo   *SystemInfo      `json:"systemInfo,omitempty"`
	LoadAverage  []float64        `json:"loadAverage,omitempty"`
}

// CPUMetrics represents CPU metrics
type CPUMetrics struct {
	UsagePercent float64   `json:"usagePercent"`
	CoreCount    int       `json:"coreCount"`
	PerCoreUsage []float64 `json:"perCoreUsage,omitempty"`
	Model        string    `json:"model,omitempty"`
	Vendor       string    `json:"vendor,omitempty"`
	FrequencyMHz uint64    `json:"frequencyMhz,omitempty"`
	Temperature  float64   `json:"temperature,omitempty"`
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
	MountPoint       string  `json:"mountPoint"`
	Device           string  `json:"device"`
	FSType           string  `json:"fsType"`
	Total            uint64  `json:"total"`
	Used             uint64  `json:"used"`
	Available        uint64  `json:"available"`
	ReadBytesPerSec  uint64  `json:"readBytesPerSec"`
	WriteBytesPerSec uint64  `json:"writeBytesPerSec"`
	Model            string  `json:"model,omitempty"`
	DiskType         string  `json:"diskType,omitempty"`
	Temperature      float64 `json:"temperature,omitempty"`
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
	Interface       string   `json:"interface"`
	RxBytesPerSec   uint64   `json:"rxBytesPerSec"`
	TxBytesPerSec   uint64   `json:"txBytesPerSec"`
	RxPacketsPerSec uint64   `json:"rxPacketsPerSec"`
	TxPacketsPerSec uint64   `json:"txPacketsPerSec"`
	IsUp            bool     `json:"isUp"`
	MacAddress      string   `json:"macAddress,omitempty"`
	IPAddresses     []string `json:"ipAddresses,omitempty"`
	SpeedMbps       uint64   `json:"speedMbps,omitempty"`
}

// GPUMetrics represents GPU metrics
type GPUMetrics struct {
	Index           uint32  `json:"index"`
	Name            string  `json:"name"`
	Vendor          string  `json:"vendor"` // NVIDIA, AMD, Intel
	UsagePercent    float64 `json:"usagePercent"`
	MemoryTotal     uint64  `json:"memoryTotal"`
	MemoryUsed      uint64  `json:"memoryUsed"`
	Temperature     float64 `json:"temperature"`
	FanSpeedPercent uint32  `json:"fanSpeedPercent"`
	PowerWatts      uint32  `json:"powerWatts"`
	ClockCoreMHz    uint64  `json:"clockCoreMhz"`
	ClockMemoryMHz  uint64  `json:"clockMemoryMhz"`
	DriverVersion   string  `json:"driverVersion"`
	EncoderUsage    float64 `json:"encoderUsage"`
	DecoderUsage    float64 `json:"decoderUsage"`
}

// NPUMetrics represents NPU/AI accelerator metrics
type NPUMetrics struct {
	Index         uint32  `json:"index"`
	Name          string  `json:"name"`
	Vendor        string  `json:"vendor"` // Intel, Huawei, Qualcomm
	UsagePercent  float64 `json:"usagePercent"`
	MemoryTotal   uint64  `json:"memoryTotal"`
	MemoryUsed    uint64  `json:"memoryUsed"`
	Temperature   float64 `json:"temperature"`
	PowerWatts    uint32  `json:"powerWatts"`
	DriverVersion string  `json:"driverVersion"`
}

// UserSession represents a logged-in user session
type UserSession struct {
	Username    string `json:"username"`
	TTY         string `json:"tty"`
	LoginTime   uint64 `json:"loginTime"`
	RemoteHost  string `json:"remoteHost,omitempty"`
	IdleSeconds uint64 `json:"idleSeconds"`
	SessionType string `json:"sessionType"` // local, ssh, rdp, console
}

// SystemInfo represents system information
type SystemInfo struct {
	OSName            string `json:"osName"`
	OSVersion         string `json:"osVersion"`
	KernelVersion     string `json:"kernelVersion"`
	Hostname          string `json:"hostname"`
	BootTime          uint64 `json:"bootTime"`
	UptimeSeconds     uint64 `json:"uptimeSeconds"`
	MotherboardModel  string `json:"motherboardModel,omitempty"`
	MotherboardVendor string `json:"motherboardVendor,omitempty"`
	BIOSVersion       string `json:"biosVersion,omitempty"`
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
