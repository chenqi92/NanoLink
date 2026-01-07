package service

import (
	"encoding/json"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// AuditService handles operation audit logging
type AuditService struct {
	db     *gorm.DB
	logger *zap.SugaredLogger
}

// NewAuditService creates a new audit service
func NewAuditService(db *gorm.DB, logger *zap.SugaredLogger) *AuditService {
	return &AuditService{
		db:     db,
		logger: logger,
	}
}

// AuditEntry represents audit log input
type AuditEntry struct {
	UserID        uint
	Username      string
	AgentID       string
	AgentHostname string
	CommandType   string
	CommandID     string
	Target        string
	Params        map[string]string
	Success       bool
	Error         string
	DurationMs    int64
	IPAddress     string
}

// LogCommand logs a command execution to the audit trail
func (s *AuditService) LogCommand(entry AuditEntry) error {
	paramsJSON := ""
	if entry.Params != nil {
		if b, err := json.Marshal(entry.Params); err == nil {
			paramsJSON = string(b)
		}
	}

	auditLog := &database.AuditLog{
		Timestamp:     time.Now(),
		UserID:        entry.UserID,
		Username:      entry.Username,
		AgentID:       entry.AgentID,
		AgentHostname: entry.AgentHostname,
		CommandType:   entry.CommandType,
		CommandID:     entry.CommandID,
		Target:        entry.Target,
		Params:        paramsJSON,
		Success:       entry.Success,
		Error:         entry.Error,
		DurationMs:    entry.DurationMs,
		IPAddress:     entry.IPAddress,
	}

	if err := s.db.Create(auditLog).Error; err != nil {
		s.logger.Errorf("Failed to create audit log: %v", err)
		return err
	}

	s.logger.Debugf("Audit log created: user=%s agent=%s command=%s success=%v",
		entry.Username, entry.AgentID, entry.CommandType, entry.Success)
	return nil
}

// AuditQuery represents query parameters for audit logs
type AuditQuery struct {
	UserID      uint
	AgentID     string
	CommandType string
	Success     *bool
	StartTime   *time.Time
	EndTime     *time.Time
	Limit       int
	Offset      int
}

// AuditQueryResult contains paginated audit logs
type AuditQueryResult struct {
	Logs       []database.AuditLog `json:"logs"`
	Total      int64               `json:"total"`
	Limit      int                 `json:"limit"`
	Offset     int                 `json:"offset"`
	HasMore    bool                `json:"hasMore"`
}

// QueryLogs queries audit logs with filtering
func (s *AuditService) QueryLogs(query AuditQuery) (*AuditQueryResult, error) {
	if query.Limit <= 0 || query.Limit > 1000 {
		query.Limit = 100
	}

	db := s.db.Model(&database.AuditLog{})

	// Apply filters
	if query.UserID > 0 {
		db = db.Where("user_id = ?", query.UserID)
	}
	if query.AgentID != "" {
		db = db.Where("agent_id = ?", query.AgentID)
	}
	if query.CommandType != "" {
		db = db.Where("command_type = ?", query.CommandType)
	}
	if query.Success != nil {
		db = db.Where("success = ?", *query.Success)
	}
	if query.StartTime != nil {
		db = db.Where("timestamp >= ?", *query.StartTime)
	}
	if query.EndTime != nil {
		db = db.Where("timestamp <= ?", *query.EndTime)
	}

	// Get total count
	var total int64
	if err := db.Count(&total).Error; err != nil {
		return nil, err
	}

	// Get paginated results
	var logs []database.AuditLog
	if err := db.Order("timestamp DESC").
		Offset(query.Offset).
		Limit(query.Limit).
		Find(&logs).Error; err != nil {
		return nil, err
	}

	return &AuditQueryResult{
		Logs:    logs,
		Total:   total,
		Limit:   query.Limit,
		Offset:  query.Offset,
		HasMore: int64(query.Offset+len(logs)) < total,
	}, nil
}

// GetUserAuditLogs gets all audit logs for a specific user
func (s *AuditService) GetUserAuditLogs(userID uint, limit, offset int) (*AuditQueryResult, error) {
	return s.QueryLogs(AuditQuery{
		UserID: userID,
		Limit:  limit,
		Offset: offset,
	})
}

// GetAgentAuditLogs gets all audit logs for a specific agent
func (s *AuditService) GetAgentAuditLogs(agentID string, limit, offset int) (*AuditQueryResult, error) {
	return s.QueryLogs(AuditQuery{
		AgentID: agentID,
		Limit:   limit,
		Offset:  offset,
	})
}

// GetRecentLogs gets the most recent audit logs
func (s *AuditService) GetRecentLogs(limit int) ([]database.AuditLog, error) {
	if limit <= 0 || limit > 1000 {
		limit = 100
	}

	var logs []database.AuditLog
	if err := s.db.Order("timestamp DESC").Limit(limit).Find(&logs).Error; err != nil {
		return nil, err
	}
	return logs, nil
}

// GetAuditStats returns statistics about audit logs
func (s *AuditService) GetAuditStats(since time.Time) (*AuditStats, error) {
	var stats AuditStats

	// Total commands
	s.db.Model(&database.AuditLog{}).Where("timestamp >= ?", since).Count(&stats.TotalCommands)

	// Successful commands
	s.db.Model(&database.AuditLog{}).Where("timestamp >= ? AND success = ?", since, true).Count(&stats.SuccessfulCommands)

	// Failed commands
	stats.FailedCommands = stats.TotalCommands - stats.SuccessfulCommands

	// Unique users
	s.db.Model(&database.AuditLog{}).Where("timestamp >= ?", since).
		Distinct("user_id").Count(&stats.UniqueUsers)

	// Unique agents
	s.db.Model(&database.AuditLog{}).Where("timestamp >= ?", since).
		Distinct("agent_id").Count(&stats.UniqueAgents)

	// Command type breakdown
	var typeStats []CommandTypeStats
	s.db.Model(&database.AuditLog{}).
		Select("command_type, COUNT(*) as count").
		Where("timestamp >= ?", since).
		Group("command_type").
		Order("count DESC").
		Limit(10).
		Scan(&typeStats)
	stats.TopCommandTypes = typeStats

	return &stats, nil
}

// AuditStats contains audit statistics
type AuditStats struct {
	TotalCommands      int64              `json:"totalCommands"`
	SuccessfulCommands int64              `json:"successfulCommands"`
	FailedCommands     int64              `json:"failedCommands"`
	UniqueUsers        int64              `json:"uniqueUsers"`
	UniqueAgents       int64              `json:"uniqueAgents"`
	TopCommandTypes    []CommandTypeStats `json:"topCommandTypes"`
}

// CommandTypeStats contains command type statistics
type CommandTypeStats struct {
	CommandType string `json:"commandType"`
	Count       int64  `json:"count"`
}

// CleanupOldLogs removes audit logs older than the specified duration
func (s *AuditService) CleanupOldLogs(olderThan time.Duration) (int64, error) {
	cutoff := time.Now().Add(-olderThan)
	result := s.db.Where("timestamp < ?", cutoff).Delete(&database.AuditLog{})
	if result.Error != nil {
		return 0, result.Error
	}
	s.logger.Infof("Cleaned up %d old audit logs (older than %v)", result.RowsAffected, olderThan)
	return result.RowsAffected, nil
}
