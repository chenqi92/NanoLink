package handler

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"

	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/chenqi92/NanoLink/apps/server/internal/version"
)

// VersionHandler serves build identity, the upstream update check, and the
// self-update trigger.
//
// GET /api/version is readable by any authenticated user so the dashboard can
// show what it is talking to. The check and apply endpoints are super-admin
// only: a check reaches out to the network on request, and an apply replaces
// the running binary.
type VersionHandler struct {
	updates *service.SelfUpdateService
	audit   *service.AuditService
	logger  *zap.SugaredLogger
}

func NewVersionHandler(updates *service.SelfUpdateService, audit *service.AuditService, logger *zap.SugaredLogger) *VersionHandler {
	return &VersionHandler{updates: updates, audit: audit, logger: logger}
}

// GetVersion returns this build's identity plus the last cached update check,
// if one has already happened. It never performs network I/O.
func (h *VersionHandler) GetVersion(c *gin.Context) {
	resp := gin.H{
		"version":        version.Version,
		"commit":         version.Commit,
		"buildTime":      version.BuildTime,
		"goVersion":      version.Current().GoVersion,
		"goPlatform":     version.Current().GoPlatform,
		"assetPlatform":  version.Platform(),
		"deploymentMode": string(service.DetectDeploymentMode()),
		"updateEnabled":  h.updates != nil && h.updates.Enabled(),
	}
	if h.updates != nil {
		if cached, ok := h.updates.Cached(); ok {
			resp["latest"] = cached
		}
	}
	c.JSON(http.StatusOK, resp)
}

// CheckUpdate queries the configured update source. refresh=true bypasses the
// cache; without it a recent result is reused so repeated dashboard visits do
// not hammer the upstream feed.
func (h *VersionHandler) CheckUpdate(c *gin.Context) {
	if h.updates == nil || !h.updates.Enabled() {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": "version checking is disabled (update.source=disabled)",
		})
		return
	}

	refresh := c.Query("refresh") == "true" || c.Query("refresh") == "1"
	ctx, cancel := context.WithTimeout(c.Request.Context(), 45*time.Second)
	defer cancel()

	result, err := h.updates.Check(ctx, refresh)
	if err != nil {
		h.logger.Warnf("Update check failed: %v", err)
		// The upstream feed being unreachable is not a server fault, and the
		// dashboard needs the reason to show something useful.
		c.JSON(http.StatusBadGateway, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, result)
}

// ApplyUpdateRequest lets the caller state which version it believes it is
// installing, so a release published between the check and the click is not
// installed silently.
type ApplyUpdateRequest struct {
	ExpectVersion string `json:"expectVersion"`
}

// ApplyUpdate downloads, verifies and installs the newer binary, then restarts.
func (h *VersionHandler) ApplyUpdate(c *gin.Context) {
	if h.updates == nil || !h.updates.Enabled() {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": "version checking is disabled (update.source=disabled)",
		})
		return
	}

	var req ApplyUpdateRequest
	// A body is optional; only a malformed one is worth rejecting.
	if c.Request.ContentLength > 0 {
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request body: " + err.Error()})
			return
		}
	}

	userID, _ := c.Get(ContextKeyUserID)
	username, _ := c.Get(ContextKeyUsername)
	uid, _ := userID.(uint)
	uname, _ := username.(string)

	ctx, cancel := context.WithTimeout(c.Request.Context(), 15*time.Minute)
	defer cancel()

	h.logger.Infof("[AUDIT] Self-update requested by %s (uid=%d) from v%s", uname, uid, version.Version)

	result, err := h.updates.Apply(ctx, req.ExpectVersion)
	h.recordAudit(c, uid, uname, req.ExpectVersion, result, err)
	if err != nil {
		h.logger.Errorf("Self-update failed: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, result)

	// Restart only after the response has been flushed, so the caller learns the
	// outcome instead of seeing a dropped connection.
	if result.Restarting {
		h.updates.ScheduleRestart(2 * time.Second)
	}
}

// recordAudit writes the update attempt to the audit trail. An audit write
// failure is logged but never fails the request, since the binary swap has
// already happened by then.
func (h *VersionHandler) recordAudit(c *gin.Context, uid uint, uname, expect string, result *service.ApplyResult, applyErr error) {
	if h.audit == nil {
		return
	}

	params := map[string]string{
		"fromVersion":    version.Version,
		"expectVersion":  expect,
		"deploymentMode": string(service.DetectDeploymentMode()),
	}
	errText := ""
	if applyErr != nil {
		errText = applyErr.Error()
	}
	if result != nil {
		params["toVersion"] = result.ToVersion
	}

	if err := h.audit.LogCommand(service.AuditEntry{
		UserID:      uid,
		Username:    uname,
		CommandType: "server_self_update",
		Target:      "server",
		Params:      params,
		Success:     applyErr == nil,
		Error:       errText,
		IPAddress:   c.ClientIP(),
	}); err != nil {
		h.logger.Warnf("Failed to write self-update audit entry: %v", err)
	}
}
