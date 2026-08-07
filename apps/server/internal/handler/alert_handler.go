package handler

import (
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

type AlertHandler struct {
	alertService *service.AlertService
	permService  *service.PermissionService
	logger       *zap.SugaredLogger
}

func NewAlertHandler(alertService *service.AlertService, permService *service.PermissionService, logger *zap.SugaredLogger) *AlertHandler {
	return &AlertHandler{alertService: alertService, permService: permService, logger: logger}
}

func (h *AlertHandler) visibleAgents(c *gin.Context) (map[string]struct{}, []string, bool, error) {
	user := GetCurrentUser(c)
	if user == nil {
		return nil, nil, false, service.ErrPermissionDenied
	}
	if user.IsSuperAdmin {
		return nil, nil, true, nil
	}
	ids, err := h.permService.GetVisibleAgents(user.ID)
	if err != nil {
		return nil, nil, false, err
	}
	set := make(map[string]struct{}, len(ids))
	for _, id := range ids {
		set[id] = struct{}{}
	}
	return set, ids, false, nil
}

type alertDTO struct {
	ID    string  `json:"id"`
	Level string  `json:"level"`
	Title string  `json:"title"`
	Desc  string  `json:"desc"`
	Agent string  `json:"agent"`
	Rule  string  `json:"rule"`
	Since string  `json:"since"`
	Ack   bool    `json:"ack"`
	AckBy string  `json:"ackBy,omitempty"`
	Value float64 `json:"value"`
}

func humanizeSince(d time.Duration) string {
	s := int(d.Seconds())
	switch {
	case s < 60:
		return fmt.Sprintf("%ds", s)
	case s < 3600:
		return fmt.Sprintf("%dm", s/60)
	case s < 86400:
		return fmt.Sprintf("%dh", s/3600)
	default:
		return fmt.Sprintf("%dd", s/86400)
	}
}

// GET /alerts?status=
func (h *AlertHandler) ListAlerts(c *gin.Context) {
	visible, _, all, err := h.visibleAgents(c)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to resolve agent permissions"})
		return
	}
	instances, err := h.alertService.ListInstances(c.Query("status"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list alerts"})
		return
	}
	out := make([]alertDTO, 0, len(instances))
	for _, a := range instances {
		if !all {
			if _, ok := visible[a.AgentID]; !ok {
				continue
			}
		}
		out = append(out, alertDTO{
			ID:    strconv.FormatUint(uint64(a.ID), 10),
			Level: a.Level,
			Title: a.Title,
			Desc:  a.Description,
			Agent: a.AgentHostname,
			Rule:  a.RuleName,
			Since: humanizeSince(time.Since(a.FirstSeenAt)),
			Ack:   a.Status == "acked",
			AckBy: a.AckBy,
			Value: a.Value,
		})
	}
	c.JSON(http.StatusOK, out)
}

// POST /alerts/:id/ack
func (h *AlertHandler) AckAlert(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	instance, err := h.alertService.GetInstance(uint(id))
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "alert not found"})
		return
	}
	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}
	if !user.IsSuperAdmin {
		allowed, permissionErr := h.permService.CanUserAccessAgent(user.ID, instance.AgentID)
		if permissionErr != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "permission check failed"})
			return
		}
		if !allowed {
			c.JSON(http.StatusForbidden, gin.H{"error": "insufficient permissions"})
			return
		}
	}
	username := ""
	username = user.Username
	if err := h.alertService.AckInstance(uint(id), username); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to ack"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "acked"})
}

// POST /alerts/ack-all
func (h *AlertHandler) AckAll(c *gin.Context) {
	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}
	_, visibleIDs, all, permissionErr := h.visibleAgents(c)
	if permissionErr != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to resolve agent permissions"})
		return
	}
	var count int64
	var err error
	if all {
		count, err = h.alertService.AckAll(user.Username)
	} else {
		count, err = h.alertService.AckAllForAgents(user.Username, visibleIDs)
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to ack all"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "acked", "count": count})
}

// GET /alerts/rules
func (h *AlertHandler) ListRules(c *gin.Context) {
	rules, err := h.alertService.ListRules()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list rules"})
		return
	}
	c.JSON(http.StatusOK, rules)
}

type ruleRequest struct {
	Name        string  `json:"name" binding:"required"`
	Metric      string  `json:"metric" binding:"required"`
	Operator    string  `json:"operator"`
	Threshold   float64 `json:"threshold"`
	DurationSec int     `json:"durationSec"`
	Severity    string  `json:"severity"`
	Scope       string  `json:"scope"`
	Enabled     *bool   `json:"enabled"`
}

// POST /alerts/rules
func (h *AlertHandler) CreateRule(c *gin.Context) {
	var req ruleRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	rule := &database.AlertRule{
		Name: req.Name, Metric: req.Metric, Operator: orDefault(req.Operator, "gt"),
		Threshold: req.Threshold, DurationSec: req.DurationSec,
		Severity: orDefault(req.Severity, "warn"), Scope: orDefault(req.Scope, "all"),
		Enabled: req.Enabled == nil || *req.Enabled,
	}
	if err := h.alertService.CreateRule(rule); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create rule"})
		return
	}
	c.JSON(http.StatusCreated, rule)
}

