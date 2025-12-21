package storage

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	_ "github.com/lib/pq"
)

// TimescaleDBStore is a TimescaleDB time-series store
type TimescaleDBStore struct {
	db *sql.DB
}

// NewTimescaleDBStore creates a new TimescaleDB store
func NewTimescaleDBStore(cfg Config) (*TimescaleDBStore, error) {
	if cfg.URL == "" && cfg.Database == "" {
		return nil, fmt.Errorf("timescaledb: URL or database is required")
	}

	var dsn string
	if cfg.URL != "" {
		dsn = cfg.URL
	} else {
		host := cfg.URL
		if host == "" {
			host = "localhost"
		}
		port := 5432
		dsn = fmt.Sprintf(
			"host=%s port=%d user=%s password=%s dbname=%s sslmode=disable",
			host, port, cfg.Username, cfg.Password, cfg.Database,
		)
	}

	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, fmt.Errorf("timescaledb: failed to open connection: %w", err)
	}

	// Verify connection
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		db.Close()
		return nil, fmt.Errorf("timescaledb: failed to connect: %w", err)
	}

	store := &TimescaleDBStore{db: db}

	// Initialize schema
	if err := store.initSchema(); err != nil {
		db.Close()
		return nil, fmt.Errorf("timescaledb: failed to init schema: %w", err)
	}

	return store, nil
}

// initSchema creates the metrics tables with TimescaleDB hypertables
func (s *TimescaleDBStore) initSchema() error {
	ctx := context.Background()

	// Create metrics table
	_, err := s.db.ExecContext(ctx, `
		CREATE TABLE IF NOT EXISTS metrics (
			time        TIMESTAMPTZ NOT NULL,
			agent_id    TEXT NOT NULL,
			cpu_percent DOUBLE PRECISION,
			mem_total   BIGINT,
			mem_used    BIGINT,
			PRIMARY KEY (time, agent_id)
		)
	`)
	if err != nil {
		return err
	}

	// Try to create hypertable (will fail silently if already exists or TimescaleDB not installed)
	_, _ = s.db.ExecContext(ctx, `
		SELECT create_hypertable('metrics', 'time', if_not_exists => TRUE)
	`)

	// Create disk metrics table
	_, err = s.db.ExecContext(ctx, `
		CREATE TABLE IF NOT EXISTS disk_metrics (
			time         TIMESTAMPTZ NOT NULL,
			agent_id     TEXT NOT NULL,
			mount_point  TEXT NOT NULL,
			total        BIGINT,
			used         BIGINT,
			read_bps     BIGINT,
			write_bps    BIGINT,
			PRIMARY KEY (time, agent_id, mount_point)
		)
	`)
	if err != nil {
		return err
	}
	_, _ = s.db.ExecContext(ctx, `SELECT create_hypertable('disk_metrics', 'time', if_not_exists => TRUE)`)

	// Create network metrics table
	_, err = s.db.ExecContext(ctx, `
		CREATE TABLE IF NOT EXISTS network_metrics (
			time        TIMESTAMPTZ NOT NULL,
			agent_id    TEXT NOT NULL,
			interface   TEXT NOT NULL,
			rx_bps      BIGINT,
			tx_bps      BIGINT,
			is_up       BOOLEAN,
			PRIMARY KEY (time, agent_id, interface)
		)
	`)
	if err != nil {
		return err
	}
	_, _ = s.db.ExecContext(ctx, `SELECT create_hypertable('network_metrics', 'time', if_not_exists => TRUE)`)

	return nil
}

