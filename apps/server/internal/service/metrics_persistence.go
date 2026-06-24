package service

import (
	"fmt"
	"sync"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/config"
	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"go.uber.org/zap"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// MetricsPersistence handles metrics data persistence to database
type MetricsPersistence struct {
	db                *gorm.DB
	cfg               config.MetricsConfig
	logger            *zap.SugaredLogger
	tableMu                sync.Mutex
	maintenanceMu          sync.Mutex
	currentTable           string
	aggregationTicker      *time.Ticker
	dailyAggregationTicker *time.Ticker
	cleanupTicker          *time.Ticker
	stopChan               chan struct{}
}

// NewMetricsPersistence creates a new metrics persistence service
func NewMetricsPersistence(db *gorm.DB, cfg config.MetricsConfig, logger *zap.SugaredLogger) *MetricsPersistence {
	mp := &MetricsPersistence{
		db:           db,
		cfg:          cfg,
		logger:       logger,
		currentTable: database.GetCurrentMetricsTableName(),
		stopChan:     make(chan struct{}),
	}

	// Initialize tables
	if err := database.InitMetricsTables(db); err != nil {
		logger.Errorf("Failed to initialize metrics tables: %v", err)
	}

	return mp
}

// Start starts background tasks for aggregation and cleanup
func (mp *MetricsPersistence) Start() {
	// Run hourly aggregation every hour
	mp.aggregationTicker = time.NewTicker(1 * time.Hour)
	// Roll hourly rows up into daily rows every day
	mp.dailyAggregationTicker = time.NewTicker(24 * time.Hour)
	// Run cleanup every day
	mp.cleanupTicker = time.NewTicker(24 * time.Hour)

	go func() {
		for {
			select {
			case <-mp.aggregationTicker.C:
				mp.runHourlyAggregation()
			case <-mp.dailyAggregationTicker.C:
				mp.runDailyAggregation()
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
	if mp.dailyAggregationTicker != nil {
		mp.dailyAggregationTicker.Stop()
	}
	if mp.cleanupTicker != nil {
		mp.cleanupTicker.Stop()
	}
	mp.logger.Info("Metrics persistence stopped")
}

// SaveMetrics saves a metrics snapshot to the database
func (mp *MetricsPersistence) SaveMetrics(agentID string, data *MetricsData) error {
	if !mp.cfg.PersistToDB || data == nil {
		return nil
	}

	tableName, err := mp.ensureMetricsTable(data.Timestamp)
	if err != nil {
		return err
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
//
// For coarse buckets it reads the pre-computed aggregate tables instead of
// rescanning raw partitions: 1h buckets are served from MetricsHourly and
// 1d/multi-day buckets from MetricsDaily. Fine buckets (<=15m) still scan and
// bucket the raw data.
func (mp *MetricsPersistence) QueryAggregated(agentID string, start, end time.Time, interval string) ([]database.MetricsHistory, error) {
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

	// Coarse buckets: serve from aggregate tables to avoid rescanning raw data.
	switch {
	case bucketDuration >= 24*time.Hour:
		return mp.queryDailyAggregated(agentID, start, end)
	case bucketDuration >= time.Hour:
		return mp.queryHourlyAggregated(agentID, start, end)
	}

	// Fine buckets (<=15m): scan and bucket the raw data.
	raw, err := mp.QueryHistory(agentID, start, end, 0)
	if err != nil {
		return nil, err
	}
	if len(raw) == 0 {
		return raw, nil
	}
	return mp.aggregateData(raw, bucketDuration), nil
}

// queryHourlyAggregated reads pre-computed hourly rows for the range and maps
// them into the MetricsHistory shape. The DTO has no Max/Total fields, so only
// the *Avg values (and per-hour net totals) are surfaced; Max values are
// dropped (see report notes).
func (mp *MetricsPersistence) queryHourlyAggregated(agentID string, start, end time.Time) ([]database.MetricsHistory, error) {
	var rows []database.MetricsHourly
	if err := mp.db.
		Where("agent_id = ? AND hour >= ? AND hour <= ?", agentID, start, end).
		Order("hour ASC").
		Find(&rows).Error; err != nil {
		return nil, err
	}

	results := make([]database.MetricsHistory, 0, len(rows))
	for _, r := range rows {
		results = append(results, database.MetricsHistory{
			AgentID:    r.AgentID,
			Timestamp:  r.Hour,
			CPUPercent: r.CPUAvg,
			MemPercent: r.MemAvg,
			NetRxPS:    r.NetRxTotal,
			NetTxPS:    r.NetTxTotal,
		})
	}
	return results, nil
}

// queryDailyAggregated reads pre-computed daily rows for the range and maps
// them into the MetricsHistory shape (Avg values only; see report notes).
func (mp *MetricsPersistence) queryDailyAggregated(agentID string, start, end time.Time) ([]database.MetricsHistory, error) {
	var rows []database.MetricsDaily
	if err := mp.db.
		Where("agent_id = ? AND day >= ? AND day <= ?", agentID, start, end).
		Order("day ASC").
		Find(&rows).Error; err != nil {
		return nil, err
	}

	results := make([]database.MetricsHistory, 0, len(rows))
	for _, r := range rows {
		results = append(results, database.MetricsHistory{
			AgentID:    r.AgentID,
			Timestamp:  r.Day,
			CPUPercent: r.CPUAvg,
			MemPercent: r.MemAvg,
			NetRxPS:    r.NetRxTotal,
			NetTxPS:    r.NetTxTotal,
		})
	}
	return results, nil
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
	mp.maintenanceMu.Lock()
	defer mp.maintenanceMu.Unlock()

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

// runDailyAggregation rolls the previous day's hourly rows (falling back to raw
// data) into one MetricsDaily row per agent. It is restart-safe: a day that was
// already aggregated is skipped via a pre-check on the agent+day key.
func (mp *MetricsPersistence) runDailyAggregation() {
	mp.maintenanceMu.Lock()
	defer mp.maintenanceMu.Unlock()

	now := time.Now()
	// Previous calendar day in local time.
	startOfToday := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.Local)
	day := startOfToday.AddDate(0, 0, -1)
	endDay := startOfToday

	// Prefer hourly rows for the day to avoid rescanning raw partitions.
	var hourly []database.MetricsHourly
	if err := mp.db.Where("hour >= ? AND hour < ?", day, endDay).
		Order("agent_id ASC, hour ASC").
		Find(&hourly).Error; err != nil {
		mp.logger.Warnf("Daily aggregation: failed to read hourly rows: %v", err)
	}

	// Group hourly rows per agent.
	type dailyAcc struct {
		cpuAvgSum  float64
		memAvgSum  float64
		cpuMax     float64
		memMax     float64
		netRxTotal uint64
		netTxTotal uint64
		dataPoints int
		buckets    int
	}
	accs := make(map[string]*dailyAcc)
	for _, h := range hourly {
		acc, ok := accs[h.AgentID]
		if !ok {
			acc = &dailyAcc{}
			accs[h.AgentID] = acc
		}
		acc.cpuAvgSum += h.CPUAvg
		acc.memAvgSum += h.MemAvg
		if h.CPUMax > acc.cpuMax {
			acc.cpuMax = h.CPUMax
		}
		if h.MemMax > acc.memMax {
			acc.memMax = h.MemMax
		}
		acc.netRxTotal += h.NetRxTotal
		acc.netTxTotal += h.NetTxTotal
		acc.dataPoints += h.DataPoints
		acc.buckets++
	}

	// Agents that have raw data for the day but no hourly rows (e.g. hourly
	// aggregation never ran) fall back to scanning the raw partitions.
	for _, agentID := range mp.getAgentsWithData(day, endDay) {
		if _, ok := accs[agentID]; ok {
			continue
		}
		raw, err := mp.QueryHistory(agentID, day, endDay, 0)
		if err != nil || len(raw) == 0 {
			continue
		}
		acc := &dailyAcc{}
		for _, m := range raw {
			acc.cpuAvgSum += m.CPUPercent
			acc.memAvgSum += m.MemPercent
			if m.CPUPercent > acc.cpuMax {
				acc.cpuMax = m.CPUPercent
			}
			if m.MemPercent > acc.memMax {
				acc.memMax = m.MemPercent
			}
			acc.netRxTotal += m.NetRxPS
			acc.netTxTotal += m.NetTxPS
			acc.buckets++
		}
		acc.dataPoints = len(raw)
		accs[agentID] = acc
	}

	written := 0
	for agentID, acc := range accs {
		if acc.buckets == 0 {
			continue
		}

		// Restart safety: skip if this agent+day was already aggregated.
		var existing int64
		mp.db.Model(&database.MetricsDaily{}).
			Where("agent_id = ? AND day = ?", agentID, day).
			Count(&existing)
		if existing > 0 {
			continue
		}

		daily := database.MetricsDaily{
			AgentID:    agentID,
			Day:        day,
			CPUAvg:     acc.cpuAvgSum / float64(acc.buckets),
			CPUMax:     acc.cpuMax,
			MemAvg:     acc.memAvgSum / float64(acc.buckets),
			MemMax:     acc.memMax,
			NetRxTotal: acc.netRxTotal,
			NetTxTotal: acc.netTxTotal,
			DataPoints: acc.dataPoints,
		}

		// Use OnConflict as a second line of defense when a unique index on
		// (agent_id, day) exists; harmless otherwise.
		if err := mp.db.Clauses(clause.OnConflict{DoNothing: true}).Create(&daily).Error; err != nil {
			mp.logger.Warnf("Failed to save daily aggregation for %s: %v", agentID, err)
			continue
		}
		written++
	}

	mp.logger.Infof("Daily aggregation completed for %d agents", written)
}

// runCleanup removes old data
func (mp *MetricsPersistence) runCleanup() {
	mp.maintenanceMu.Lock()
	defer mp.maintenanceMu.Unlock()

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

func (mp *MetricsPersistence) ensureMetricsTable(ts time.Time) (string, error) {
	tableName := database.GetMetricsTableName(ts)

	// The cached-table check must happen under the lock: a lock-free read of
	// mp.currentTable races with the write below (data race / torn read).
	mp.tableMu.Lock()
	defer mp.tableMu.Unlock()

	if mp.currentTable == tableName {
		return tableName, nil
	}

	if err := database.EnsureMetricsTable(mp.db, tableName); err != nil {
		return "", fmt.Errorf("failed to ensure metrics table: %w", err)
	}

	mp.currentTable = tableName
	return tableName, nil
}
