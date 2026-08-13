package database

import "time"

const (
	BuildSourceGit       = "git"
	BuildSourceURL       = "url"
	BuildSourceUpload    = "upload"
	BuildSourceAuthNone  = "none"
	BuildSourceAuthBasic = "basic"
	BuildSourceAuthSSH   = "ssh"

	BuildRunnerDocker = "docker"
	BuildRunnerHost   = "host"

	BuildTriggerManual   = "manual"
	BuildTriggerWebhook  = "webhook"
	BuildTriggerSchedule = "schedule"

	BuildStatusQueued   = "queued"
	BuildStatusRunning  = "running"
	BuildStatusSuccess  = "success"
	BuildStatusFailed   = "failed"
	BuildStatusCanceled = "canceled"
)

// BuildPipeline is the reusable control-plane definition for an automated
// packaging workflow. Complex fields are stored as validated JSON snapshots so
// an in-flight or historical run is not changed by later pipeline edits.
type BuildPipeline struct {
	ID                  uint       `gorm:"primarykey" json:"id"`
	Name                string     `gorm:"uniqueIndex;size:100;not null" json:"name"`
	Description         string     `gorm:"size:500" json:"description"`
	AgentID             string     `gorm:"size:64;index;not null" json:"agentId"`
	SourceType          string     `gorm:"size:16;not null" json:"sourceType"`
	SourceURL           string     `gorm:"size:2000" json:"sourceUrl"`
	SourceRef           string     `gorm:"size:255" json:"sourceRef"`
	SourceAuthType      string     `gorm:"size:16;not null;default:none" json:"sourceAuthType"`
	SourceUsername      string     `gorm:"size:255" json:"sourceUsername,omitempty"`
	SourceCredential    string     `gorm:"type:text" json:"-"`
	SourceSSHPublicKey  string     `gorm:"type:text" json:"sourceSshPublicKey,omitempty"`
	SourceSSHKnownHosts string     `gorm:"type:text" json:"sourceSshKnownHosts,omitempty"`
	RunnerType          string     `gorm:"size:16;not null" json:"runnerType"`
	ContainerImage      string     `gorm:"size:500" json:"containerImage"`
	StagesJSON          string     `gorm:"type:text;not null" json:"-"`
	VariablesJSON       string     `gorm:"type:text" json:"-"`
	ArtifactPattern     string     `gorm:"size:500;not null" json:"artifactPattern"`
	ArtifactName        string     `gorm:"size:255" json:"artifactName"`
	KeepArtifacts       int        `gorm:"default:20;not null" json:"keepArtifacts"`
	PublishProjectID    *uint      `gorm:"index" json:"publishProjectId,omitempty"`
	TimeoutSeconds      int        `gorm:"default:1800;not null" json:"timeoutSeconds"`
	Schedule            string     `gorm:"size:100" json:"schedule"`
	Enabled             bool       `gorm:"not null" json:"enabled"`
	WebhookTokenHash    string     `gorm:"size:64" json:"-"`
	WebhookTokenHint    string     `gorm:"size:12" json:"webhookTokenHint,omitempty"`
	LastRunAt           *time.Time `json:"lastRunAt,omitempty"`
	LastScheduledAt     *time.Time `json:"lastScheduledAt,omitempty"`
	CreatedBy           uint       `gorm:"index;not null" json:"createdBy"`
	CreatedAt           time.Time  `json:"createdAt"`
	UpdatedAt           time.Time  `json:"updatedAt"`
}

// BuildRun is an immutable execution snapshot plus its live/result state.
type BuildRun struct {
	ID                   string     `gorm:"primaryKey;size:36" json:"id"`
	PipelineID           uint       `gorm:"index;uniqueIndex:idx_pipeline_run_number;not null" json:"pipelineId"`
	RunNumber            int        `gorm:"uniqueIndex:idx_pipeline_run_number;not null" json:"runNumber"`
	AgentID              string     `gorm:"size:64;index;not null" json:"agentId"`
	CommandID            string     `gorm:"size:36;uniqueIndex" json:"commandId"`
	Status               string     `gorm:"size:16;index;not null" json:"status"`
	Trigger              string     `gorm:"size:16;not null" json:"trigger"`
	Version              string     `gorm:"size:64;not null" json:"version"`
	SourceType           string     `gorm:"size:16;not null" json:"sourceType"`
	SourceURL            string     `gorm:"size:2000" json:"sourceUrl"`
	SourceRef            string     `gorm:"size:255" json:"sourceRef"`
	SourceAuthType       string     `gorm:"size:16;not null;default:none" json:"sourceAuthType"`
	SourceUsername       string     `gorm:"size:255" json:"sourceUsername,omitempty"`
	SourceCredential     string     `gorm:"type:text" json:"-"`
	SourceSSHKnownHosts  string     `gorm:"type:text" json:"-"`
	SourceName           string     `gorm:"size:255" json:"sourceName"`
	SourcePath           string     `gorm:"size:1000" json:"-"`
	SourceSize           int64      `json:"sourceSize"`
	SourceSHA256         string     `gorm:"size:64" json:"sourceSha256"`
	RunnerType           string     `gorm:"size:16;not null" json:"runnerType"`
	ContainerImage       string     `gorm:"size:500" json:"containerImage"`
	StagesJSON           string     `gorm:"type:text;not null" json:"-"`
	VariablesJSON        string     `gorm:"type:text" json:"-"`
	ArtifactPattern      string     `gorm:"size:500;not null" json:"artifactPattern"`
	ArtifactName         string     `gorm:"size:255" json:"artifactName"`
	PublishProjectID     *uint      `gorm:"index" json:"publishProjectId,omitempty"`
	TimeoutSeconds       int        `gorm:"not null" json:"timeoutSeconds"`
	Output               string     `gorm:"type:text" json:"output"`
	Error                string     `gorm:"type:text" json:"error"`
	SourceTokenHash      string     `gorm:"size:64" json:"-"`
	SourceTokenExpires   *time.Time `json:"-"`
	ArtifactTokenHash    string     `gorm:"size:64" json:"-"`
	ArtifactTokenExpires *time.Time `json:"-"`
	CreatedBy            uint       `gorm:"index;not null" json:"createdBy"`
	CreatedByName        string     `gorm:"size:50" json:"createdByName"`
	CreatedAt            time.Time  `json:"createdAt"`
	StartedAt            *time.Time `json:"startedAt,omitempty"`
	FinishedAt           *time.Time `json:"finishedAt,omitempty"`

	Pipeline BuildPipeline  `gorm:"foreignKey:PipelineID" json:"pipeline,omitempty"`
	Artifact *BuildArtifact `gorm:"foreignKey:RunID" json:"artifact,omitempty"`
}

// BuildArtifact is the immutable package emitted by a successful build. When a
// pipeline publishes to Deployment Center, DeploymentReleaseID links the same
// verified file into the existing release flow without copying it again.
type BuildArtifact struct {
	ID                  string    `gorm:"primaryKey;size:36" json:"id"`
	RunID               string    `gorm:"uniqueIndex;size:36;not null" json:"runId"`
	Name                string    `gorm:"size:255;not null" json:"name"`
	Path                string    `gorm:"size:1000;not null" json:"-"`
	Size                int64     `gorm:"not null" json:"size"`
	SHA256              string    `gorm:"size:64;not null" json:"sha256"`
	DeploymentReleaseID *string   `gorm:"size:36;index" json:"deploymentReleaseId,omitempty"`
	CreatedAt           time.Time `json:"createdAt"`
}
