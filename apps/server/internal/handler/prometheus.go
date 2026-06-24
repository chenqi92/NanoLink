package handler

import (
	"net/http"

	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// MetricsCollector implements prometheus.Collector and exposes the latest
// per-agent metrics held in MetricsService as Prometheus gauges.
type MetricsCollector struct {
	ms *service.MetricsService

	cpuUsage    *prometheus.Desc
	cpuTemp     *prometheus.Desc
	memTotal    *prometheus.Desc
	memUsed     *prometheus.Desc
	diskUsage   *prometheus.Desc
	diskUsed    *prometheus.Desc
	loadAverage *prometheus.Desc
}

// NewMetricsCollector creates a prometheus.Collector backed by the metrics service.
func NewMetricsCollector(ms *service.MetricsService) *MetricsCollector {
	return &MetricsCollector{
		ms: ms,
		cpuUsage: prometheus.NewDesc(
			"nanolink_cpu_usage_percent",
			"Current CPU usage percentage reported by the agent.",
			[]string{"agent_id"}, nil,
		),
		cpuTemp: prometheus.NewDesc(
			"nanolink_cpu_temperature_celsius",
			"Current CPU temperature in degrees Celsius.",
			[]string{"agent_id"}, nil,
		),
		memTotal: prometheus.NewDesc(
			"nanolink_memory_total_bytes",
			"Total physical memory in bytes.",
			[]string{"agent_id"}, nil,
		),
		memUsed: prometheus.NewDesc(
			"nanolink_memory_used_bytes",
			"Used physical memory in bytes.",
			[]string{"agent_id"}, nil,
		),
		diskUsage: prometheus.NewDesc(
			"nanolink_disk_usage_percent",
			"Disk usage percentage per mount point.",
			[]string{"agent_id", "mount_point", "device"}, nil,
		),
		diskUsed: prometheus.NewDesc(
			"nanolink_disk_used_bytes",
			"Used disk space in bytes per mount point.",
			[]string{"agent_id", "mount_point", "device"}, nil,
		),
		loadAverage: prometheus.NewDesc(
			"nanolink_load_average",
			"System load average (1 minute).",
			[]string{"agent_id"}, nil,
		),
	}
}

// Describe implements prometheus.Collector.
func (c *MetricsCollector) Describe(ch chan<- *prometheus.Desc) {
	ch <- c.cpuUsage
	ch <- c.cpuTemp
	ch <- c.memTotal
	ch <- c.memUsed
	ch <- c.diskUsage
	ch <- c.diskUsed
	ch <- c.loadAverage
}

// Collect implements prometheus.Collector. It reads a snapshot of the current
// metrics for every agent and emits one gauge sample per metric.
func (c *MetricsCollector) Collect(ch chan<- prometheus.Metric) {
	if c.ms == nil {
		return
	}

	all := c.ms.GetAllCurrentMetrics()
	for agentID, data := range all {
		if data == nil {
			continue
		}

		ch <- prometheus.MustNewConstMetric(
			c.cpuUsage, prometheus.GaugeValue, data.CPU.UsagePercent, agentID,
		)
		ch <- prometheus.MustNewConstMetric(
			c.cpuTemp, prometheus.GaugeValue, data.CPU.Temperature, agentID,
		)
		ch <- prometheus.MustNewConstMetric(
			c.memTotal, prometheus.GaugeValue, float64(data.Memory.Total), agentID,
		)
		ch <- prometheus.MustNewConstMetric(
			c.memUsed, prometheus.GaugeValue, float64(data.Memory.Used), agentID,
		)

		for _, disk := range data.Disks {
			ch <- prometheus.MustNewConstMetric(
				c.diskUsage, prometheus.GaugeValue, disk.UsagePercent,
				agentID, disk.MountPoint, disk.Device,
			)
			ch <- prometheus.MustNewConstMetric(
				c.diskUsed, prometheus.GaugeValue, float64(disk.Used),
				agentID, disk.MountPoint, disk.Device,
			)
		}

		if len(data.LoadAverage) > 0 {
			ch <- prometheus.MustNewConstMetric(
				c.loadAverage, prometheus.GaugeValue, data.LoadAverage[0], agentID,
			)
		}
	}
}

// NewMetricsPromHandler returns an http.Handler that serves the NanoLink
// metrics in Prometheus text exposition format. It uses a dedicated registry
// so only NanoLink gauges (not the default process/go collectors) are exposed.
func NewMetricsPromHandler(ms *service.MetricsService) http.Handler {
	reg := prometheus.NewRegistry()
	reg.MustRegister(NewMetricsCollector(ms))
	return promhttp.HandlerFor(reg, promhttp.HandlerOpts{})
}
