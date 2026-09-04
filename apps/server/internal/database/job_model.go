package database

import (
	"time"

	"gorm.io/gorm"
)

// Job represents a scheduled or on-demand operation job
type Job struct {
	ID          uint           `gorm:"primarykey" json:"id"`
	Name        string         `gorm:"size:100;not null" json:"name"`
	Type        string         `gorm:"size:50;not null" json:"type"` // "script", "package_update", "config_write", "health_check"
	Description string         `gorm:"type:text" json:"description"`
	Scope       string         `gorm:"type:text" json:"scope"` // Target agent filter (e.g. "tag=prod", "agent_id=...")
	Schedule    string         `gorm:"size:100" json:"schedule"` // Cron expression for recurring jobs
	Enabled     bool           `gorm:"default:true" json:"enabled"`
	RequireApproval bool       `gorm:"default:false" json:"requireApproval"` // Needs approval before execution
	Timeout     int            `gorm:"default:300" json:"timeout"` // Execution timeout in seconds
	Params      string         `gorm:"type:text" json:"params"` // JSON object of job parameters
	CreatedBy   uint           `gorm:"index" json:"createdBy"`
	UpdatedBy   uint           `json:"updatedBy"`
	CreatedAt   time.Time      `json:"createdAt"`
	UpdatedAt   time.Time      `json:"updatedAt"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`

	// Relations
	Creator   User         `gorm:"foreignKey:CreatedBy" json:"creator,omitempty"`
	Updater   User         `gorm:"foreignKey:UpdatedBy" json:"updater,omitempty"`
	Executions []JobExecution `gorm:"foreignKey:JobID" json:"executions,omitempty"`
}

func (Job) TableName() string {
	return "jobs"
}

// JobExecution represents a single execution instance of a job
type JobExecution struct {
	ID          uint      `gorm:"primarykey" json:"id"`
	JobID       uint      `gorm:"index;not null" json:"jobId"`
	Status      string    `gorm:"size:20;not null" json:"status"` // "pending", "approved", "running", "success", "failed", "cancelled"
	StartedAt   *time.Time `json:"startedAt,omitempty"`
	CompletedAt *time.Time `json:"completedAt,omitempty"`
	TriggeredBy uint      `gorm:"index" json:"triggeredBy"` // User who triggered this execution
	ApprovedBy  *uint     `json:"approvedBy,omitempty"` // User who approved (if required)
	ApprovedAt  *time.Time `json:"approvedAt,omitempty"`
	TargetAgents string   `gorm:"type:text" json:"targetAgents"` // JSON array of agent IDs
	Result      string    `gorm:"type:text" json:"result"` // JSON object with execution results per agent
	ErrorMsg    string    `gorm:"type:text" json:"errorMsg"`
	CreatedAt   time.Time `json:"createdAt"`
	UpdatedAt   time.Time `json:"updatedAt"`

	// Relations
	Job      Job  `gorm:"foreignKey:JobID" json:"job,omitempty"`
	Trigger  User `gorm:"foreignKey:TriggeredBy" json:"trigger,omitempty"`
	Approver *User `gorm:"foreignKey:ApprovedBy" json:"approver,omitempty"`
}

func (JobExecution) TableName() string {
	return "job_executions"
}

// Script represents a managed script that can be executed on agents
type Script struct {
	ID          uint           `gorm:"primarykey" json:"id"`
	Name        string         `gorm:"size:100;not null" json:"name"`
	Description string         `gorm:"type:text" json:"description"`
	Language    string         `gorm:"size:20;not null" json:"language"` // "bash", "python", "powershell"
	Content     string         `gorm:"type:text;not null" json:"content"` // Script source code
	Checksum    string         `gorm:"size:64" json:"checksum"` // SHA256 of content
	Scope       string         `gorm:"type:text" json:"scope"` // Default target agent filter
	Timeout     int            `gorm:"default:300" json:"timeout"` // Default timeout in seconds
	IsSigned    bool           `gorm:"default:false" json:"isSigned"` // Code signing verification
	Signature   string         `gorm:"type:text" json:"signature"` // Digital signature
	CreatedBy   uint           `gorm:"index" json:"createdBy"`
	UpdatedBy   uint           `json:"updatedBy"`
	CreatedAt   time.Time      `json:"createdAt"`
	UpdatedAt   time.Time      `json:"updatedAt"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`

	// Relations
	Creator User `gorm:"foreignKey:CreatedBy" json:"creator,omitempty"`
	Updater User `gorm:"foreignKey:UpdatedBy" json:"updater,omitempty"`
}

func (Script) TableName() string {
	return "scripts"
}

// ConfigFile represents a managed configuration file with version control
type ConfigFile struct {
	ID          uint           `gorm:"primarykey" json:"id"`
	AgentID     string         `gorm:"size:50;index;not null" json:"agentId"`
	Path        string         `gorm:"size:500;not null" json:"path"` // File path on the agent
	Description string         `gorm:"type:text" json:"description"`
	Validated   bool           `gorm:"default:false" json:"validated"` // Syntax/semantic validation passed
	LastUpdatedBy uint         `gorm:"index" json:"lastUpdatedBy"`
	CreatedAt   time.Time      `json:"createdAt"`
	UpdatedAt   time.Time      `json:"updatedAt"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`

	// Relations
	LastUpdater User              `gorm:"foreignKey:LastUpdatedBy" json:"lastUpdater,omitempty"`
	Versions    []ConfigVersion   `gorm:"foreignKey:ConfigFileID" json:"versions,omitempty"`
}

func (ConfigFile) TableName() string {
	return "config_files"
}

