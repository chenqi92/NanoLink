package handler

import (
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// AssistantHandler produces metric-derived "findings" and, when an LLM is
// configured, answers free-form questions grounded in the live fleet snapshot.
type AssistantHandler struct {
	metrics  *service.MetricsService
	agents   *service.AgentService
	db       *gorm.DB
	perm     *service.PermissionService
	llm      *service.LLMClient
	profiles *service.LLMProfileService
	logger   *zap.SugaredLogger
}

func NewAssistantHandler(metrics *service.MetricsService, agents *service.AgentService, db *gorm.DB, perm *service.PermissionService, llm *service.LLMClient, logger *zap.SugaredLogger) *AssistantHandler {
	return &AssistantHandler{metrics: metrics, agents: agents, db: db, perm: perm, llm: llm, logger: logger}
}

// SetProfileService enables chatting through a saved provider profile selected
// per request, falling back to the globally configured provider when unset.
func (h *AssistantHandler) SetProfileService(profiles *service.LLMProfileService) {
	h.profiles = profiles
}

func (h *AssistantHandler) visibility(c *gin.Context) (map[string]struct{}, bool, error) {
	user := GetCurrentUser(c)
	if user == nil {
		return nil, false, service.ErrPermissionDenied
	}
	if user.IsSuperAdmin {
		return nil, true, nil
	}
	ids, err := h.perm.GetVisibleAgents(user.ID)
	if err != nil {
		return nil, false, err
	}
	visible := make(map[string]struct{}, len(ids))
	for _, id := range ids {
		visible[id] = struct{}{}
	}
	return visible, false, nil
}

func agentVisible(agentID string, visible map[string]struct{}, all bool) bool {
	if all {
		return true
	}
	_, ok := visible[agentID]
	return ok
}

type findingDTO struct {
	Kind    string   `json:"kind"` // anomaly | warn | info | ok
	Title   string   `json:"title"`
	Detail  string   `json:"detail"`
	AgentID string   `json:"agentId,omitempty"`
	Actions []string `json:"actions"`
}

// GET /assistant/findings
func (h *AssistantHandler) Findings(c *gin.Context) {
	visible, all, err := h.visibility(c)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to resolve agent permissions"})
		return
	}
	findings := []findingDTO{}

	hostByID := map[string]string{}
	for _, a := range h.agents.GetAllAgents() {
		if !agentVisible(a.ID, visible, all) {
			continue
		}
		hostByID[a.ID] = a.Hostname
	}

	metrics := h.metrics.GetAllCurrentMetrics()
	for id, m := range metrics {
		if m == nil || !agentVisible(id, visible, all) {
			continue
		}
		host := hostByID[id]
		if host == "" {
			host = id
		}
		cpu := m.CPU.UsagePercent
		if cpu > 90 {
			findings = append(findings, findingDTO{Kind: "anomaly", AgentID: id, Title: fmt.Sprintf("%s CPU sustained at %.0f%%", host, cpu), Detail: "CPU above 90% — check top processes for a runaway job.", Actions: []string{"List processes", "View history"}})
		}
		if m.Memory.Total > 0 {
			memPct := float64(m.Memory.Used) / float64(m.Memory.Total) * 100
			if memPct > 90 {
				findings = append(findings, findingDTO{Kind: "warn", AgentID: id, Title: fmt.Sprintf("%s memory pressure at %.0f%%", host, memPct), Detail: "Memory above 90% — risk of OOM. Consider checking processes or swap.", Actions: []string{"List processes", "View history"}})
			}
		}
		for _, d := range m.Disks {
			if d.UsagePercent > 90 {
				findings = append(findings, findingDTO{Kind: "warn", AgentID: id, Title: fmt.Sprintf("%s %s at %.0f%% full", host, d.MountPoint, d.UsagePercent), Detail: "Disk above 90% — archive or extend the volume before it fills.", Actions: []string{"Open shell"}})
				break
			}
		}
		for _, g := range m.GPUs {
			if g.UsagePercent > 90 {
				findings = append(findings, findingDTO{Kind: "anomaly", AgentID: id, Title: fmt.Sprintf("%s GPU sustained at %.0f%%", host, g.UsagePercent), Detail: "GPU above 90% — likely a long-running job; check VRAM headroom.", Actions: []string{"View history"}})
				break
			}
		}
	}

	// Offline agents (from registered tokens)
	var tokens []database.AgentToken
	h.db.Where("agent_id != ?", "").Find(&tokens)
	for _, tk := range tokens {
		if tk.IsOnline() || !agentVisible(tk.AgentID, visible, all) {
			continue
		}
		host := tk.Hostname
		if host == "" {
			host = tk.AgentID
		}
		findings = append(findings, findingDTO{Kind: "info", AgentID: tk.AgentID, Title: fmt.Sprintf("%s is offline", host), Detail: "No recent heartbeat — the agent may be down or unreachable.", Actions: []string{"View history"}})
	}

	if len(findings) == 0 {
		if !all && len(visible) == 0 {
			findings = append(findings, findingDTO{Kind: "info", Title: "No agents assigned", Detail: "This account does not currently have access to any agents.", Actions: []string{}})
		} else {
			findings = append(findings, findingDTO{Kind: "ok", Title: "Fleet healthy", Detail: "All visible monitored agents are within thresholds.", Actions: []string{}})
		}
	}

	c.JSON(http.StatusOK, findings)
}

