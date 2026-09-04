package service

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// JobService handles job scheduling and execution
type JobService struct {
	db     *gorm.DB
	logger *zap.SugaredLogger
}

// NewJobService creates a new job service
func NewJobService(db *gorm.DB, logger *zap.SugaredLogger) *JobService {
	return &JobService{
		db:     db,
		logger: logger,
	}
}

// CreateJob creates a new job
func (s *JobService) CreateJob(ctx context.Context, job *database.Job) error {
	return s.db.Create(job).Error
}

// UpdateJob updates a job
func (s *JobService) UpdateJob(ctx context.Context, jobID uint, updates map[string]interface{}) error {
	return s.db.Model(&database.Job{}).Where("id = ?", jobID).Updates(updates).Error
}

// DeleteJob deletes a job
func (s *JobService) DeleteJob(ctx context.Context, jobID uint) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		// Delete executions first
		if err := tx.Where("job_id = ?", jobID).Delete(&database.JobExecution{}).Error; err != nil {
			return fmt.Errorf("delete executions: %w", err)
		}
		// Delete job
		if err := tx.Delete(&database.Job{}, jobID).Error; err != nil {
			return fmt.Errorf("delete job: %w", err)
		}
		return nil
	})
}

// GetJob returns a job by ID
func (s *JobService) GetJob(ctx context.Context, jobID uint) (*database.Job, error) {
	var job database.Job
	if err := s.db.Preload("Creator").Preload("Updater").First(&job, jobID).Error; err != nil {
		return nil, err
	}
	return &job, nil
}

// ListJobs returns all jobs
func (s *JobService) ListJobs(ctx context.Context, filters map[string]interface{}) ([]database.Job, error) {
	var jobs []database.Job
	query := s.db.Preload("Creator")

	if jobType, ok := filters["type"].(string); ok && jobType != "" {
		query = query.Where("type = ?", jobType)
	}
	if enabled, ok := filters["enabled"].(bool); ok {
		query = query.Where("enabled = ?", enabled)
	}

	if err := query.Order("created_at DESC").Find(&jobs).Error; err != nil {
		return nil, err
	}
	return jobs, nil
}

// ExecuteJob triggers a job execution
func (s *JobService) ExecuteJob(ctx context.Context, jobID uint, userID uint, targetAgents []string) (*database.JobExecution, error) {
	var job database.Job
	if err := s.db.First(&job, jobID).Error; err != nil {
		return nil, fmt.Errorf("job not found: %w", err)
	}

	if !job.Enabled {
		return nil, fmt.Errorf("job is disabled")
	}

	targetJSON, _ := json.Marshal(targetAgents)
	execution := &database.JobExecution{
		JobID:        jobID,
		Status:       "pending",
		TriggeredBy:  userID,
		TargetAgents: string(targetJSON),
		CreatedAt:    time.Now(),
		UpdatedAt:    time.Now(),
	}

	// If approval required, set status to pending approval
	if job.RequireApproval {
		execution.Status = "pending"
	} else {
		execution.Status = "running"
		now := time.Now()
		execution.StartedAt = &now
	}

	if err := s.db.Create(execution).Error; err != nil {
		return nil, fmt.Errorf("create execution: %w", err)
	}

	return execution, nil
}

// ApproveExecution approves a pending job execution
func (s *JobService) ApproveExecution(ctx context.Context, executionID uint, approverID uint) error {
	var execution database.JobExecution
	if err := s.db.First(&execution, executionID).Error; err != nil {
		return fmt.Errorf("execution not found: %w", err)
	}

	if execution.Status != "pending" {
		return fmt.Errorf("execution is not pending approval")
	}

	now := time.Now()
	updates := map[string]interface{}{
		"status":      "running",
		"approved_by": approverID,
		"approved_at": now,
		"started_at":  now,
		"updated_at":  now,
	}

	return s.db.Model(&execution).Updates(updates).Error
}

// UpdateExecutionStatus updates execution status and result
func (s *JobService) UpdateExecutionStatus(ctx context.Context, executionID uint, status string, result map[string]interface{}, errorMsg string) error {
	updates := map[string]interface{}{
		"status":     status,
		"updated_at": time.Now(),
	}

	if result != nil {
		resultJSON, _ := json.Marshal(result)
		updates["result"] = string(resultJSON)
	}

	if errorMsg != "" {
		updates["error_msg"] = errorMsg
	}

	if status == "success" || status == "failed" || status == "cancelled" {
		now := time.Now()
		updates["completed_at"] = now
	}

	return s.db.Model(&database.JobExecution{}).Where("id = ?", executionID).Updates(updates).Error
}