// Write stores a metrics point
func (s *TimescaleDBStore) Write(point *MetricsPoint) error {
	ctx := context.Background()

	// Insert main metrics
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO metrics (time, agent_id, cpu_percent, mem_total, mem_used)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (time, agent_id) DO UPDATE SET
			cpu_percent = EXCLUDED.cpu_percent,
			mem_total = EXCLUDED.mem_total,
			mem_used = EXCLUDED.mem_used
	`, point.Timestamp, point.AgentID, point.CPU.UsagePercent, point.Memory.Total, point.Memory.Used)
	if err != nil {
		return fmt.Errorf("timescaledb: failed to write metrics: %w", err)
	}

	// Insert disk metrics
	for _, disk := range point.Disks {
		_, err := s.db.ExecContext(ctx, `
			INSERT INTO disk_metrics (time, agent_id, mount_point, total, used, read_bps, write_bps)
			VALUES ($1, $2, $3, $4, $5, $6, $7)
			ON CONFLICT (time, agent_id, mount_point) DO UPDATE SET
				total = EXCLUDED.total,
				used = EXCLUDED.used,
				read_bps = EXCLUDED.read_bps,
				write_bps = EXCLUDED.write_bps
		`, point.Timestamp, point.AgentID, disk.MountPoint, disk.Total, disk.Used, disk.ReadBytesPerSec, disk.WriteBytesPerSec)
		if err != nil {
			return fmt.Errorf("timescaledb: failed to write disk metrics: %w", err)
		}
	}

	// Insert network metrics
	for _, net := range point.Networks {
		_, err := s.db.ExecContext(ctx, `
			INSERT INTO network_metrics (time, agent_id, interface, rx_bps, tx_bps, is_up)
			VALUES ($1, $2, $3, $4, $5, $6)
			ON CONFLICT (time, agent_id, interface) DO UPDATE SET
				rx_bps = EXCLUDED.rx_bps,
				tx_bps = EXCLUDED.tx_bps,
				is_up = EXCLUDED.is_up
		`, point.Timestamp, point.AgentID, net.Interface, net.RxBytesPerSec, net.TxBytesPerSec, net.IsUp)
		if err != nil {
			return fmt.Errorf("timescaledb: failed to write network metrics: %w", err)
		}
	}

	return nil
}

// Query retrieves metrics for an agent within a time range
func (s *TimescaleDBStore) Query(agentID string, start, end time.Time, limit int) ([]*MetricsPoint, error) {
	ctx := context.Background()

	if start.IsZero() {
		start = time.Now().Add(-10 * time.Minute)
	}
	if end.IsZero() {
		end = time.Now()
	}
	if limit <= 0 {
		limit = 600
	}

	rows, err := s.db.QueryContext(ctx, `
		SELECT time, cpu_percent, mem_total, mem_used
		FROM metrics
		WHERE agent_id = $1 AND time >= $2 AND time <= $3
		ORDER BY time DESC
		LIMIT $4
	`, agentID, start, end, limit)
	if err != nil {
		return nil, fmt.Errorf("timescaledb: query failed: %w", err)
	}
	defer rows.Close()

	var points []*MetricsPoint
	for rows.Next() {
		var t time.Time
		var cpuPercent float64
		var memTotal, memUsed int64

		if err := rows.Scan(&t, &cpuPercent, &memTotal, &memUsed); err != nil {
			return nil, fmt.Errorf("timescaledb: scan failed: %w", err)
		}

		points = append(points, &MetricsPoint{
			AgentID:   agentID,
			Timestamp: t,
			CPU:       CPUMetrics{UsagePercent: cpuPercent},
			Memory:    MemoryMetrics{Total: uint64(memTotal), Used: uint64(memUsed)},
		})
	}

	// Reverse to chronological order
	for i, j := 0, len(points)-1; i < j; i, j = i+1, j-1 {
		points[i], points[j] = points[j], points[i]
	}

	return points, nil
}

// QueryAll retrieves metrics for all agents within a time range
func (s *TimescaleDBStore) QueryAll(start, end time.Time, limit int) (map[string][]*MetricsPoint, error) {
	ctx := context.Background()

	// Get unique agent IDs
	rows, err := s.db.QueryContext(ctx, `SELECT DISTINCT agent_id FROM metrics`)
	if err != nil {
		return nil, fmt.Errorf("timescaledb: failed to get agents: %w", err)
	}
	defer rows.Close()

	var agentIDs []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		agentIDs = append(agentIDs, id)
	}

	result := make(map[string][]*MetricsPoint)
	for _, id := range agentIDs {
		points, err := s.Query(id, start, end, limit)
		if err != nil {
			return nil, err
		}
		if len(points) > 0 {
			result[id] = points
		}
	}

	return result, nil
}

// Delete removes metrics older than the specified time
func (s *TimescaleDBStore) Delete(before time.Time) error {
	ctx := context.Background()

	_, err := s.db.ExecContext(ctx, `DELETE FROM metrics WHERE time < $1`, before)
	if err != nil {
		return fmt.Errorf("timescaledb: delete metrics failed: %w", err)
	}

	_, err = s.db.ExecContext(ctx, `DELETE FROM disk_metrics WHERE time < $1`, before)
	if err != nil {
		return fmt.Errorf("timescaledb: delete disk_metrics failed: %w", err)
	}

	_, err = s.db.ExecContext(ctx, `DELETE FROM network_metrics WHERE time < $1`, before)
	if err != nil {
		return fmt.Errorf("timescaledb: delete network_metrics failed: %w", err)
	}

	return nil
}

// Close closes the storage connection
func (s *TimescaleDBStore) Close() error {
	return s.db.Close()
}

// Name returns the storage backend name
func (s *TimescaleDBStore) Name() string {
	return "timescaledb"
}
