package storage

import (
	"fmt"
)

// New creates a new TimeSeriesStore based on config
func New(cfg Config) (TimeSeriesStore, error) {
	switch cfg.Type {
	case "memory", "":
		return NewMemoryStore(cfg), nil
	case "influxdb":
		return NewInfluxDBStore(cfg)
	case "timescaledb":
		return NewTimescaleDBStore(cfg)
	default:
		return nil, fmt.Errorf("unsupported time-series storage type: %s (supported: memory, influxdb, timescaledb)", cfg.Type)
	}
}
