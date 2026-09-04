package handler

import (
	"net/http"
	"strconv"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// IncidentHandler handles incident API requests
type IncidentHandler struct {
	incidentService *service.IncidentService
	logger          *zap.SugaredLogger
}

// NewIncidentHandler creates a new incident handler
func NewIncidentHandler(incidentService *service.IncidentService, logger *zap.SugaredLogger) *IncidentHandler {
	return &IncidentHandler{
		incidentService: incidentService,
		logger:          logger,
	}
}

// ListIncidents returns incidents with filters
func (h *IncidentHandler) ListIncidents(c *gin.Context) {
	filters := make(map[string]interface{})

	if status := c.Query("status"); status != "" {
		filters["status"] = status
	}
	if severity := c.Query("severity"); severity != "" {
		filters["severity"] = severity
	}
	if assignedTo, err := strconv.ParseUint(c.Query("assignedTo"), 10, 32); err == nil {
		filters["assigned_to"] = uint(assignedTo)
	}

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))

	incidents, err := h.incidentService.ListIncidents(c.Request.Context(), filters, limit)
	if err != nil {
		h.logger.Errorf("Failed to list incidents: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list incidents"})
		return
	}

	c.JSON(http.StatusOK, incidents)
}

// GetIncident returns an incident by ID
func (h *IncidentHandler) GetIncident(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid incident ID"})
		return
	}

	incident, err := h.incidentService.GetIncident(c.Request.Context(), uint(id))
	if err != nil {
		h.logger.Errorf("Failed to get incident: %v", err)
		c.JSON(http.StatusNotFound, gin.H{"error": "incident not found"})
		return
	}

	c.JSON(http.StatusOK, incident)
}

// CreateIncident creates a new incident
func (h *IncidentHandler) CreateIncident(c *gin.Context) {
	var req database.Incident
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
	req.Status = "open"

	if err := h.incidentService.CreateIncident(c.Request.Context(), &req); err != nil {
		h.logger.Errorf("Failed to create incident: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create incident"})
		return
	}

	c.JSON(http.StatusCreated, req)
}

// UpdateIncident updates an incident
func (h *IncidentHandler) UpdateIncident(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid incident ID"})
		return
	}

	var req map[string]interface{}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.incidentService.UpdateIncident(c.Request.Context(), uint(id), req); err != nil {
		h.logger.Errorf("Failed to update incident: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update incident"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "incident updated"})
}

// ResolveIncident marks an incident as resolved
func (h *IncidentHandler) ResolveIncident(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid incident ID"})
		return
	}

	var req struct {
		RootCause  string `json:"rootCause" binding:"required"`
		Resolution string `json:"resolution" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.incidentService.ResolveIncident(c.Request.Context(), uint(id), req.RootCause, req.Resolution); err != nil {
		h.logger.Errorf("Failed to resolve incident: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to resolve incident"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "incident resolved"})
}

// CloseIncident marks an incident as closed
func (h *IncidentHandler) CloseIncident(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid incident ID"})
		return
	}

	if err := h.incidentService.CloseIncident(c.Request.Context(), uint(id)); err != nil {
		h.logger.Errorf("Failed to close incident: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to close incident"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "incident closed"})
}

// AssignIncident assigns an incident to a user
func (h *IncidentHandler) AssignIncident(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid incident ID"})
		return
	}

	var req struct {
		UserID uint `json:"userId" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.incidentService.AssignIncident(c.Request.Context(), uint(id), req.UserID); err != nil {
		h.logger.Errorf("Failed to assign incident: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to assign incident"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "incident assigned"})
}

// ConfigHandler handles configuration file API requests
type ConfigHandler struct {
	configService *service.ConfigService
	logger        *zap.SugaredLogger
}

// NewConfigHandler creates a new config handler
func NewConfigHandler(configService *service.ConfigService, logger *zap.SugaredLogger) *ConfigHandler {
	return &ConfigHandler{
		configService: configService,
		logger:        logger,
	}
}

// ListConfigFiles returns config files for an agent
func (h *ConfigHandler) ListConfigFiles(c *gin.Context) {
	agentID := c.Param("agentId")
	if agentID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "agent ID required"})
		return
	}

	configs, err := h.configService.ListConfigFiles(c.Request.Context(), agentID)
	if err != nil {
		h.logger.Errorf("Failed to list config files: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list config files"})
		return
	}

	c.JSON(http.StatusOK, configs)
}

