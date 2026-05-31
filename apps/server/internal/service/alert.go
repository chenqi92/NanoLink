package service

import (
	"fmt"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// AlertService evaluates threshold rules against live metrics and manages
// alert instances, rules and notification channels.
type AlertService struct {
	db             *gorm.DB
	logger         *zap.SugaredLogger
	metricsService *MetricsService
	agentService   *AgentService
	stopChan       chan struct{}
}

func NewAlertService(db *gorm.DB, metricsService *MetricsService, agentService *AgentService, logger *zap.SugaredLogger) *AlertService {
	return &AlertService{
		db:             db,
		logger:         logger,
		metricsService: metricsService,
		agentService:   agentService,
		stopChan:       make(chan struct{}),
	}
}

// Start seeds default rules and begins the evaluation loop (every 30s).
func (s *AlertService) Start() {
	s.seedDefaults()
	go func() {
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		s.Evaluate()
		for {
			select {
			case <-ticker.C:
				s.Evaluate()
			case <-s.stopChan:
				return
			}
		}
	}()
	s.logger.Info("Alert evaluation loop started (every 30s)")
}

func (s *AlertService) Stop() {
	close(s.stopChan)
}

func (s *AlertService) seedDefaults() {
	var count int64
	s.db.Model(&database.AlertRule{}).Count(&count)
	if count > 0 {
		return
	}
	defaults := []database.AlertRule{
		{Name: "High CPU usage", Metric: "cpu", Operator: "gt", Threshold: 90, Severity: "crit", Scope: "all", Enabled: true},
		{Name: "High memory usage", Metric: "memory", Operator: "gt", Threshold: 90, Severity: "crit", Scope: "all", Enabled: true},
		{Name: "Disk filling up", Metric: "disk", Operator: "gt", Threshold: 90, Severity: "warn", Scope: "all", Enabled: true},
		{Name: "Agent offline", Metric: "offline", Operator: "gt", Threshold: 0, Severity: "crit", Scope: "all", Enabled: true},
	}
	for i := range defaults {
		s.db.Create(&defaults[i])
	}
	s.logger.Info("Seeded default alert rules")
}

// ─── Evaluation ────────────────────────────────────────────

func metricValue(metric string, m *MetricsData) (float64, bool) {
	switch metric {
	case "cpu":
		return m.CPU.UsagePercent, true
	case "memory":
		if m.Memory.Total == 0 {
			return 0, false
		}
		return float64(m.Memory.Used) / float64(m.Memory.Total) * 100, true
	case "disk":
		var max float64
		for _, d := range m.Disks {
			if d.UsagePercent > max {
				max = d.UsagePercent
			}
		}
		return max, true
	}
	return 0, false
}

func compare(op string, val, threshold float64) bool {
	if op == "lt" {
		return val < threshold
	}
	return val > threshold
}

func (s *AlertService) Evaluate() {
	var rules []database.AlertRule
	if err := s.db.Where("enabled = ?", true).Find(&rules).Error; err != nil {
		return
	}
	if len(rules) == 0 {
		return
	}

	metrics := s.metricsService.GetAllCurrentMetrics()
	hostByID := map[string]string{}
	for _, a := range s.agentService.GetAllAgents() {
		hostByID[a.ID] = a.Hostname
	}

	for _, r := range rules {
		if r.Metric == "offline" {
			var tokens []database.AgentToken
			s.db.Where("agent_id != ?", "").Find(&tokens)
			for _, tk := range tokens {
				host := tk.Hostname
				if host == "" {
					host = tk.AgentID
				}
				if tk.IsOnline() {
					s.resolve(r.ID, tk.AgentID)
				} else {
					s.fire(r, tk.AgentID, host, 0, fmt.Sprintf("%s is offline", host), "Agent heartbeat lost")
				}
			}
			continue
		}
		for id, m := range metrics {
			if m == nil {
				continue
			}
			val, ok := metricValue(r.Metric, m)
			if !ok {
				continue
			}
			host := hostByID[id]
			if host == "" {
				host = id
			}
			if compare(r.Operator, val, r.Threshold) {
				title := fmt.Sprintf("%s %s on %s (%.0f%%)", metricLabel(r.Metric), r.Operator+" threshold", host, val)
				s.fire(r, id, host, val, title, fmt.Sprintf("%s is %.1f%% (threshold %s %.0f%%)", metricLabel(r.Metric), val, r.Operator, r.Threshold))
			} else {
				s.resolve(r.ID, id)
			}
		}
	}

	// prune resolved instances older than 24h
	s.db.Where("status = ? AND last_seen_at < ?", "resolved", time.Now().Add(-24*time.Hour)).Delete(&database.AlertInstance{})
}

func metricLabel(metric string) string {
	switch metric {
	case "cpu":
		return "CPU"
	case "memory":
		return "Memory"
	case "disk":
		return "Disk"
	}
	return metric
}

func (s *AlertService) fire(r database.AlertRule, agentID, host string, val float64, title, desc string) {
	now := time.Now()
	var inst database.AlertInstance
	err := s.db.Where("rule_id = ? AND agent_id = ? AND status != ?", r.ID, agentID, "resolved").First(&inst).Error
	if err == nil {
		inst.Value = val
		inst.LastSeenAt = now
		inst.Title = title
		inst.Description = desc
		s.db.Save(&inst)
		return
	}
	inst = database.AlertInstance{
		RuleID:        r.ID,
		RuleName:      r.Name,
		AgentID:       agentID,
		AgentHostname: host,
		Level:         r.Severity,
		Title:         title,
		Description:   desc,
		Value:         val,
		Status:        "firing",
		FirstSeenAt:   now,
		LastSeenAt:    now,
	}
	s.db.Create(&inst)
}

func (s *AlertService) resolve(ruleID uint, agentID string) {
	s.db.Model(&database.AlertInstance{}).
		Where("rule_id = ? AND agent_id = ? AND status != ?", ruleID, agentID, "resolved").
		Update("status", "resolved")
}

// ─── Instances ─────────────────────────────────────────────

func (s *AlertService) ListInstances(status string) ([]database.AlertInstance, error) {
	var out []database.AlertInstance
	q := s.db.Order("first_seen_at desc")
	if status != "" {
		q = q.Where("status = ?", status)
	} else {
		q = q.Where("status != ?", "resolved")
	}
	if err := q.Limit(500).Find(&out).Error; err != nil {
		return nil, err
	}
	return out, nil
}

func (s *AlertService) AckInstance(id uint, username string) error {
	now := time.Now()
	return s.db.Model(&database.AlertInstance{}).
		Where("id = ? AND status = ?", id, "firing").
		Updates(map[string]interface{}{"status": "acked", "ack_by": username, "acked_at": &now}).Error
}

func (s *AlertService) AckAll(username string) error {
	now := time.Now()
	return s.db.Model(&database.AlertInstance{}).
		Where("status = ?", "firing").
		Updates(map[string]interface{}{"status": "acked", "ack_by": username, "acked_at": &now}).Error
}

// ─── Rules ─────────────────────────────────────────────────

func (s *AlertService) ListRules() ([]database.AlertRule, error) {
	var out []database.AlertRule
	if err := s.db.Order("id asc").Find(&out).Error; err != nil {
		return nil, err
	}
	return out, nil
}

func (s *AlertService) CreateRule(r *database.AlertRule) error { return s.db.Create(r).Error }

func (s *AlertService) UpdateRule(id uint, fields map[string]interface{}) error {
	return s.db.Model(&database.AlertRule{}).Where("id = ?", id).Updates(fields).Error
}

func (s *AlertService) DeleteRule(id uint) error {
	return s.db.Delete(&database.AlertRule{}, id).Error
}

// ─── Channels ──────────────────────────────────────────────

func (s *AlertService) ListChannels() ([]database.NotifyChannel, error) {
	var out []database.NotifyChannel
	if err := s.db.Order("id asc").Find(&out).Error; err != nil {
		return nil, err
	}
	return out, nil
}

func (s *AlertService) CreateChannel(c *database.NotifyChannel) error { return s.db.Create(c).Error }

func (s *AlertService) DeleteChannel(id uint) error {
	return s.db.Delete(&database.NotifyChannel{}, id).Error
}
