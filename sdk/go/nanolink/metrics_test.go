package nanolink

import (
	"testing"
)

func TestMemoryUsagePercent(t *testing.T) {
	tests := []struct {
		name     string
		metrics  MemoryMetrics
		expected float64
	}{
		{
			name:     "50% usage",
			metrics:  MemoryMetrics{Total: 100, Used: 50},
			expected: 50.0,
		},
		{
			name:     "0% usage",
			metrics:  MemoryMetrics{Total: 100, Used: 0},
			expected: 0.0,
		},
		{
			name:     "100% usage",
			metrics:  MemoryMetrics{Total: 100, Used: 100},
			expected: 100.0,
		},
		{
			name:     "zero total",
			metrics:  MemoryMetrics{Total: 0, Used: 50},
			expected: 0.0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := tt.metrics.UsagePercent()
			if result != tt.expected {
				t.Errorf("Expected %.2f, got %.2f", tt.expected, result)
			}
		})
	}
}

func TestDiskUsagePercent(t *testing.T) {
	tests := []struct {
		name     string
		metrics  DiskMetrics
		expected float64
	}{
		{
			name:     "50% usage",
			metrics:  DiskMetrics{Total: 1000, Used: 500},
			expected: 50.0,
		},
		{
			name:     "0% usage",
			metrics:  DiskMetrics{Total: 1000, Used: 0},
			expected: 0.0,
		},
		{
			name:     "100% usage",
			metrics:  DiskMetrics{Total: 1000, Used: 1000},
			expected: 100.0,
		},
		{
			name:     "zero total",
			metrics:  DiskMetrics{Total: 0, Used: 500},
			expected: 0.0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := tt.metrics.UsagePercent()
			if result != tt.expected {
				t.Errorf("Expected %.2f, got %.2f", tt.expected, result)
			}
		})
	}
}

func TestMetricsStructure(t *testing.T) {
	metrics := Metrics{
		Timestamp: 1234567890,
		Hostname:  "test-host",
		CPU: &CPUMetrics{
			UsagePercent: 45.5,
			CoreCount:    8,
			PerCoreUsage: []float64{40.0, 50.0, 45.0, 42.0, 48.0, 44.0, 46.0, 43.0},
		},
		Memory: &MemoryMetrics{
			Total:     16000000000,
			Used:      8000000000,
			Available: 8000000000,
			SwapTotal: 8000000000,
			SwapUsed:  1000000000,
		},
		Disks: []DiskMetrics{
			{
				MountPoint: "/",
				Device:     "/dev/sda1",
				FSType:     "ext4",
				Total:      500000000000,
				Used:       250000000000,
				Available:  250000000000,
			},
		},
		Networks: []NetworkMetrics{
			{
				Interface:     "eth0",
				RxBytesPerSec: 1000000,
				TxBytesPerSec: 500000,
				IsUp:          true,
			},
		},
		LoadAverage: []float64{1.5, 2.0, 1.8},
	}

	if metrics.Hostname != "test-host" {
		t.Errorf("Expected hostname 'test-host', got '%s'", metrics.Hostname)
	}

	if metrics.CPU.CoreCount != 8 {
		t.Errorf("Expected 8 cores, got %d", metrics.CPU.CoreCount)
	}

	if len(metrics.Disks) != 1 {
		t.Errorf("Expected 1 disk, got %d", len(metrics.Disks))
	}

	if len(metrics.Networks) != 1 {
		t.Errorf("Expected 1 network, got %d", len(metrics.Networks))
	}

	if len(metrics.LoadAverage) != 3 {
		t.Errorf("Expected 3 load averages, got %d", len(metrics.LoadAverage))
	}
}

func TestCPUMetrics(t *testing.T) {
	cpu := CPUMetrics{
		UsagePercent: 75.5,
		CoreCount:    4,
		PerCoreUsage: []float64{70.0, 80.0, 75.0, 77.0},
	}

	if cpu.UsagePercent != 75.5 {
		t.Errorf("Expected usage 75.5, got %.2f", cpu.UsagePercent)
	}

	if len(cpu.PerCoreUsage) != cpu.CoreCount {
		t.Errorf("Expected %d per-core values, got %d", cpu.CoreCount, len(cpu.PerCoreUsage))
	}
}

func TestProcessInfo(t *testing.T) {
	proc := ProcessInfo{
		PID:         1234,
		Name:        "test-process",
		User:        "root",
		CPUPercent:  10.5,
		MemoryBytes: 104857600,
		Status:      "running",
		StartTime:   1234567890,
	}

	if proc.PID != 1234 {
		t.Errorf("Expected PID 1234, got %d", proc.PID)
	}

	if proc.Name != "test-process" {
		t.Errorf("Expected name 'test-process', got '%s'", proc.Name)
	}
}

func TestContainerInfo(t *testing.T) {
	container := ContainerInfo{
		ID:      "abc123",
		Name:    "my-container",
		Image:   "nginx:latest",
		Status:  "Up 2 hours",
		State:   "running",
		Created: 1234567890,
	}

	if container.ID != "abc123" {
		t.Errorf("Expected ID 'abc123', got '%s'", container.ID)
	}

	if container.State != "running" {
		t.Errorf("Expected state 'running', got '%s'", container.State)
	}
}

func TestNetworkMetrics(t *testing.T) {
	network := NetworkMetrics{
		Interface:       "eth0",
		RxBytesPerSec:   1048576,
		TxBytesPerSec:   524288,
		RxPacketsPerSec: 1000,
		TxPacketsPerSec: 500,
		IsUp:            true,
	}

	if !network.IsUp {
		t.Error("Expected network to be up")
	}

	if network.RxBytesPerSec != 1048576 {
		t.Errorf("Expected RxBytesPerSec 1048576, got %d", network.RxBytesPerSec)
	}
}
