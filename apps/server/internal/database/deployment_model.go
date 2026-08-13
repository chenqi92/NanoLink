package database

import "time"

const (
	DeploymentProjectJava   = "java"
	DeploymentProjectStatic = "static"

	DeploymentActionDeploy   = "deploy"
	DeploymentActionRollback = "rollback"

	DeploymentStatusQueued  = "queued"
	DeploymentStatusRunning = "running"
	DeploymentStatusSuccess = "success"
	DeploymentStatusFailed  = "failed"
)

// DeploymentProject describes one remotely managed application. DeployPath is
// the release root on the target agent (for example /opt/nanolink/apps/orders).
type DeploymentProject struct {
	ID               uint      `gorm:"primarykey" json:"id"`
	Name             string    `gorm:"uniqueIndex;size:100;not null" json:"name"`
	Type             string    `gorm:"size:16;not null" json:"type"`
	AgentID          string    `gorm:"size:64;index;not null" json:"agentId"`
	DeployPath       string    `gorm:"size:500;not null" json:"deployPath"`
	ServiceName      string    `gorm:"size:160" json:"serviceName"`
	HealthURL        string    `gorm:"size:1000" json:"healthUrl"`
	KeepReleases     int       `gorm:"default:5;not null" json:"keepReleases"`
	CurrentReleaseID *string   `gorm:"size:36;index" json:"currentReleaseId,omitempty"`
	CreatedBy        uint      `gorm:"index;not null" json:"createdBy"`
	CreatedAt        time.Time `json:"createdAt"`
	UpdatedAt        time.Time `json:"updatedAt"`
}

// DeploymentRelease is immutable metadata for a server-side artifact.
type DeploymentRelease struct {
	ID            string    `gorm:"primaryKey;size:36" json:"id"`
	ProjectID     uint      `gorm:"uniqueIndex:idx_project_version;index;not null" json:"projectId"`
	Version       string    `gorm:"uniqueIndex:idx_project_version;size:64;not null" json:"version"`
	ArtifactName  string    `gorm:"size:255;not null" json:"artifactName"`
	ArtifactPath  string    `gorm:"size:1000;not null" json:"-"`
	ArtifactSize  int64     `gorm:"not null" json:"artifactSize"`
	SHA256        string    `gorm:"size:64;not null" json:"sha256"`
	Extract       *bool     `json:"extract,omitempty"`
	StripTopLevel bool      `gorm:"not null;default:false" json:"stripTopLevel"`
	Notes         string    `gorm:"type:text" json:"notes"`
	CreatedBy     uint      `gorm:"index;not null" json:"createdBy"`
	CreatedAt     time.Time `json:"createdAt"`
}

// DeploymentTask persists every deploy/rollback attempt independently of the
// short-lived gRPC command-result cache.
type DeploymentTask struct {
	ID                   string     `gorm:"primaryKey;size:36" json:"id"`
	ProjectID            uint       `gorm:"index;not null" json:"projectId"`
	ReleaseID            string     `gorm:"size:36;index;not null" json:"releaseId"`
	AgentID              string     `gorm:"size:64;index;not null" json:"agentId"`
	CommandID            string     `gorm:"size:36;uniqueIndex" json:"commandId"`
	Action               string     `gorm:"size:16;not null" json:"action"`
	Status               string     `gorm:"size:16;index;not null" json:"status"`
	Output               string     `gorm:"type:text" json:"output"`
	Error                string     `gorm:"type:text" json:"error"`
	ArtifactTokenHash    string     `gorm:"size:64" json:"-"`
	ArtifactTokenExpires *time.Time `json:"-"`
	CreatedBy            uint       `gorm:"index;not null" json:"createdBy"`
	CreatedByName        string     `gorm:"size:50" json:"createdByName"`
	CreatedAt            time.Time  `json:"createdAt"`
	StartedAt            *time.Time `json:"startedAt,omitempty"`
	FinishedAt           *time.Time `json:"finishedAt,omitempty"`

	Project DeploymentProject `gorm:"foreignKey:ProjectID" json:"project,omitempty"`
	Release DeploymentRelease `gorm:"foreignKey:ReleaseID" json:"release,omitempty"`
}