// PUT /alerts/rules/:id
func (h *AlertHandler) UpdateRule(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	// only allow known fields
	fields := map[string]interface{}{}
	for _, k := range []string{"name", "metric", "operator", "threshold", "durationSec", "severity", "scope", "enabled"} {
		if v, ok := body[k]; ok {
			col := map[string]string{"durationSec": "duration_sec"}[k]
			if col == "" {
				col = k
			}
			fields[col] = v
		}
	}
	if len(fields) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no fields"})
		return
	}
	if err := h.alertService.UpdateRule(uint(id), fields); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update rule"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

// DELETE /alerts/rules/:id
func (h *AlertHandler) DeleteRule(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	if err := h.alertService.DeleteRule(uint(id)); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete rule"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "deleted"})
}

// GET /alerts/channels
func (h *AlertHandler) ListChannels(c *gin.Context) {
	channels, err := h.alertService.ListChannels()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list channels"})
		return
	}
	// Target holds webhook URLs / SMTP creds (often with embedded tokens). Never
	// echo it back verbatim — mask it so listing a channel can't leak the secret.
	out := make([]gin.H, 0, len(channels))
	for i := range channels {
		ch := &channels[i]
		status := "ok"
		if !ch.Enabled {
			status = "warn"
		}
		out = append(out, gin.H{
			"id":         ch.ID,
			"kind":       ch.Kind,
			"name":       ch.Name,
			"target":     maskChannelTarget(ch.Target),
			"enabled":    ch.Enabled,
			"status":     status,
			"lastUsedAt": ch.LastUsedAt,
		})
	}
	c.JSON(http.StatusOK, out)
}

// TestChannel sends a synthetic notification through a channel to verify config.
func (h *AlertHandler) TestChannel(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid channel id"})
		return
	}
	if err := h.alertService.TestChannel(uint(id)); err != nil {
		// Don't echo err.Error(): transport errors embed the full channel URL,
		// whose path/query can carry the webhook secret (masked elsewhere).
		h.logger.Warnw("test channel failed", "channelId", id, "error", err)
		c.JSON(http.StatusBadGateway, gin.H{"error": "test notification failed"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "test sent"})
}

// ListSilences returns active silences.
func (h *AlertHandler) ListSilences(c *gin.Context) {
	sils, err := h.alertService.ListSilences()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list silences"})
		return
	}
	c.JSON(http.StatusOK, sils)
}

type silenceRequest struct {
	Matcher     string `json:"matcher" binding:"required"`
	Reason      string `json:"reason"`
	DurationMin int    `json:"durationMin" binding:"min=1"`
}

// CreateSilence creates a silence valid for DurationMin minutes.
func (h *AlertHandler) CreateSilence(c *gin.Context) {
	var req silenceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	var by string
	if u := GetCurrentUser(c); u != nil {
		by = u.Username
	}
	sil := &database.Silence{
		Matcher:   req.Matcher,
		Reason:    req.Reason,
		Until:     time.Now().Add(time.Duration(req.DurationMin) * time.Minute),
		CreatedBy: by,
		CreatedAt: time.Now(),
	}
	if err := h.alertService.CreateSilence(sil); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create silence"})
		return
	}
	c.JSON(http.StatusCreated, sil)
}

// DeleteSilence removes a silence.
func (h *AlertHandler) DeleteSilence(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid silence id"})
		return
	}
	if err := h.alertService.DeleteSilence(uint(id)); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete silence"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "silence deleted"})
}

// maskChannelTarget hides the secret portion of a notification target while
// keeping enough to identify it. For URLs it keeps scheme+host (the token
// usually lives in the path/query); for anything else it shows a short prefix.
func maskChannelTarget(target string) string {
	if target == "" {
		return ""
	}
	if u, err := url.Parse(target); err == nil && u.Host != "" {
		return u.Scheme + "://" + u.Host + "/***"
	}
	if len(target) <= 6 {
		return "***"
	}
	return target[:3] + "***"
}

type channelRequest struct {
	Kind   string `json:"kind" binding:"required"`
	Name   string `json:"name" binding:"required"`
	Target string `json:"target"`
}

// POST /alerts/channels
func (h *AlertHandler) CreateChannel(c *gin.Context) {
	var req channelRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	ch := &database.NotifyChannel{Kind: req.Kind, Name: req.Name, Target: req.Target, Enabled: true}
	if err := h.alertService.CreateChannel(ch); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create channel"})
		return
	}
	c.JSON(http.StatusCreated, ch)
}

// DELETE /alerts/channels/:id
func (h *AlertHandler) DeleteChannel(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	if err := h.alertService.DeleteChannel(uint(id)); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete channel"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "deleted"})
}

func orDefault(v, def string) string {
	if v == "" {
		return def
	}
	return v
}
