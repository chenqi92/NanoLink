package database

import (
	"fmt"
	"time"

	"gorm.io/gorm"
)

// MetricsHistory stores raw metrics data (monthly partitioned tables)
// Table naming: metrics_history_2026_01, metrics_history_2026_02, etc.
type MetricsHistory struct {
	ID          uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	AgentID     string    `gorm:"type:varchar(64);index:idx_metrics_agent_time;not null" json:"agentId"`
	Timestamp   time.Time `gorm:"index:idx_metrics_agent_time;index:idx_metrics_timestamp;not null" json:"timestamp"`
	CPUPercent  float64   `json:"cpuPercent"`
	MemPercent  float64   `json:"memPercent"`
	DiskReadPS  uint64    `json:"diskReadPS"`  // bytes per second
	DiskWritePS uint64    `json:"diskWritePS"` // bytes per second
	NetRxPS     uint64    `json:"netRxPS"`     // bytes per second
	NetTxPS     uint64    `json:"netTxPS"`     // bytes per second
	GPUPercent  float64   `json:"gpuPercent"`
	LoadAvg1    float64   `json:"loadAvg1"`
}

// MetricsHourly stores aggregated hourly metrics
type MetricsHourly struct {
	ID         uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	AgentID    string    `gorm:"type:varchar(64);index:idx_hourly_agent_hour;not null" json:"agentId"`
	Hour       time.Time `gorm:"index:idx_hourly_agent_hour;not null" json:"hour"` // Truncated to hour
	CPUAvg     float64   `json:"cpuAvg"`
	CPUMax     float64   `json:"cpuMax"`
	MemAvg     float64   `json:"memAvg"`
	MemMax     float64   `json:"memMax"`
	NetRxTotal uint64    `json:"netRxTotal"` // Total bytes in the hour
	NetTxTotal uint64    `json:"netTxTotal"` // Total bytes in the hour
	DataPoints int       `json:"dataPoints"` // Number of data points aggregated
}

// MetricsDaily stores aggregated daily metrics
type MetricsDaily struct {
	ID         uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	AgentID    string    `gorm:"type:varchar(64);index:idx_daily_agent_day;not null" json:"agentId"`
	Day        time.Time `gorm:"index:idx_daily_agent_day;not null" json:"day"` // Truncated to day
	CPUAvg     float64   `json:"cpuAvg"`
	CPUMax     float64   `json:"cpuMax"`
	MemAvg     float64   `json:"memAvg"`
	MemMax     float64   `json:"memMax"`
	NetRxTotal uint64    `json:"netRxTotal"` // Total bytes in the day
	NetTxTotal uint64    `json:"netTxTotal"` // Total bytes in the day
	DataPoints int       `json:"dataPoints"` // Number of data points aggregated
}

// GetMetricsTableName returns the monthly partitioned table name
func GetMetricsTableName(t time.Time) string {
	return fmt.Sprintf("metrics_history_%04d_%02d", t.Year(), t.Month())
}

// GetCurrentMetricsTableName returns the current month's table name
func GetCurrentMetricsTableName() string {
	return GetMetricsTableName(time.Now())
}

// EnsureMetricsTable ensures the monthly metrics table exists
func EnsureMetricsTable(db *gorm.DB, tableName string) error {
	// Check if table exists
	if db.Migrator().HasTable(tableName) {
		return nil
	}

	// Create table with same schema as MetricsHistory
	return db.Table(tableName).AutoMigrate(&MetricsHistory{})
}

// EnsureCurrentMetricsTable ensures the current month's table exists
func EnsureCurrentMetricsTable(db *gorm.DB) error {
	return EnsureMetricsTable(db, GetCurrentMetricsTableName())
}

// InitMetricsTables initializes aggregation tables and ensures current month table exists
func InitMetricsTables(db *gorm.DB) error {
	// Auto migrate aggregation tables (single tables, not partitioned)
	if err := db.AutoMigrate(&MetricsHourly{}, &MetricsDaily{}); err != nil {
		return fmt.Errorf("failed to migrate metrics aggregation tables: %w", err)
	}

	// Ensure current month's raw metrics table exists
	if err := EnsureCurrentMetricsTable(db); err != nil {
		return fmt.Errorf("failed to create current metrics table: %w", err)
	}

	return nil
}

// CleanupOldMetricsTables removes old monthly tables beyond retention period
func CleanupOldMetricsTables(db *gorm.DB, retentionDays int) error {
	cutoff := time.Now().AddDate(0, 0, -retentionDays)
	cutoffMonth := time.Date(cutoff.Year(), cutoff.Month(), 1, 0, 0, 0, 0, time.Local)

	// Get list of all metrics tables
	var tables []string
	switch db.Dialector.Name() {
	case "sqlite":
		db.Raw("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'metrics_history_%'").Scan(&tables)
	case "mysql":
		db.Raw("SHOW TABLES LIKE 'metrics_history_%'").Scan(&tables)
	case "postgres":
		db.Raw("SELECT tablename FROM pg_tables WHERE tablename LIKE 'metrics_history_%'").Scan(&tables)
	}

	for _, table := range tables {
		// Parse table name to get year and month
		var year, month int
		if _, err := fmt.Sscanf(table, "metrics_history_%d_%d", &year, &month); err != nil {
			continue
		}

		tableMonth := time.Date(year, time.Month(month), 1, 0, 0, 0, 0, time.Local)
		if tableMonth.Before(cutoffMonth) {
			// Drop old table
			if err := db.Migrator().DropTable(table); err != nil {
				return fmt.Errorf("failed to drop old metrics table %s: %w", table, err)
			}
		}
	}

	return nil
}

// CleanupOldAggregatedData removes old aggregated data beyond retention period
func CleanupOldAggregatedData(db *gorm.DB, hourlyRetentionDays, dailyRetentionDays int) error {
	hourlyCutoff := time.Now().AddDate(0, 0, -hourlyRetentionDays)
	dailyCutoff := time.Now().AddDate(0, 0, -dailyRetentionDays)

	// Delete old hourly data
	if err := db.Where("hour < ?", hourlyCutoff).Delete(&MetricsHourly{}).Error; err != nil {
		return fmt.Errorf("failed to cleanup old hourly data: %w", err)
	}

	// Delete old daily data
	if err := db.Where("day < ?", dailyCutoff).Delete(&MetricsDaily{}).Error; err != nil {
		return fmt.Errorf("failed to cleanup old daily data: %w", err)
	}

	return nil
}
