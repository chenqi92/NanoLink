// Package storage provides time-series storage backends for metrics data
package storage

import (
	"time"
)

// MetricsPoint represents a single metrics data point
type MetricsPoint struct {
	AgentID   string                 `json:"agentId"`
	Timestamp time.Time              `json:"timestamp"`
	CPU       CPUMetrics             `json:"cpu"`
	Memory    MemoryMetrics          `json:"memory"`
	Disks     []DiskMetrics          `json:"disks,omitempty"`
	Networks  []NetworkMetrics       `json:"networks,omitempty"`
	GPUs      []GPUMetrics           `json:"gpus,omitempty"`
	NPUs      []NPUMetrics           `json:"npus,omitempty"`
	Extra     map[string]interface{} `json:"extra,omitempty"`
}

// CPUMetrics holds CPU metrics
type CPUMetrics struct {
	UsagePercent float64   `json:"usagePercent"`
	Model        string    `json:"model,omitempty"`
	CoreCount    int       `json:"coreCount,omitempty"`
	PerCore      []float64 `json:"perCore,omitempty"`
}

// MemoryMetrics holds memory metrics
type MemoryMetrics struct {
	Total     uint64 `json:"total"`
	Used      uint64 `json:"used"`
	Available uint64 `json:"available"`
}

// DiskMetrics holds disk metrics
type DiskMetrics struct {
	MountPoint       string `json:"mountPoint"`
	Total            uint64 `json:"total"`
	Used             uint64 `json:"used"`
	ReadBytesPerSec  uint64 `json:"readBytesPerSec"`
	WriteBytesPerSec uint64 `json:"writeBytesPerSec"`
}

// NetworkMetrics holds network interface metrics
type NetworkMetrics struct {
	Interface     string `json:"interface"`
	RxBytesPerSec uint64 `json:"rxBytesPerSec"`
	TxBytesPerSec uint64 `json:"txBytesPerSec"`
	IsUp          bool   `json:"isUp"`
}

// GPUMetrics holds GPU metrics
type GPUMetrics struct {
	Name         string  `json:"name"`
	Index        int     `json:"index"`
	UsagePercent float64 `json:"usagePercent"`
	MemoryUsed   uint64  `json:"memoryUsed"`
	MemoryTotal  uint64  `json:"memoryTotal"`
	Temperature  float64 `json:"temperature"`
	PowerWatts   float64 `json:"powerWatts"`
}

// NPUMetrics holds NPU/AI accelerator metrics
type NPUMetrics struct {
	Name         string  `json:"name"`
	Index        int     `json:"index"`
	UsagePercent float64 `json:"usagePercent"`
}

// TimeSeriesStore defines the interface for time-series storage backends
type TimeSeriesStore interface {
	// Write stores a metrics point
	Write(point *MetricsPoint) error

	// Query retrieves metrics for an agent within a time range
	Query(agentID string, start, end time.Time, limit int) ([]*MetricsPoint, error)

	// QueryAll retrieves metrics for all agents within a time range
	QueryAll(start, end time.Time, limit int) (map[string][]*MetricsPoint, error)

	// Delete removes metrics older than the specified time
	Delete(before time.Time) error

	// Close closes the storage connection
	Close() error

	// Name returns the storage backend name
	Name() string
}

// Config holds time-series storage configuration
type Config struct {
	Type          string // "memory", "influxdb", "timescaledb"
	URL           string // Connection URL
	Token         string // InfluxDB token
	Org           string // InfluxDB organization
	Bucket        string // InfluxDB bucket
	Database      string // TimescaleDB database
	Username      string
	Password      string
	RetentionDays int // Data retention in days (0 = unlimited)
	MaxEntries    int // Max entries per agent (for memory store)
}
