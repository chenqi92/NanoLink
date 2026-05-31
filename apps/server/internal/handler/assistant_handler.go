package handler

import (
	"fmt"
	"net/http"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// AssistantHandler produces metric-derived "findings" (no external LLM).
type AssistantHandler struct {
	metrics *service.MetricsService
	agents  *service.AgentService
	db      *gorm.DB
	logger  *zap.SugaredLogger
}

func NewAssistantHandler(metrics *service.MetricsService, agents *service.AgentService, db *gorm.DB, logger *zap.SugaredLogger) *AssistantHandler {
	return &AssistantHandler{metrics: metrics, agents: agents, db: db, logger: logger}
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
