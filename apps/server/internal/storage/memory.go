package storage

import (
	"sync"
	"time"
)

// MemoryStore is an in-memory time-series store (default backend)
type MemoryStore struct {
	data       map[string][]*MetricsPoint
	maxEntries int
	mu         sync.RWMutex
}

// NewMemoryStore creates a new in-memory store
func NewMemoryStore(cfg Config) *MemoryStore {
	maxEntries := cfg.MaxEntries
	if maxEntries <= 0 {
		maxEntries = 600 // ~10 minutes at 1s intervals
	}
	return &MemoryStore{
		data:       make(map[string][]*MetricsPoint),
		maxEntries: maxEntries,
	}
}

// Write stores a metrics point
func (s *MemoryStore) Write(point *MetricsPoint) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	agentID := point.AgentID
	if _, exists := s.data[agentID]; !exists {
		s.data[agentID] = make([]*MetricsPoint, 0, s.maxEntries)
	}

	history := s.data[agentID]
	if len(history) >= s.maxEntries {
		// Remove oldest entry
		history = history[1:]
	}

	// Make a copy to avoid external modifications
	pointCopy := *point
	s.data[agentID] = append(history, &pointCopy)
	return nil
}

// Query retrieves metrics for an agent within a time range
func (s *MemoryStore) Query(agentID string, start, end time.Time, limit int) ([]*MetricsPoint, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	history, exists := s.data[agentID]
	if !exists {
		return nil, nil
	}

	// Filter by time range
	var result []*MetricsPoint
	for _, point := range history {
		if (start.IsZero() || point.Timestamp.After(start) || point.Timestamp.Equal(start)) &&
			(end.IsZero() || point.Timestamp.Before(end) || point.Timestamp.Equal(end)) {
			result = append(result, point)
		}
	}

	// Apply limit (return most recent)
	if limit > 0 && len(result) > limit {
		result = result[len(result)-limit:]
	}

	return result, nil
}

// QueryAll retrieves metrics for all agents within a time range
func (s *MemoryStore) QueryAll(start, end time.Time, limit int) (map[string][]*MetricsPoint, error) {
	s.mu.RLock()
	agentIDs := make([]string, 0, len(s.data))
	for id := range s.data {
		agentIDs = append(agentIDs, id)
	}
	s.mu.RUnlock()

	result := make(map[string][]*MetricsPoint)
	for _, id := range agentIDs {
		data, err := s.Query(id, start, end, limit)
		if err != nil {
			return nil, err
		}
		if len(data) > 0 {
			result[id] = data
		}
	}
	return result, nil
}

// Delete removes metrics older than the specified time
func (s *MemoryStore) Delete(before time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	for agentID, history := range s.data {
		var filtered []*MetricsPoint
		for _, point := range history {
			if point.Timestamp.After(before) || point.Timestamp.Equal(before) {
				filtered = append(filtered, point)
			}
		}
		s.data[agentID] = filtered
	}
	return nil
}

// Close closes the storage (no-op for memory)
func (s *MemoryStore) Close() error {
	return nil
}

// Name returns the storage backend name
func (s *MemoryStore) Name() string {
	return "memory"
}

// GetAgentIDs returns all agent IDs with stored metrics
func (s *MemoryStore) GetAgentIDs() []string {
	s.mu.RLock()
	defer s.mu.RUnlock()

	ids := make([]string, 0, len(s.data))
	for id := range s.data {
		ids = append(ids, id)
	}
	return ids
}

// RemoveAgent removes all metrics for an agent
func (s *MemoryStore) RemoveAgent(agentID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.data, agentID)
}
