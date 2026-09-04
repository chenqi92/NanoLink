package handler

import (
	"net/http"
	"strconv"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// JobHandler handles job API requests
type JobHandler struct {
	jobService *service.JobService
	logger     *zap.SugaredLogger
}

// NewJobHandler creates a new job handler
func NewJobHandler(jobService *service.JobService, logger *zap.SugaredLogger) *JobHandler {
	return &JobHandler{
		jobService: jobService,
		logger:     logger,
	}
}

// ListJobs returns all jobs
func (h *JobHandler) ListJobs(c *gin.Context) {
	filters := make(map[string]interface{})

	if jobType := c.Query("type"); jobType != "" {
		filters["type"] = jobType
	}
	if enabled := c.Query("enabled"); enabled != "" {
		filters["enabled"] = enabled == "true"
	}

	jobs, err := h.jobService.ListJobs(c.Request.Context(), filters)
	if err != nil {
		h.logger.Errorf("Failed to list jobs: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list jobs"})
		return
	}

	c.JSON(http.StatusOK, jobs)
}

// GetJob returns a job by ID
func (h *JobHandler) GetJob(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid job ID"})
		return
	}

	job, err := h.jobService.GetJob(c.Request.Context(), uint(id))
	if err != nil {
		h.logger.Errorf("Failed to get job: %v", err)
		c.JSON(http.StatusNotFound, gin.H{"error": "job not found"})
		return
	}

	c.JSON(http.StatusOK, job)
}

// CreateJob creates a new job
func (h *JobHandler) CreateJob(c *gin.Context) {
	var req database.Job
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}

	req.CreatedBy = user.ID

	if err := h.jobService.CreateJob(c.Request.Context(), &req); err != nil {
		h.logger.Errorf("Failed to create job: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create job"})
		return
	}

	c.JSON(http.StatusCreated, req)
}

// UpdateJob updates a job
func (h *JobHandler) UpdateJob(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid job ID"})
		return
	}

	var req map[string]interface{}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}

	req["updated_by"] = user.ID

	if err := h.jobService.UpdateJob(c.Request.Context(), uint(id), req); err != nil {
		h.logger.Errorf("Failed to update job: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update job"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "job updated"})
}

// DeleteJob deletes a job
func (h *JobHandler) DeleteJob(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid job ID"})
		return
	}

	if err := h.jobService.DeleteJob(c.Request.Context(), uint(id)); err != nil {
		h.logger.Errorf("Failed to delete job: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete job"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "job deleted"})
}

// ExecuteJob triggers a job execution
func (h *JobHandler) ExecuteJob(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid job ID"})
		return
	}

	var req struct {
		TargetAgents []string `json:"targetAgents"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}

	execution, err := h.jobService.ExecuteJob(c.Request.Context(), uint(id), user.ID, req.TargetAgents)
	if err != nil {
		h.logger.Errorf("Failed to execute job: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, execution)
}

// ApproveExecution approves a pending job execution
func (h *JobHandler) ApproveExecution(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid execution ID"})
		return
	}

	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}

	if err := h.jobService.ApproveExecution(c.Request.Context(), uint(id), user.ID); err != nil {
		h.logger.Errorf("Failed to approve execution: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "execution approved"})
}

// CancelExecution cancels a running execution
func (h *JobHandler) CancelExecution(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid execution ID"})
		return
	}

	if err := h.jobService.CancelExecution(c.Request.Context(), uint(id)); err != nil {
		h.logger.Errorf("Failed to cancel execution: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "execution cancelled"})
}

// GetExecution returns an execution by ID
func (h *JobHandler) GetExecution(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid execution ID"})
		return
	}

	execution, err := h.jobService.GetExecution(c.Request.Context(), uint(id))
	if err != nil {
		h.logger.Errorf("Failed to get execution: %v", err)
		c.JSON(http.StatusNotFound, gin.H{"error": "execution not found"})
		return
	}

	c.JSON(http.StatusOK, execution)
}

// ListExecutions returns executions for a job
func (h *JobHandler) ListExecutions(c *gin.Context) {
	jobID, _ := strconv.ParseUint(c.Query("jobId"), 10, 32)
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))

	executions, err := h.jobService.ListExecutions(c.Request.Context(), uint(jobID), limit)
	if err != nil {
		h.logger.Errorf("Failed to list executions: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list executions"})
		return
	}

	c.JSON(http.StatusOK, executions)
}

// ScriptHandler handles script API requests
type ScriptHandler struct {
	scriptService *service.ScriptService
	logger        *zap.SugaredLogger
}

// NewScriptHandler creates a new script handler
func NewScriptHandler(scriptService *service.ScriptService, logger *zap.SugaredLogger) *ScriptHandler {
	return &ScriptHandler{
		scriptService: scriptService,
		logger:        logger,
	}
}

// ListScripts returns all scripts
func (h *ScriptHandler) ListScripts(c *gin.Context) {
	scripts, err := h.scriptService.ListScripts(c.Request.Context())
	if err != nil {
		h.logger.Errorf("Failed to list scripts: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list scripts"})
		return
	}

	c.JSON(http.StatusOK, scripts)
}

// GetScript returns a script by ID
func (h *ScriptHandler) GetScript(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid script ID"})
		return
	}

	script, err := h.scriptService.GetScript(c.Request.Context(), uint(id))
	if err != nil {
		h.logger.Errorf("Failed to get script: %v", err)
		c.JSON(http.StatusNotFound, gin.H{"error": "script not found"})
		return
	}

	c.JSON(http.StatusOK, script)
}

// CreateScript creates a new script
func (h *ScriptHandler) CreateScript(c *gin.Context) {
	var req database.Script
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}

	req.CreatedBy = user.ID

	if err := h.scriptService.CreateScript(c.Request.Context(), &req); err != nil {
		h.logger.Errorf("Failed to create script: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create script"})
		return
	}

	c.JSON(http.StatusCreated, req)
}

// UpdateScript updates a script
func (h *ScriptHandler) UpdateScript(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid script ID"})
		return
	}

	var req map[string]interface{}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	user := GetCurrentUser(c)
	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
		return
	}

	req["updated_by"] = user.ID

	if err := h.scriptService.UpdateScript(c.Request.Context(), uint(id), req); err != nil {
		h.logger.Errorf("Failed to update script: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update script"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "script updated"})
}

// DeleteScript deletes a script
func (h *ScriptHandler) DeleteScript(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid script ID"})
		return
	}

	if err := h.scriptService.DeleteScript(c.Request.Context(), uint(id)); err != nil {
		h.logger.Errorf("Failed to delete script: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete script"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "script deleted"})
}
