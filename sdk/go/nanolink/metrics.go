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

// MetricsType indicates the type of metrics message
type MetricsType int

const (
	MetricsFull     MetricsType = 0
	MetricsRealtime MetricsType = 1
	MetricsStatic   MetricsType = 2
	MetricsPeriodic MetricsType = 3
)

// DataRequestType indicates what data the server is requesting
type DataRequestType int

const (
	DataRequestFull     DataRequestType = 0
	DataRequestStatic   DataRequestType = 1
	DataRequestPeriodic DataRequestType = 2
)

// DiskIO represents disk I/O metrics for realtime data
type DiskIO struct {
	Device           string `json:"device"`
	ReadBytesPerSec  uint64 `json:"readBytesPerSec"`
	WriteBytesPerSec uint64 `json:"writeBytesPerSec"`
}

// NetworkIO represents network I/O metrics for realtime data
type NetworkIO struct {
	Interface     string `json:"interface"`
	RxBytesPerSec uint64 `json:"rxBytesPerSec"`
	TxBytesPerSec uint64 `json:"txBytesPerSec"`
}

// GPUUsage represents lightweight GPU usage for realtime data
type GPUUsage struct {
	Index        uint32  `json:"index"`
	UsagePercent float64 `json:"usagePercent"`
	MemoryUsed   uint64  `json:"memoryUsed"`
	Temperature  float64 `json:"temperature"`
}

// NPUUsage represents lightweight NPU usage for realtime data
type NPUUsage struct {
	Index        uint32  `json:"index"`
	UsagePercent float64 `json:"usagePercent"`
	MemoryUsed   uint64  `json:"memoryUsed"`
	Temperature  float64 `json:"temperature"`
}

// RealtimeMetrics represents high-frequency metrics (sent every ~1 second)
type RealtimeMetrics struct {
	Timestamp      int64       `json:"timestamp"`
	Hostname       string      `json:"hostname"`
	CPUUsage       float64     `json:"cpuUsage"`
	CPUPerCore     []float64   `json:"cpuPerCore,omitempty"`
	MemoryUsed     uint64      `json:"memoryUsed"`
	MemoryPercent  float64     `json:"memoryPercent"`
	SwapUsed       uint64      `json:"swapUsed"`
	DiskIO         []DiskIO    `json:"diskIo,omitempty"`
	NetworkIO      []NetworkIO `json:"networkIo,omitempty"`
	GPUUsages      []GPUUsage  `json:"gpuUsages,omitempty"`
	NPUUsages      []NPUUsage  `json:"npuUsages,omitempty"`
	LoadAverage    []float64   `json:"loadAverage,omitempty"`
	CPUTemperature float64     `json:"cpuTemperature,omitempty"`
}

// CPUStaticInfo represents static CPU information
type CPUStaticInfo struct {
	Model        string `json:"model"`
	Vendor       string `json:"vendor"`
	Cores        int    `json:"cores"`
	Threads      int    `json:"threads"`
	FrequencyMHz uint64 `json:"frequencyMhz"`
	CacheSize    uint64 `json:"cacheSize"`
	Architecture string `json:"architecture"`
}

// MemoryStaticInfo represents static memory information
type MemoryStaticInfo struct {
	TotalPhysical uint64 `json:"totalPhysical"`
	TotalSwap     uint64 `json:"totalSwap"`
	MemoryType    string `json:"memoryType,omitempty"`
	SpeedMHz      uint32 `json:"speedMhz,omitempty"`
	Slots         uint32 `json:"slots,omitempty"`
}

// DiskStaticInfo represents static disk information
type DiskStaticInfo struct {
	Device     string `json:"device"`
	Model      string `json:"model,omitempty"`
	Serial     string `json:"serial,omitempty"`
	Type       string `json:"type"` // SSD, HDD, NVMe
	Total      uint64 `json:"total"`
	FSType     string `json:"fsType"`
	MountPoint string `json:"mountPoint"`
}

// NetworkStaticInfo represents static network interface information
type NetworkStaticInfo struct {
	Interface  string   `json:"interface"`
	MacAddress string   `json:"macAddress"`
	SpeedMbps  uint64   `json:"speedMbps,omitempty"`
	Type       string   `json:"type,omitempty"` // ethernet, wifi, virtual
	IPAddress  []string `json:"ipAddress,omitempty"`
}

// GPUStaticInfo represents static GPU information
type GPUStaticInfo struct {
	Index          uint32 `json:"index"`
	Name           string `json:"name"`
	Vendor         string `json:"vendor"`
	MemoryTotal    uint64 `json:"memoryTotal"`
	DriverVersion  string `json:"driverVersion"`
	PCIeGeneration uint32 `json:"pcieGeneration,omitempty"`
}

// NPUStaticInfo represents static NPU information
type NPUStaticInfo struct {
	Index         uint32 `json:"index"`
	Name          string `json:"name"`
	Vendor        string `json:"vendor"`
	MemoryTotal   uint64 `json:"memoryTotal"`
	DriverVersion string `json:"driverVersion"`
}

// StaticInfo represents hardware information that rarely changes (sent once on connect)
type StaticInfo struct {
	Timestamp         int64               `json:"timestamp"`
	Hostname          string              `json:"hostname"`
	OSName            string              `json:"osName"`
	OSVersion         string              `json:"osVersion"`
	KernelVersion     string              `json:"kernelVersion"`
	BootTime          uint64              `json:"bootTime"`
	MotherboardModel  string              `json:"motherboardModel,omitempty"`
	MotherboardVendor string              `json:"motherboardVendor,omitempty"`
	BIOSVersion       string              `json:"biosVersion,omitempty"`
	CPU               *CPUStaticInfo      `json:"cpu,omitempty"`
	Memory            *MemoryStaticInfo   `json:"memory,omitempty"`
	Disks             []DiskStaticInfo    `json:"disks,omitempty"`
	Networks          []NetworkStaticInfo `json:"networks,omitempty"`
	GPUs              []GPUStaticInfo     `json:"gpus,omitempty"`
	NPUs              []NPUStaticInfo     `json:"npus,omitempty"`
}

// DiskUsage represents periodic disk usage update
type DiskUsage struct {
	MountPoint string `json:"mountPoint"`
	Used       uint64 `json:"used"`
	Available  uint64 `json:"available"`
}

// NetworkAddressUpdate represents periodic network address update
type NetworkAddressUpdate struct {
	Interface   string   `json:"interface"`
	IPAddresses []string `json:"ipAddresses"`
}

// PeriodicData represents data that changes slowly (sent every 30s-5min)
type PeriodicData struct {
	Timestamp      int64                  `json:"timestamp"`
	Hostname       string                 `json:"hostname"`
	UptimeSeconds  uint64                 `json:"uptimeSeconds"`
	DiskUsage      []DiskUsage            `json:"diskUsage,omitempty"`
	NetworkAddress []NetworkAddressUpdate `json:"networkAddress,omitempty"`
	UserSessions   []UserSession          `json:"userSessions,omitempty"`
}
