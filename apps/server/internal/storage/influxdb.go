package storage

import (
	"context"
	"fmt"
	"time"

	influxdb2 "github.com/influxdata/influxdb-client-go/v2"
	"github.com/influxdata/influxdb-client-go/v2/api"
)

// InfluxDBStore is an InfluxDB time-series store
type InfluxDBStore struct {
	client   influxdb2.Client
	writeAPI api.WriteAPIBlocking
	queryAPI api.QueryAPI
	org      string
	bucket   string
}

// NewInfluxDBStore creates a new InfluxDB store
func NewInfluxDBStore(cfg Config) (*InfluxDBStore, error) {
	if cfg.URL == "" {
		return nil, fmt.Errorf("influxdb: URL is required")
	}
	if cfg.Token == "" {
		return nil, fmt.Errorf("influxdb: token is required")
	}
	if cfg.Org == "" {
		return nil, fmt.Errorf("influxdb: org is required")
	}
	if cfg.Bucket == "" {
		cfg.Bucket = "nanolink"
	}

	client := influxdb2.NewClient(cfg.URL, cfg.Token)

	// Verify connection
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_, err := client.Health(ctx)
	if err != nil {
		client.Close()
		return nil, fmt.Errorf("influxdb: failed to connect: %w", err)
	}

	return &InfluxDBStore{
		client:   client,
		writeAPI: client.WriteAPIBlocking(cfg.Org, cfg.Bucket),
		queryAPI: client.QueryAPI(cfg.Org),
		org:      cfg.Org,
		bucket:   cfg.Bucket,
	}, nil
}

// Write stores a metrics point
func (s *InfluxDBStore) Write(point *MetricsPoint) error {
	ctx := context.Background()

	// Create InfluxDB point for CPU
	p := influxdb2.NewPointWithMeasurement("cpu").
		AddTag("agent_id", point.AgentID).
		AddField("usage_percent", point.CPU.UsagePercent).
		SetTime(point.Timestamp)
	if err := s.writeAPI.WritePoint(ctx, p); err != nil {
		return fmt.Errorf("influxdb: failed to write cpu: %w", err)
	}

	// Memory
	p = influxdb2.NewPointWithMeasurement("memory").
		AddTag("agent_id", point.AgentID).
		AddField("total", int64(point.Memory.Total)).
		AddField("used", int64(point.Memory.Used)).
		AddField("available", int64(point.Memory.Available)).
		SetTime(point.Timestamp)
	if err := s.writeAPI.WritePoint(ctx, p); err != nil {
		return fmt.Errorf("influxdb: failed to write memory: %w", err)
	}

	// Disks
	for _, disk := range point.Disks {
		p = influxdb2.NewPointWithMeasurement("disk").
			AddTag("agent_id", point.AgentID).
			AddTag("mount_point", disk.MountPoint).
			AddField("total", int64(disk.Total)).
			AddField("used", int64(disk.Used)).
			AddField("read_bytes_per_sec", int64(disk.ReadBytesPerSec)).
			AddField("write_bytes_per_sec", int64(disk.WriteBytesPerSec)).
			SetTime(point.Timestamp)
		if err := s.writeAPI.WritePoint(ctx, p); err != nil {
			return fmt.Errorf("influxdb: failed to write disk: %w", err)
		}
	}

	// Networks
	for _, net := range point.Networks {
		p = influxdb2.NewPointWithMeasurement("network").
			AddTag("agent_id", point.AgentID).
			AddTag("interface", net.Interface).
			AddField("rx_bytes_per_sec", int64(net.RxBytesPerSec)).
			AddField("tx_bytes_per_sec", int64(net.TxBytesPerSec)).
			AddField("is_up", net.IsUp).
			SetTime(point.Timestamp)
		if err := s.writeAPI.WritePoint(ctx, p); err != nil {
			return fmt.Errorf("influxdb: failed to write network: %w", err)
		}
	}

	return nil
}

// Query retrieves metrics for an agent within a time range
func (s *InfluxDBStore) Query(agentID string, start, end time.Time, limit int) ([]*MetricsPoint, error) {
	ctx := context.Background()

	if start.IsZero() {
		start = time.Now().Add(-10 * time.Minute)
	}
	if end.IsZero() {
		end = time.Now()
	}

	// Query CPU data as primary timeline
	query := fmt.Sprintf(`
		from(bucket: "%s")
		|> range(start: %s, stop: %s)
		|> filter(fn: (r) => r._measurement == "cpu" and r.agent_id == "%s")
		|> filter(fn: (r) => r._field == "usage_percent")
		|> sort(columns: ["_time"])
		|> limit(n: %d)
	`, s.bucket, start.Format(time.RFC3339), end.Format(time.RFC3339), agentID, limit)

	result, err := s.queryAPI.Query(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("influxdb: query failed: %w", err)
	}
	defer result.Close()

	var points []*MetricsPoint
	for result.Next() {
		record := result.Record()
		point := &MetricsPoint{
			AgentID:   agentID,
			Timestamp: record.Time(),
			CPU: CPUMetrics{
				UsagePercent: record.Value().(float64),
			},
		}
		points = append(points, point)
	}

	return points, nil
}

// QueryAll retrieves metrics for all agents within a time range
func (s *InfluxDBStore) QueryAll(start, end time.Time, limit int) (map[string][]*MetricsPoint, error) {
	ctx := context.Background()

	if start.IsZero() {
		start = time.Now().Add(-10 * time.Minute)
	}
	if end.IsZero() {
		end = time.Now()
	}

	// Get distinct agent IDs
	query := fmt.Sprintf(`
		from(bucket: "%s")
		|> range(start: %s, stop: %s)
		|> filter(fn: (r) => r._measurement == "cpu")
		|> distinct(column: "agent_id")
	`, s.bucket, start.Format(time.RFC3339), end.Format(time.RFC3339))

	result, err := s.queryAPI.Query(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("influxdb: failed to get agent ids: %w", err)
	}
	defer result.Close()

	var agentIDs []string
	for result.Next() {
		if id, ok := result.Record().Value().(string); ok {
			agentIDs = append(agentIDs, id)
		}
	}

	// Query each agent
	allPoints := make(map[string][]*MetricsPoint)
	for _, id := range agentIDs {
		points, err := s.Query(id, start, end, limit)
		if err != nil {
			return nil, err
		}
		if len(points) > 0 {
			allPoints[id] = points
		}
	}

	return allPoints, nil
}

// Delete removes metrics older than the specified time
func (s *InfluxDBStore) Delete(before time.Time) error {
	// InfluxDB handles retention via bucket retention policies
	// This is a no-op as data is automatically deleted based on retention
	return nil
}

// Close closes the storage connection
func (s *InfluxDBStore) Close() error {
	s.client.Close()
	return nil
}

// Name returns the storage backend name
func (s *InfluxDBStore) Name() string {
	return "influxdb"
}