// GetConfigFile returns a config file by ID
func (h *ConfigHandler) GetConfigFile(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid config ID"})
		return
	}

	config, err := h.configService.GetConfigFile(c.Request.Context(), uint(id))
	if err != nil {
		h.logger.Errorf("Failed to get config file: %v", err)
		c.JSON(http.StatusNotFound, gin.H{"error": "config file not found"})
		return
	}

	c.JSON(http.StatusOK, config)
}

// AddConfigVersion adds a new version to a config file
func (h *ConfigHandler) AddConfigVersion(c *gin.Context) {
	var req database.ConfigVersion
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

	if err := h.configService.AddConfigVersion(c.Request.Context(), &req); err != nil {
		h.logger.Errorf("Failed to add config version: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to add config version"})
		return
	}

	c.JSON(http.StatusCreated, req)
}

// GetConfigVersion returns a specific config version
func (h *ConfigHandler) GetConfigVersion(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("versionId"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid version ID"})
		return
	}

	version, err := h.configService.GetConfigVersion(c.Request.Context(), uint(id))
	if err != nil {
		h.logger.Errorf("Failed to get config version: %v", err)
		c.JSON(http.StatusNotFound, gin.H{"error": "config version not found"})
		return
	}

	c.JSON(http.StatusOK, version)
}

// HealthCheckHandler handles health check API requests
type HealthCheckHandler struct {
	healthService *service.HealthCheckService
	logger        *zap.SugaredLogger
}

// NewHealthCheckHandler creates a new health check handler
func NewHealthCheckHandler(healthService *service.HealthCheckService, logger *zap.SugaredLogger) *HealthCheckHandler {
	return &HealthCheckHandler{
		healthService: healthService,
		logger:        logger,
	}
}

// ListHealthChecks returns all health checks
func (h *HealthCheckHandler) ListHealthChecks(c *gin.Context) {
	checks, err := h.healthService.ListHealthChecks(c.Request.Context())
	if err != nil {
		h.logger.Errorf("Failed to list health checks: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list health checks"})
		return
	}

	c.JSON(http.StatusOK, checks)
}

// GetHealthCheck returns a health check by ID
func (h *HealthCheckHandler) GetHealthCheck(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid health check ID"})
		return
	}

	check, err := h.healthService.GetHealthCheck(c.Request.Context(), uint(id))
	if err != nil {
		h.logger.Errorf("Failed to get health check: %v", err)
		c.JSON(http.StatusNotFound, gin.H{"error": "health check not found"})
		return
	}

	c.JSON(http.StatusOK, check)
}

// CreateHealthCheck creates a new health check
func (h *HealthCheckHandler) CreateHealthCheck(c *gin.Context) {
	var req database.HealthCheck
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

	if err := h.healthService.CreateHealthCheck(c.Request.Context(), &req); err != nil {
		h.logger.Errorf("Failed to create health check: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create health check"})
		return
	}

	c.JSON(http.StatusCreated, req)
}

// UpdateHealthCheck updates a health check
func (h *HealthCheckHandler) UpdateHealthCheck(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid health check ID"})
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

	if err := h.healthService.UpdateHealthCheck(c.Request.Context(), uint(id), req); err != nil {
		h.logger.Errorf("Failed to update health check: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update health check"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "health check updated"})
}

// DeleteHealthCheck deletes a health check
func (h *HealthCheckHandler) DeleteHealthCheck(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid health check ID"})
		return
	}

	if err := h.healthService.DeleteHealthCheck(c.Request.Context(), uint(id)); err != nil {
		h.logger.Errorf("Failed to delete health check: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete health check"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "health check deleted"})
}

// GetLatestResults returns latest results for a health check
func (h *HealthCheckHandler) GetLatestResults(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid health check ID"})
		return
	}

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))

	results, err := h.healthService.GetLatestResults(c.Request.Context(), uint(id), limit)
	if err != nil {
		h.logger.Errorf("Failed to get latest results: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get latest results"})
		return
	}

	c.JSON(http.StatusOK, results)
}