type chatRequest struct {
	Messages []service.ChatMessage `json:"messages"`
	// ProfileID selects a saved provider profile. 0 means "use the active
	// profile, or the globally configured provider if no profile is active".
	ProfileID uint `json:"profileId"`
}

const (
	maxAssistantRequestBytes = 64 * 1024
	maxAssistantMessages     = 20
	maxAssistantMessageBytes = 4 * 1024
	maxAssistantTotalBytes   = 20 * 1024
)

var (
	errAssistantTooManyMessages = errors.New("too many messages")
	errAssistantMessageTooLong  = errors.New("message too long")
	errAssistantPromptTooLong   = errors.New("conversation too long")
)

func sanitizeAssistantMessages(messages []service.ChatMessage) ([]service.ChatMessage, error) {
	if len(messages) > maxAssistantMessages {
		return nil, errAssistantTooManyMessages
	}

	msgs := make([]service.ChatMessage, 0, len(messages))
	totalBytes := 0
	for _, m := range messages {
		if m.Role != "user" && m.Role != "assistant" {
			continue
		}
		content := strings.TrimSpace(m.Content)
		if content == "" {
			continue
		}
		if len(content) > maxAssistantMessageBytes {
			return nil, errAssistantMessageTooLong
		}
		totalBytes += len(content)
		if totalBytes > maxAssistantTotalBytes {
			return nil, errAssistantPromptTooLong
		}
		msgs = append(msgs, service.ChatMessage{Role: m.Role, Content: content})
	}

	return msgs, nil
}

// Status returns the non-secret provider identity so the assistant UI can show
// the configured model without exposing the base URL or API key. An active
// saved profile takes precedence over the legacy singleton configuration.
func (h *AssistantHandler) Status(c *gin.Context) {
	if h.profiles != nil {
		if cfg, err := h.profiles.ActiveConfig(); err == nil && cfg.APIKey != "" && cfg.Model != "" {
			c.JSON(http.StatusOK, service.LLMStatus{
				Enabled:    true,
				Configured: true,
				Provider:   cfg.Provider,
				Model:      cfg.Model,
			})
			return
		}
	}
	if h.llm == nil {
		c.JSON(http.StatusOK, service.LLMStatus{})
		return
	}
	c.JSON(http.StatusOK, h.llm.Status())
}

// resolveChatConfig picks the provider configuration for this request:
// an explicitly requested profile, else the active profile, else the
// globally configured provider. The second return reports whether a usable
// provider configuration was found.
func (h *AssistantHandler) resolveChatConfig(profileID uint) (service.LLMConfig, bool) {
	if h.profiles != nil {
		if profileID != 0 {
			profile, err := h.profiles.GetProfile(profileID)
			if err == nil {
				if cfg, cfgErr := h.profiles.ConfigForProfile(profile); cfgErr == nil && cfg.APIKey != "" && cfg.Model != "" {
					return cfg, true
				}
			}
			// An explicit but unusable selection should not silently fall back
			// to a different model than the user picked.
			return service.LLMConfig{}, false
		}
		if cfg, err := h.profiles.ActiveConfig(); err == nil && cfg.APIKey != "" && cfg.Model != "" {
			return cfg, true
		}
	}
	if h.llm != nil && h.llm.Enabled() {
		// Signal "use the client's own configuration" with an empty config.
		return service.LLMConfig{}, true
	}
	return service.LLMConfig{}, false
}

