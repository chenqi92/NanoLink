package service

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/smtp"
	"os"
	"strings"
	"sync"
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

	// pending tracks when a (rule,agent) condition first became true, so a rule's
	// DurationSec ("sustained for N seconds") can be honored before firing.
	pending   map[string]time.Time
	pendingMu sync.Mutex
}

func NewAlertService(db *gorm.DB, metricsService *MetricsService, agentService *AgentService, logger *zap.SugaredLogger) *AlertService {
	return &AlertService{
		db:             db,
		logger:         logger,
		metricsService: metricsService,
		agentService:   agentService,
		stopChan:       make(chan struct{}),
		pending:        make(map[string]time.Time),
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
				if !scopeMatches(r.Scope, tk.AgentID, host) {
					continue
				}
				key := fmt.Sprintf("%d:%s", r.ID, tk.AgentID)
				if tk.IsOnline() {
					s.clearPending(key)
					s.resolve(r.ID, tk.AgentID)
				} else if s.passesDuration(key, r.DurationSec) {
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
			if !scopeMatches(r.Scope, id, host) {
				continue
			}
			key := fmt.Sprintf("%d:%s", r.ID, id)
			if compare(r.Operator, val, r.Threshold) {
				if s.passesDuration(key, r.DurationSec) {
					title := fmt.Sprintf("%s %s on %s (%.0f%%)", metricLabel(r.Metric), r.Operator+" threshold", host, val)
					s.fire(r, id, host, val, title, fmt.Sprintf("%s is %.1f%% (threshold %s %.0f%%)", metricLabel(r.Metric), val, r.Operator, r.Threshold))
				}
			} else {
				s.clearPending(key)
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
	if err := s.db.Create(&inst).Error; err != nil {
		s.logger.Warnw("failed to persist alert instance", "err", err)
		return
	}
	// Dispatch notifications for newly fired alerts (async; channels may be slow).
	go s.notify(inst)
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

// ─── Duration / scope gating ───────────────────────────────

// passesDuration reports whether a (rule,agent) condition has held for at least
// the rule's DurationSec. The first time the condition is seen it records the
// timestamp and returns false (unless DurationSec is 0 — fire immediately).
func (s *AlertService) passesDuration(key string, durationSec int) bool {
	if durationSec <= 0 {
		return true
	}
	s.pendingMu.Lock()
	defer s.pendingMu.Unlock()
	now := time.Now()
	since, ok := s.pending[key]
	if !ok {
		s.pending[key] = now
		return false
	}
	return now.Sub(since) >= time.Duration(durationSec)*time.Second
}

// clearPending resets the sustained-condition timer for a (rule,agent) key.
func (s *AlertService) clearPending(key string) {
	s.pendingMu.Lock()
	delete(s.pending, key)
	s.pendingMu.Unlock()
}

// scopeMatches reports whether a rule's Scope applies to the given agent.
// "all" (or empty) matches every agent; otherwise Scope is a comma-separated
// list of agent IDs or hostnames.
func scopeMatches(scope, agentID, host string) bool {
	scope = strings.TrimSpace(scope)
	if scope == "" || scope == "all" {
		return true
	}
	for _, tok := range strings.Split(scope, ",") {
		tok = strings.TrimSpace(tok)
		if tok != "" && (tok == agentID || tok == host) {
			return true
		}
	}
	return false
}

// ─── Notifications ─────────────────────────────────────────

var notifyHTTPClient = &http.Client{Timeout: 10 * time.Second}

// notify dispatches a fired alert to every enabled notification channel.
func (s *AlertService) notify(inst database.AlertInstance) {
	var channels []database.NotifyChannel
	if err := s.db.Where("enabled = ?", true).Find(&channels).Error; err != nil {
		s.logger.Warnw("failed to load notify channels", "err", err)
		return
	}
	for _, ch := range channels {
		if err := s.sendNotification(ch, inst); err != nil {
			s.logger.Warnw("notification failed", "channel", ch.Name, "kind", ch.Kind, "err", err)
		}
	}
}

func (s *AlertService) sendNotification(ch database.NotifyChannel, inst database.AlertInstance) error {
	switch strings.ToLower(strings.TrimSpace(ch.Kind)) {
	case "slack":
		return postJSON(ch.Target, map[string]string{"text": formatAlertText(inst)})
	case "discord":
		return postJSON(ch.Target, map[string]string{"content": formatAlertText(inst)})
	case "email":
		return sendEmail(ch.Target, inst)
	default: // webhook and unknown kinds: POST the full instance as JSON
		return postJSON(ch.Target, inst)
	}
}

func formatAlertText(inst database.AlertInstance) string {
	return fmt.Sprintf("[%s] %s — %s (host: %s)",
		strings.ToUpper(inst.Level), inst.Title, inst.Description, inst.AgentHostname)
}

// postJSON POSTs a JSON payload to an operator-configured webhook target URL.
func postJSON(target string, payload interface{}) error {
	target = strings.TrimSpace(target)
	if target == "" {
		return fmt.Errorf("empty target url")
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	req, err := http.NewRequest(http.MethodPost, target, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := notifyHTTPClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return fmt.Errorf("notification endpoint returned status %d", resp.StatusCode)
	}
	return nil
}

// sendEmail delivers an alert by SMTP. Connection settings come from environment
// variables (SMTP_HOST/SMTP_PORT/SMTP_USER/SMTP_PASS/SMTP_FROM) so credentials
// are never stored in the database; the channel Target is the recipient address.
func sendEmail(to string, inst database.AlertInstance) error {
	to = strings.TrimSpace(to)
	if to == "" {
		return fmt.Errorf("empty recipient")
	}
	host := os.Getenv("SMTP_HOST")
	if host == "" {
		return fmt.Errorf("email channel requires SMTP_HOST/SMTP_PORT/SMTP_USER/SMTP_PASS env")
	}
	port := os.Getenv("SMTP_PORT")
	if port == "" {
		port = "587"
	}
	user := os.Getenv("SMTP_USER")
	pass := os.Getenv("SMTP_PASS")
	from := os.Getenv("SMTP_FROM")
	if from == "" {
		from = user
	}
	subject := fmt.Sprintf("[NanoLink][%s] %s", strings.ToUpper(inst.Level), inst.Title)
	msg := fmt.Sprintf("From: %s\r\nTo: %s\r\nSubject: %s\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n%s\r\n",
		from, to, subject, formatAlertText(inst))
	var auth smtp.Auth
	if user != "" {
		auth = smtp.PlainAuth("", user, pass, host)
	}
	return smtp.SendMail(host+":"+port, auth, from, []string{to}, []byte(msg))
}