// ConfigVersion represents a specific version of a configuration file
type ConfigVersion struct {
	ID           uint      `gorm:"primarykey" json:"id"`
	ConfigFileID uint      `gorm:"index;not null" json:"configFileId"`
	Version      int       `gorm:"not null" json:"version"` // Incremental version number
	Content      string    `gorm:"type:text;not null" json:"content"` // File content
	Checksum     string    `gorm:"size:64" json:"checksum"` // SHA256 of content
	Size         int64     `json:"size"` // Content size in bytes
	Comment      string    `gorm:"type:text" json:"comment"` // Change description
	CreatedBy    uint      `gorm:"index" json:"createdBy"`
	CreatedAt    time.Time `json:"createdAt"`

	// Relations
	ConfigFile ConfigFile `gorm:"foreignKey:ConfigFileID" json:"configFile,omitempty"`
	Creator    User       `gorm:"foreignKey:CreatedBy" json:"creator,omitempty"`
}

func (ConfigVersion) TableName() string {
	return "config_versions"
}

// HealthCheck represents a health check configuration for agents
type HealthCheck struct {
	ID          uint           `gorm:"primarykey" json:"id"`
	Name        string         `gorm:"size:100;not null" json:"name"`
	Type        string         `gorm:"size:50;not null" json:"type"` // "http", "tcp", "command", "script"
	Description string         `gorm:"type:text" json:"description"`
	Scope       string         `gorm:"type:text" json:"scope"` // Target agent filter
	Config      string         `gorm:"type:text;not null" json:"config"` // JSON config (URL, port, command, etc.)
	Interval    int            `gorm:"default:60" json:"interval"` // Check interval in seconds
	Timeout     int            `gorm:"default:10" json:"timeout"` // Check timeout in seconds
	Enabled     bool           `gorm:"default:true" json:"enabled"`
	CreatedBy   uint           `gorm:"index" json:"createdBy"`
	UpdatedBy   uint           `json:"updatedBy"`
	CreatedAt   time.Time      `json:"createdAt"`
	UpdatedAt   time.Time      `json:"updatedAt"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`

	// Relations
	Creator User                `gorm:"foreignKey:CreatedBy" json:"creator,omitempty"`
	Updater User                `gorm:"foreignKey:UpdatedBy" json:"updater,omitempty"`
	Results []HealthCheckResult `gorm:"foreignKey:HealthCheckID" json:"results,omitempty"`
}

func (HealthCheck) TableName() string {
	return "health_checks"
}

// HealthCheckResult stores health check execution results
type HealthCheckResult struct {
	ID            uint      `gorm:"primarykey" json:"id"`
	HealthCheckID uint      `gorm:"index;not null" json:"healthCheckId"`
	AgentID       string    `gorm:"size:50;index;not null" json:"agentId"`
	Status        string    `gorm:"size:20;not null" json:"status"` // "healthy", "unhealthy", "timeout", "error"
	Message       string    `gorm:"type:text" json:"message"`
	DurationMs    int64     `json:"durationMs"` // Execution duration in milliseconds
	CheckedAt     time.Time `gorm:"index;not null" json:"checkedAt"`

	// Relations
	HealthCheck HealthCheck `gorm:"foreignKey:HealthCheckID" json:"healthCheck,omitempty"`
}

func (HealthCheckResult) TableName() string {
	return "health_check_results"
}

// Package represents installed package information on agents
type Package struct {
	ID            uint      `gorm:"primarykey" json:"id"`
	AgentID       string    `gorm:"size:50;index;not null" json:"agentId"`
	Name          string    `gorm:"size:200;not null" json:"name"`
	CurrentVersion string   `gorm:"size:100" json:"currentVersion"`
	LatestVersion  string   `gorm:"size:100" json:"latestVersion"`
	IsSecurity    bool      `gorm:"default:false" json:"isSecurity"` // Security update available
	Size          int64     `json:"size"` // Package size in bytes
	UpdatedAt     time.Time `gorm:"index" json:"updatedAt"` // Last scanned/updated time
}

func (Package) TableName() string {
	return "packages"
}

// Incident represents an operational incident
type Incident struct {
	ID          uint           `gorm:"primarykey" json:"id"`
	Title       string         `gorm:"size:200;not null" json:"title"`
	Description string         `gorm:"type:text" json:"description"`
	Severity    string         `gorm:"size:20;not null" json:"severity"` // "critical", "high", "medium", "low"
	Status      string         `gorm:"size:20;not null" json:"status"` // "open", "investigating", "resolved", "closed"
	StartedAt   time.Time      `gorm:"index;not null" json:"startedAt"`
	ResolvedAt  *time.Time     `json:"resolvedAt,omitempty"`
	ClosedAt    *time.Time     `json:"closedAt,omitempty"`
	CreatedBy   uint           `gorm:"index" json:"createdBy"`
	AssignedTo  *uint          `gorm:"index" json:"assignedTo,omitempty"`
	RootCause   string         `gorm:"type:text" json:"rootCause"` // Post-mortem root cause
	Resolution  string         `gorm:"type:text" json:"resolution"` // How it was resolved
	RelatedAgents string       `gorm:"type:text" json:"relatedAgents"` // JSON array of affected agent IDs
	RelatedAlerts string       `gorm:"type:text" json:"relatedAlerts"` // JSON array of related alert IDs
	CreatedAt   time.Time      `json:"createdAt"`
	UpdatedAt   time.Time      `json:"updatedAt"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`

	// Relations
	Creator  User  `gorm:"foreignKey:CreatedBy" json:"creator,omitempty"`
	Assignee *User `gorm:"foreignKey:AssignedTo" json:"assignee,omitempty"`
}

func (Incident) TableName() string {
	return "incidents"
}