// Chat answers a free-form question using the configured external LLM, grounding
// it with a live snapshot of the fleet. Requires llm.enabled + an API key.
// POST /assistant/chat
func (h *AssistantHandler) Chat(c *gin.Context) {
	var req chatRequest
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxAssistantRequestBytes)
	if err := c.ShouldBindJSON(&req); err != nil || len(req.Messages) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "messages are required"})
		return
	}

	cfg, ok := h.resolveChatConfig(req.ProfileID)
	if !ok {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": "AI assistant chat is not configured. Ask a super admin to configure an AI provider in Settings.",
		})
		return
	}
	// Only user/assistant turns are forwarded; the system prompt is injected here.
	msgs, sanitizeErr := sanitizeAssistantMessages(req.Messages)
	if sanitizeErr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": sanitizeErr.Error()})
		return
	}
	if len(msgs) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no usable messages"})
		return
	}

	visible, all, visibilityErr := h.visibility(c)
	if visibilityErr != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to resolve agent permissions"})
		return
	}
	system := h.buildSystemPrompt(visible, all)
	var reply string
	var err error
	if cfg.Model != "" {
		reply, err = h.llm.ChatWithConfig(c.Request.Context(), cfg, system, msgs)
	} else {
		reply, err = h.llm.Chat(c.Request.Context(), system, msgs)
	}
	if err != nil {
		h.logger.Warnw("assistant chat failed", "err", err)
		c.JSON(http.StatusBadGateway, gin.H{"error": "assistant chat failed"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"reply": reply})
}

// buildSystemPrompt assembles a concise live snapshot of the fleet so the LLM
// answers grounded in real data.
func (h *AssistantHandler) buildSystemPrompt(visible map[string]struct{}, all bool) string {
	var sb strings.Builder
	sb.WriteString("You are NanoOps' infrastructure assistant. Answer concisely and only from the live snapshot below. ")
	sb.WriteString("You cannot run commands; when asked to act, describe the steps the operator should take.\n\n")

	hostByID := map[string]string{}
	for _, a := range h.agents.GetAllAgents() {
		if !agentVisible(a.ID, visible, all) {
			continue
		}
		hostByID[a.ID] = a.Hostname
	}

	metrics := h.metrics.GetAllCurrentMetrics()
	visibleMetricCount := 0
	for id, metric := range metrics {
		if metric != nil && agentVisible(id, visible, all) {
			visibleMetricCount++
		}
	}
	sb.WriteString(fmt.Sprintf("Fleet snapshot — %d visible agent(s) reporting:\n", visibleMetricCount))
	for id, m := range metrics {
		if m == nil || !agentVisible(id, visible, all) {
			continue
		}
		host := hostByID[id]
		if host == "" {
			host = id
		}
		memPct := 0.0
		if m.Memory.Total > 0 {
			memPct = float64(m.Memory.Used) / float64(m.Memory.Total) * 100
		}
		maxDisk := 0.0
		for _, d := range m.Disks {
			if d.UsagePercent > maxDisk {
				maxDisk = d.UsagePercent
			}
		}
		sb.WriteString(fmt.Sprintf("- %s: CPU %.0f%%, memory %.0f%%, peak disk %.0f%%\n",
			host, m.CPU.UsagePercent, memPct, maxDisk))
	}

	var tokens []database.AgentToken
	h.db.Where("agent_id != ?", "").Find(&tokens)
	var offline []string
	for _, tk := range tokens {
		if !tk.IsOnline() && agentVisible(tk.AgentID, visible, all) {
			host := tk.Hostname
			if host == "" {
				host = tk.AgentID
			}
			offline = append(offline, host)
		}
	}
	if len(offline) > 0 {
		sb.WriteString("Offline agents: " + strings.Join(offline, ", ") + "\n")
	}
	return sb.String()
}
