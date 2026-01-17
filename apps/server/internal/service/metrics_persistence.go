package service

import (
	"fmt"
	"sync"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/config"
	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// MetricsPersistence handles metrics data persistence to database
type MetricsPersistence struct {
	db                *gorm.DB
	cfg               config.MetricsConfig
	logger            *zap.SugaredLogger
	mu                sync.Mutex
	aggregationTicker *time.Ticker
	cleanupTicker     *time.Ticker
	stopChan          chan struct{}
}

// NewMetricsPersistence creates a new metrics persistence service
func NewMetricsPersistence(db *gorm.DB, cfg config.MetricsConfig, logger *zap.SugaredLogger) *MetricsPersistence {
	mp := &MetricsPersistence{
		db:       db,
		cfg:      cfg,
		logger:   logger,
		stopChan: make(chan struct{}),
	}

	// Initialize tables
	if err := database.InitMetricsTables(db); err != nil {
		logger.Errorf("Failed to initialize metrics tables: %v", err)
	}

	return mp
}

// Start starts background tasks for aggregation and cleanup
func (mp *MetricsPersistence) Start() {
	// Run aggregation every hour
	mp.aggregationTicker = time.NewTicker(1 * time.Hour)
	// Run cleanup every day
	mp.cleanupTicker = time.NewTicker(24 * time.Hour)

	go func() {
		for {
			select {
			case <-mp.aggregationTicker.C:
				mp.runHourlyAggregation()
			case <-mp.cleanupTicker.C:
				mp.runCleanup()
			case <-mp.stopChan:
				return
			}
		}
	}()

	mp.logger.Info("Metrics persistence background tasks started")
}

// Stop stops background tasks
func (mp *MetricsPersistence) Stop() {
	close(mp.stopChan)
	if mp.aggregationTicker != nil {
		mp.aggregationTicker.Stop()
	}
	if mp.cleanupTicker != nil {
		mp.cleanupTicker.Stop()
	}
	mp.logger.Info("Metrics persistence stopped")
}

// SaveMetrics saves a metrics snapshot to the database
func (mp *MetricsPersistence) SaveMetrics(agentID string, data *MetricsData) error {
	if !mp.cfg.PersistToDB {
		return nil
	}

	mp.mu.Lock()
	defer mp.mu.Unlock()

	// Ensure current month's table exists
	tableName := database.GetCurrentMetricsTableName()
	if err := database.EnsureMetricsTable(mp.db, tableName); err != nil {
		return fmt.Errorf("failed to ensure metrics table: %w", err)
	}

	// Calculate aggregated values
	var diskReadPS, diskWritePS, netRxPS, netTxPS uint64
	var gpuPercent float64

	for _, d := range data.Disks {
		diskReadPS += d.ReadBytesPS
		diskWritePS += d.WriteBytesPS
	}

	for _, n := range data.Networks {
		netRxPS += n.RxBytesPS
		netTxPS += n.TxBytesPS
	}

	if len(data.GPUs) > 0 {
		var total float64
		for _, g := range data.GPUs {
			total += g.UsagePercent
		}
		gpuPercent = total / float64(len(data.GPUs))
	}

	memPercent := 0.0
	if data.Memory.Total > 0 {
		memPercent = float64(data.Memory.Used) / float64(data.Memory.Total) * 100
	}

	loadAvg1 := 0.0
	if len(data.LoadAverage) > 0 {
		loadAvg1 = data.LoadAverage[0]
	}

	record := database.MetricsHistory{
		AgentID:     agentID,
		Timestamp:   data.Timestamp,
		CPUPercent:  data.CPU.UsagePercent,
		MemPercent:  memPercent,
		DiskReadPS:  diskReadPS,
		DiskWritePS: diskWritePS,
		NetRxPS:     netRxPS,
		NetTxPS:     netTxPS,
		GPUPercent:  gpuPercent,
		LoadAvg1:    loadAvg1,
	}

	return mp.db.Table(tableName).Create(&record).Error
}

// QueryHistory queries historical metrics for an agent within a time range
func (mp *MetricsPersistence) QueryHistory(agentID string, start, end time.Time, limit int) ([]database.MetricsHistory, error) {
	var results []database.MetricsHistory

	// Determine which monthly tables to query
	tables := mp.getTablesForRange(start, end)

	for _, table := range tables {
		if !mp.db.Migrator().HasTable(table) {
			continue
		}

		var partial []database.MetricsHistory
		query := mp.db.Table(table).
			Where("agent_id = ? AND timestamp >= ? AND timestamp <= ?", agentID, start, end).
			Order("timestamp ASC")

		if limit > 0 {
			query = query.Limit(limit)
		}

		if err := query.Find(&partial).Error; err != nil {
			mp.logger.Warnf("Error querying table %s: %v", table, err)
			continue
		}

		results = append(results, partial...)
	}

	return results, nil
}

// QueryAggregated queries aggregated metrics with specified interval
// interval: "1m", "5m", "1h", "1d"
func (mp *MetricsPersistence) QueryAggregated(agentID string, start, end time.Time, interval string) ([]database.MetricsHistory, error) {
	raw, err := mp.QueryHistory(agentID, start, end, 0)
	if err != nil {
		return nil, err
	}

	if len(raw) == 0 {
		return raw, nil
	}

	// Determine bucket duration
	var bucketDuration time.Duration
	switch interval {
	case "1m":
		bucketDuration = time.Minute
	case "5m":
		bucketDuration = 5 * time.Minute
	case "1h":
		bucketDuration = time.Hour
	case "1d":
		bucketDuration = 24 * time.Hour
	default:
		// Auto-determine based on range
		rangeDuration := end.Sub(start)
		switch {
		case rangeDuration <= time.Hour:
			bucketDuration = time.Minute
		case rangeDuration <= 6*time.Hour:
			bucketDuration = 5 * time.Minute
		case rangeDuration <= 24*time.Hour:
			bucketDuration = 15 * time.Minute
		case rangeDuration <= 7*24*time.Hour:
			bucketDuration = time.Hour
		default:
			bucketDuration = 24 * time.Hour
		}
	}

	return mp.aggregateData(raw, bucketDuration), nil
}

// aggregateData aggregates raw metrics into buckets
func (mp *MetricsPersistence) aggregateData(raw []database.MetricsHistory, bucketDuration time.Duration) []database.MetricsHistory {
	if len(raw) == 0 {
		return raw
	}

	buckets := make(map[int64]*aggregationBucket)

	for _, m := range raw {
		bucketKey := m.Timestamp.Truncate(bucketDuration).Unix()
		bucket, exists := buckets[bucketKey]
		if !exists {
			bucket = &aggregationBucket{
				timestamp: time.Unix(bucketKey, 0),
			}
			buckets[bucketKey] = bucket
		}
		bucket.add(m)
	}

	// Convert buckets to results
	results := make([]database.MetricsHistory, 0, len(buckets))
	for _, bucket := range buckets {
		results = append(results, bucket.toMetrics())
	}

	// Sort by timestamp
	for i := 0; i < len(results)-1; i++ {
		for j := i + 1; j < len(results); j++ {
			if results[i].Timestamp.After(results[j].Timestamp) {
				results[i], results[j] = results[j], results[i]
			}
		}
	}

	return results
}

type aggregationBucket struct {
	timestamp    time.Time
	cpuSum       float64
	memSum       float64
	diskReadSum  uint64
	diskWriteSum uint64
	netRxSum     uint64
	netTxSum     uint64
	gpuSum       float64
	loadSum      float64
	count        int
}

func (b *aggregationBucket) add(m database.MetricsHistory) {
	b.cpuSum += m.CPUPercent
	b.memSum += m.MemPercent
	b.diskReadSum += m.DiskReadPS
	b.diskWriteSum += m.DiskWritePS
	b.netRxSum += m.NetRxPS
	b.netTxSum += m.NetTxPS
	b.gpuSum += m.GPUPercent
	b.loadSum += m.LoadAvg1
	b.count++
}

func (b *aggregationBucket) toMetrics() database.MetricsHistory {
	if b.count == 0 {
		return database.MetricsHistory{Timestamp: b.timestamp}
	}
	return database.MetricsHistory{
		Timestamp:   b.timestamp,
		CPUPercent:  b.cpuSum / float64(b.count),
		MemPercent:  b.memSum / float64(b.count),
		DiskReadPS:  b.diskReadSum / uint64(b.count),
		DiskWritePS: b.diskWriteSum / uint64(b.count),
		NetRxPS:     b.netRxSum / uint64(b.count),
		NetTxPS:     b.netTxSum / uint64(b.count),
		GPUPercent:  b.gpuSum / float64(b.count),
		LoadAvg1:    b.loadSum / float64(b.count),
	}
}

// getTablesForRange returns the table names that cover the given time range
func (mp *MetricsPersistence) getTablesForRange(start, end time.Time) []string {
	var tables []string
	current := time.Date(start.Year(), start.Month(), 1, 0, 0, 0, 0, time.Local)
	endMonth := time.Date(end.Year(), end.Month(), 1, 0, 0, 0, 0, time.Local)

	for !current.After(endMonth) {
		tables = append(tables, database.GetMetricsTableName(current))
		current = current.AddDate(0, 1, 0)
	}

	return tables
}

// runHourlyAggregation aggregates the last hour's data
func (mp *MetricsPersistence) runHourlyAggregation() {
	mp.mu.Lock()
	defer mp.mu.Unlock()

	now := time.Now()
	hour := now.Truncate(time.Hour).Add(-time.Hour) // Previous hour
	endHour := hour.Add(time.Hour)

	// Get all agents with data in the last hour
	agentIDs := mp.getAgentsWithData(hour, endHour)

	for _, agentID := range agentIDs {
		raw, err := mp.QueryHistory(agentID, hour, endHour, 0)
		if err != nil || len(raw) == 0 {
			continue
		}

		// Calculate aggregates
		var cpuSum, memSum, gpuSum float64
		var cpuMax, memMax float64
		var netRxTotal, netTxTotal uint64

		for _, m := range raw {
			cpuSum += m.CPUPercent
			memSum += m.MemPercent
			gpuSum += m.GPUPercent
			netRxTotal += m.NetRxPS
			netTxTotal += m.NetTxPS

			if m.CPUPercent > cpuMax {
				cpuMax = m.CPUPercent
			}
			if m.MemPercent > memMax {
				memMax = m.MemPercent
			}
		}

		count := len(raw)
		hourly := database.MetricsHourly{
			AgentID:    agentID,
			Hour:       hour,
			CPUAvg:     cpuSum / float64(count),
			CPUMax:     cpuMax,
			MemAvg:     memSum / float64(count),
			MemMax:     memMax,
			NetRxTotal: netRxTotal,
			NetTxTotal: netTxTotal,
			DataPoints: count,
		}

		if err := mp.db.Create(&hourly).Error; err != nil {
			mp.logger.Warnf("Failed to save hourly aggregation for %s: %v", agentID, err)
		}
	}

	mp.logger.Infof("Hourly aggregation completed for %d agents", len(agentIDs))
}

// runCleanup removes old data
func (mp *MetricsPersistence) runCleanup() {
	mp.mu.Lock()
	defer mp.mu.Unlock()

	// Cleanup old monthly tables
	if err := database.CleanupOldMetricsTables(mp.db, mp.cfg.RetentionDays); err != nil {
		mp.logger.Errorf("Failed to cleanup old metrics tables: %v", err)
	}

	// Cleanup old aggregated data
	if err := database.CleanupOldAggregatedData(mp.db, mp.cfg.HourlyRetentionDays, mp.cfg.DailyRetentionDays); err != nil {
		mp.logger.Errorf("Failed to cleanup old aggregated data: %v", err)
	}

	mp.logger.Info("Metrics cleanup completed")
}

// getAgentsWithData returns agent IDs that have data in the given time range
func (mp *MetricsPersistence) getAgentsWithData(start, end time.Time) []string {
	var agentIDs []string
	tables := mp.getTablesForRange(start, end)

	for _, table := range tables {
		if !mp.db.Migrator().HasTable(table) {
			continue
		}

		var ids []string
		mp.db.Table(table).
			Where("timestamp >= ? AND timestamp <= ?", start, end).
			Distinct("agent_id").
			Pluck("agent_id", &ids)

		for _, id := range ids {
			found := false
			for _, existing := range agentIDs {
				if existing == id {
					found = true
					break
				}
			}
			if !found {
				agentIDs = append(agentIDs, id)
			}
		}
	}

	return agentIDs
}