// CancelExecution cancels a running execution
func (s *JobService) CancelExecution(ctx context.Context, executionID uint) error {
	var execution database.JobExecution
	if err := s.db.First(&execution, executionID).Error; err != nil {
		return fmt.Errorf("execution not found: %w", err)
	}

	if execution.Status != "running" && execution.Status != "pending" {
		return fmt.Errorf("cannot cancel execution in status: %s", execution.Status)
	}

	now := time.Now()
	return s.db.Model(&execution).Updates(map[string]interface{}{
		"status":       "cancelled",
		"completed_at": now,
		"updated_at":   now,
	}).Error
}

// GetExecution returns an execution by ID
func (s *JobService) GetExecution(ctx context.Context, executionID uint) (*database.JobExecution, error) {
	var execution database.JobExecution
	if err := s.db.Preload("Job").Preload("Trigger").Preload("Approver").
		First(&execution, executionID).Error; err != nil {
		return nil, err
	}
	return &execution, nil
}

// ListExecutions returns executions for a job
func (s *JobService) ListExecutions(ctx context.Context, jobID uint, limit int) ([]database.JobExecution, error) {
	var executions []database.JobExecution
	query := s.db.Preload("Trigger").Preload("Approver")

	if jobID > 0 {
		query = query.Where("job_id = ?", jobID)
	}

	if limit > 0 {
		query = query.Limit(limit)
	}

	if err := query.Order("created_at DESC").Find(&executions).Error; err != nil {
		return nil, err
	}
	return executions, nil
}

// ScriptService handles script management
type ScriptService struct {
	db     *gorm.DB
	logger *zap.SugaredLogger
}

// NewScriptService creates a new script service
func NewScriptService(db *gorm.DB, logger *zap.SugaredLogger) *ScriptService {
	return &ScriptService{
		db:     db,
		logger: logger,
	}
}

// CreateScript creates a new script
func (s *ScriptService) CreateScript(ctx context.Context, script *database.Script) error {
	return s.db.Create(script).Error
}

// UpdateScript updates a script
func (s *ScriptService) UpdateScript(ctx context.Context, scriptID uint, updates map[string]interface{}) error {
	return s.db.Model(&database.Script{}).Where("id = ?", scriptID).Updates(updates).Error
}

// DeleteScript deletes a script
func (s *ScriptService) DeleteScript(ctx context.Context, scriptID uint) error {
	return s.db.Delete(&database.Script{}, scriptID).Error
}

// GetScript returns a script by ID
func (s *ScriptService) GetScript(ctx context.Context, scriptID uint) (*database.Script, error) {
	var script database.Script
	if err := s.db.Preload("Creator").Preload("Updater").First(&script, scriptID).Error; err != nil {
		return nil, err
	}
	return &script, nil
}

// ListScripts returns all scripts
func (s *ScriptService) ListScripts(ctx context.Context) ([]database.Script, error) {
	var scripts []database.Script
	if err := s.db.Preload("Creator").Order("name ASC").Find(&scripts).Error; err != nil {
		return nil, err
	}
	return scripts, nil
}

// ConfigService handles configuration file management
type ConfigService struct {
	db     *gorm.DB
	logger *zap.SugaredLogger
}

// NewConfigService creates a new config service
func NewConfigService(db *gorm.DB, logger *zap.SugaredLogger) *ConfigService {
	return &ConfigService{
		db:     db,
		logger: logger,
	}
}

// CreateConfigFile creates a new config file record
func (s *ConfigService) CreateConfigFile(ctx context.Context, config *database.ConfigFile) error {
	return s.db.Create(config).Error
}

// GetConfigFile returns a config file by ID
func (s *ConfigService) GetConfigFile(ctx context.Context, configID uint) (*database.ConfigFile, error) {
	var config database.ConfigFile
	if err := s.db.Preload("LastUpdater").Preload("Versions", func(db *gorm.DB) *gorm.DB {
		return db.Order("version DESC").Limit(10)
	}).First(&config, configID).Error; err != nil {
		return nil, err
	}
	return &config, nil
}

