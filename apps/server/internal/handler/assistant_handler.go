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
	metrics *service.MetricsService
	agents  *service.AgentService
	db      *gorm.DB
	llm     *service.LLMClient
	logger  *zap.SugaredLogger
}

func NewAssistantHandler(metrics *service.MetricsService, agents *service.AgentService, db *gorm.DB, llm *service.LLMClient, logger *zap.SugaredLogger) *AssistantHandler {
	return &AssistantHandler{metrics: metrics, agents: agents, db: db, llm: llm, logger: logger}
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
	findings := []findingDTO{}

	hostByID := map[string]string{}
	for _, a := range h.agents.GetAllAgents() {
		hostByID[a.ID] = a.Hostname
	}

	metrics := h.metrics.GetAllCurrentMetrics()
	for id, m := range metrics {
		if m == nil {
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
		if tk.IsOnline() {
			continue
		}
		host := tk.Hostname
		if host == "" {
			host = tk.AgentID
		}
		findings = append(findings, findingDTO{Kind: "info", AgentID: tk.AgentID, Title: fmt.Sprintf("%s is offline", host), Detail: "No recent heartbeat — the agent may be down or unreachable.", Actions: []string{"View history"}})
	}

	if len(findings) == 0 {
		findings = append(findings, findingDTO{Kind: "ok", Title: "Fleet healthy", Detail: "All monitored agents are within thresholds.", Actions: []string{}})
	}

	c.JSON(http.StatusOK, findings)
}

type chatRequest struct {
	Messages []service.ChatMessage `json:"messages"`
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

// Chat answers a free-form question using the configured external LLM, grounding
// it with a live snapshot of the fleet. Requires llm.enabled + an API key.
// POST /assistant/chat
func (h *AssistantHandler) Chat(c *gin.Context) {
	if h.llm == nil || !h.llm.Enabled() {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": "AI assistant chat is not configured. Enable llm in the server config and set NANOLINK_LLM_API_KEY.",
		})
		return
	}

	var req chatRequest
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxAssistantRequestBytes)
	if err := c.ShouldBindJSON(&req); err != nil || len(req.Messages) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "messages are required"})
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

	reply, err := h.llm.Chat(c.Request.Context(), h.buildSystemPrompt(), msgs)
	if err != nil {
		h.logger.Warnw("assistant chat failed", "err", err)
		c.JSON(http.StatusBadGateway, gin.H{"error": "assistant chat failed"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"reply": reply})
}

// buildSystemPrompt assembles a concise live snapshot of the fleet so the LLM
// answers grounded in real data.
func (h *AssistantHandler) buildSystemPrompt() string {
	var sb strings.Builder
	sb.WriteString("You are NanoLink's infrastructure assistant. Answer concisely and only from the live snapshot below. ")
	sb.WriteString("You cannot run commands; when asked to act, describe the steps the operator should take.\n\n")

	hostByID := map[string]string{}
	for _, a := range h.agents.GetAllAgents() {
		hostByID[a.ID] = a.Hostname
	}

	metrics := h.metrics.GetAllCurrentMetrics()
	sb.WriteString(fmt.Sprintf("Fleet snapshot — %d agent(s) reporting:\n", len(metrics)))
	for id, m := range metrics {
		if m == nil {
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
		if !tk.IsOnline() {
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
