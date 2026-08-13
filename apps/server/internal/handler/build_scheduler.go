package handler

import (
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/gin-gonic/gin"
)

// Cron syntax intentionally supports a dependable five-field subset: numbers,
// comma lists, ranges, and */step. It is enough for CI schedules while avoiding
// an additional runtime dependency and ambiguous seconds/timezone semantics.
func validateCronExpression(expression string) error {
	parts := strings.Fields(strings.TrimSpace(expression))
	if len(parts) != 5 {
		return errors.New("schedule must be a five-field cron expression: minute hour day month weekday")
	}
	ranges := [][2]int{{0, 59}, {0, 23}, {1, 31}, {1, 12}, {0, 6}}
	for i, part := range parts {
		if _, err := parseCronField(part, ranges[i][0], ranges[i][1]); err != nil {
			return fmt.Errorf("invalid cron field %d: %w", i+1, err)
		}
	}
	return nil
}

func parseCronField(value string, min, max int) (map[int]bool, error) {
	result := map[int]bool{}
	for _, item := range strings.Split(value, ",") {
		item = strings.TrimSpace(item)
		if item == "" {
			return nil, errors.New("empty item")
		}
		base, step := item, 1
		if slash := strings.Index(item, "/"); slash >= 0 {
			base = item[:slash]
			parsed, err := strconv.Atoi(item[slash+1:])
			if err != nil || parsed <= 0 {
				return nil, errors.New("step must be positive")
			}
			step = parsed
		}
		start, end := min, max
		if base != "*" {
			if dash := strings.Index(base, "-"); dash >= 0 {
				var err error
				start, err = strconv.Atoi(base[:dash])
				if err != nil {
					return nil, errors.New("range start is invalid")
				}
				end, err = strconv.Atoi(base[dash+1:])
				if err != nil {
					return nil, errors.New("range end is invalid")
				}
			} else {
				parsed, err := strconv.Atoi(base)
				if err != nil {
					return nil, errors.New("value is invalid")
				}
				start, end = parsed, parsed
			}
		}
		if start < min || end > max || start > end {
			return nil, fmt.Errorf("value must be between %d and %d", min, max)
		}
		for number := start; number <= end; number += step {
			result[number] = true
		}
	}
	return result, nil
}

func cronMatches(expression string, at time.Time) bool {
	parts := strings.Fields(expression)
	if len(parts) != 5 {
		return false
	}
	values := []int{at.Minute(), at.Hour(), at.Day(), int(at.Month()), int(at.Weekday())}
	ranges := [][2]int{{0, 59}, {0, 23}, {1, 31}, {1, 12}, {0, 6}}
	for index, part := range parts {
		allowed, err := parseCronField(part, ranges[index][0], ranges[index][1])
		if err != nil || !allowed[values[index]] {
			return false
		}
	}
	return true
}

func (h *BuildHandler) StartScheduler() {
	go func() {
		defer close(h.schedulerDone)
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				h.runScheduledPipelines(time.Now())
			case <-h.schedulerStop:
				return
			}
		}
	}()
}

func (h *BuildHandler) StopScheduler() {
	select {
	case <-h.schedulerStop:
		return
	default:
		close(h.schedulerStop)
	}
	select {
	case <-h.schedulerDone:
	case <-time.After(5 * time.Second):
	}
}

func (h *BuildHandler) runScheduledPipelines(now time.Time) {
	minute := now.Truncate(time.Minute)
	var pipelines []database.BuildPipeline
	if err := h.db.Where("enabled = ? AND schedule <> ''", true).Find(&pipelines).Error; err != nil {
		h.logger.Warnf("list scheduled builds: %v", err)
		return
	}
	for _, pipeline := range pipelines {
		if !cronMatches(pipeline.Schedule, now) || (pipeline.LastScheduledAt != nil && !pipeline.LastScheduledAt.Before(minute)) {
			continue
		}
		result := h.db.Model(&database.BuildPipeline{}).Where("id = ? AND (last_scheduled_at IS NULL OR last_scheduled_at < ?)", pipeline.ID, minute).Update("last_scheduled_at", minute)
		if result.Error != nil || result.RowsAffected == 0 {
			continue
		}
		pipeline.LastScheduledAt = &minute
		if pipeline.SourceType == database.BuildSourceUpload {
			h.logger.Warnf("scheduled pipeline %d uses upload source and was skipped", pipeline.ID)
			continue
		}
		if _, err := h.dispatchPipeline(pipeline, buildDispatchInput{Trigger: database.BuildTriggerSchedule, Username: "scheduler", BaseURL: h.externalURL}); err != nil {
			h.logger.Warnf("dispatch scheduled pipeline %d: %v", pipeline.ID, err)
		}
	}
}

func (h *BuildHandler) Webhook(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil || id == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid pipeline id"})
		return
	}
	var pipeline database.BuildPipeline
	if err := h.db.First(&pipeline, uint(id)).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "build pipeline not found"})
		return
	}
	token := strings.TrimSpace(c.GetHeader("X-NanoOps-Token"))
	if token == "" {
		token = strings.TrimSpace(c.Query("token"))
	}
	if !tokenMatches(token, pipeline.WebhookTokenHash) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "webhook token is invalid"})
		return
	}
	if pipeline.SourceType == database.BuildSourceUpload {
		c.JSON(http.StatusBadRequest, gin.H{"error": "upload-source pipelines cannot use webhooks"})
		return
	}
	var request buildRunRequest
	if c.Request.ContentLength > 0 {
		c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 64*1024)
		_ = c.ShouldBindJSON(&request)
	}
	run, err := h.dispatchPipeline(pipeline, buildDispatchInput{Version: request.Version, Trigger: database.BuildTriggerWebhook, Username: "webhook", BaseURL: requestBaseURL(c)})
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusAccepted, run)
}