// ListConfigFiles returns config files for an agent
func (s *ConfigService) ListConfigFiles(ctx context.Context, agentID string) ([]database.ConfigFile, error) {
	var configs []database.ConfigFile
	if err := s.db.Where("agent_id = ?", agentID).
		Preload("LastUpdater").
		Order("path ASC").
		Find(&configs).Error; err != nil {
		return nil, err
	}
	return configs, nil
}

// AddConfigVersion adds a new version to a config file
func (s *ConfigService) AddConfigVersion(ctx context.Context, version *database.ConfigVersion) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		// Get current max version
		var maxVersion int
		if err := tx.Model(&database.ConfigVersion{}).
			Where("config_file_id = ?", version.ConfigFileID).
			Select("COALESCE(MAX(version), 0)").
			Scan(&maxVersion).Error; err != nil {
			return fmt.Errorf("get max version: %w", err)
		}

		version.Version = maxVersion + 1

		if err := tx.Create(version).Error; err != nil {
			return fmt.Errorf("create version: %w", err)
		}

		// Update config file's last updated by
		return tx.Model(&database.ConfigFile{}).
			Where("id = ?", version.ConfigFileID).
			Updates(map[string]interface{}{
				"last_updated_by": version.CreatedBy,
				"updated_at":      time.Now(),
			}).Error
	})
}

// GetConfigVersion returns a specific version
func (s *ConfigService) GetConfigVersion(ctx context.Context, versionID uint) (*database.ConfigVersion, error) {
	var version database.ConfigVersion
	if err := s.db.Preload("Creator").First(&version, versionID).Error; err != nil {
		return nil, err
	}
	return &version, nil
}

// HealthCheckService handles health check operations
type HealthCheckService struct {
	db     *gorm.DB
	logger *zap.SugaredLogger
}

// NewHealthCheckService creates a new health check service
func NewHealthCheckService(db *gorm.DB, logger *zap.SugaredLogger) *HealthCheckService {
	return &HealthCheckService{
		db:     db,
		logger: logger,
	}
}

// CreateHealthCheck creates a new health check
func (s *HealthCheckService) CreateHealthCheck(ctx context.Context, check *database.HealthCheck) error {
	return s.db.Create(check).Error
}

// UpdateHealthCheck updates a health check
func (s *HealthCheckService) UpdateHealthCheck(ctx context.Context, checkID uint, updates map[string]interface{}) error {
	return s.db.Model(&database.HealthCheck{}).Where("id = ?", checkID).Updates(updates).Error
}

// DeleteHealthCheck deletes a health check
func (s *HealthCheckService) DeleteHealthCheck(ctx context.Context, checkID uint) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		// Delete results first
		if err := tx.Where("health_check_id = ?", checkID).Delete(&database.HealthCheckResult{}).Error; err != nil {
			return fmt.Errorf("delete results: %w", err)
		}
		// Delete check
		if err := tx.Delete(&database.HealthCheck{}, checkID).Error; err != nil {
			return fmt.Errorf("delete check: %w", err)
		}
		return nil
	})
}

// GetHealthCheck returns a health check by ID
func (s *HealthCheckService) GetHealthCheck(ctx context.Context, checkID uint) (*database.HealthCheck, error) {
	var check database.HealthCheck
	if err := s.db.Preload("Creator").Preload("Updater").First(&check, checkID).Error; err != nil {
		return nil, err
	}
	return &check, nil
}

// ListHealthChecks returns all health checks
func (s *HealthCheckService) ListHealthChecks(ctx context.Context) ([]database.HealthCheck, error) {
	var checks []database.HealthCheck
	if err := s.db.Preload("Creator").Order("name ASC").Find(&checks).Error; err != nil {
		return nil, err
	}
	return checks, nil
}

// RecordHealthCheckResult records a health check result
func (s *HealthCheckService) RecordHealthCheckResult(ctx context.Context, result *database.HealthCheckResult) error {
	return s.db.Create(result).Error
}

// GetLatestResults returns latest results for a health check
func (s *HealthCheckService) GetLatestResults(ctx context.Context, checkID uint, limit int) ([]database.HealthCheckResult, error) {
	var results []database.HealthCheckResult
	query := s.db.Where("health_check_id = ?", checkID).
		Order("checked_at DESC")

	if limit > 0 {
		query = query.Limit(limit)
	}

	if err := query.Find(&results).Error; err != nil {
		return nil, err
	}
	return results, nil
}
