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

	DeploymentTargetAuthPassword   = "password"
	DeploymentTargetAuthPrivateKey = "private_key"
)

// DeploymentTarget is an SSH destination reached by a connected Agent. The
// control-plane never dials the target directly: AgentID selects the outbound
// relay, which is useful when the NanoOps Server itself has no Internet or
// target-network access. Credential is encrypted by the server secret codec.
type DeploymentTarget struct {
	ID               uint      `gorm:"primarykey" json:"id"`
	Name             string    `gorm:"uniqueIndex;size:100;not null" json:"name"`
	AgentID          string    `gorm:"size:64;index;not null" json:"agentId"`
	Host             string    `gorm:"size:255;not null" json:"host"`
	Port             int       `gorm:"not null;default:22" json:"port"`
	Username         string    `gorm:"size:255;not null" json:"username"`
	AuthType         string    `gorm:"size:20;not null" json:"authType"`
	Credential       string    `gorm:"type:text" json:"-"`
	SSHKnownHosts    string    `gorm:"type:text" json:"sshKnownHosts,omitempty"`
	AllowUnknownHost bool      `gorm:"not null;default:false" json:"allowUnknownHost"`
	UseSudo          bool      `gorm:"not null;default:false" json:"useSudo"`
	CreatedBy        uint      `gorm:"index;not null" json:"createdBy"`
	CreatedAt        time.Time `json:"createdAt"`
	UpdatedAt        time.Time `json:"updatedAt"`
}

// DeploymentProject describes one remotely managed application. DeployPath is
// the release root on the target agent (for example /opt/nanolink/apps/orders).
type DeploymentProject struct {
	ID               uint      `gorm:"primarykey" json:"id"`
	Name             string    `gorm:"uniqueIndex;size:100;not null" json:"name"`
	Type             string    `gorm:"size:16;not null" json:"type"`
	AgentID          string    `gorm:"size:64;index;not null" json:"agentId"`
	TargetID         *uint     `gorm:"index" json:"targetId,omitempty"`
	DeployPath       string    `gorm:"size:500;not null" json:"deployPath"`
	ExtractArchive   bool      `gorm:"not null" json:"extractArchive"`
	ServiceName      string    `gorm:"size:160" json:"serviceName"`
	HealthURL        string    `gorm:"size:1000" json:"healthUrl"`
	KeepReleases     int       `gorm:"default:5;not null" json:"keepReleases"`
	CurrentReleaseID *string   `gorm:"size:36;index" json:"currentReleaseId,omitempty"`
	CreatedBy        uint      `gorm:"index;not null" json:"createdBy"`
	CreatedAt        time.Time `json:"createdAt"`
	UpdatedAt        time.Time `json:"updatedAt"`
}

// EnvironmentScript is a reusable, encrypted shell script executed over an
// external target's SSH connection. Script contents can contain bootstrap
// secrets, so they follow the same at-rest protection as SSH credentials.
type EnvironmentScript struct {
	ID             uint      `gorm:"primarykey" json:"id"`
	Name           string    `gorm:"uniqueIndex;size:100;not null" json:"name"`
	Description    string    `gorm:"size:500" json:"description"`
	TargetID       uint      `gorm:"index;not null" json:"targetId"`
	Content        string    `gorm:"type:text;not null" json:"-"`
	TimeoutSeconds int       `gorm:"not null;default:600" json:"timeoutSeconds"`
	CreatedBy      uint      `gorm:"index;not null" json:"createdBy"`
	CreatedAt      time.Time `json:"createdAt"`
	UpdatedAt      time.Time `json:"updatedAt"`

	Target DeploymentTarget `gorm:"foreignKey:TargetID" json:"target,omitempty"`
}

// EnvironmentScriptRun persists the audited result independently of the
// short-lived command-result cache.
type EnvironmentScriptRun struct {
	ID            string     `gorm:"primaryKey;size:36" json:"id"`
	ScriptID      uint       `gorm:"index;not null" json:"scriptId"`
	TargetID      uint       `gorm:"index;not null" json:"targetId"`
	AgentID       string     `gorm:"size:64;index;not null" json:"agentId"`
	CommandID     string     `gorm:"size:36;uniqueIndex" json:"commandId"`
	Status        string     `gorm:"size:16;index;not null" json:"status"`
	Output        string     `gorm:"type:text" json:"output"`
	Error         string     `gorm:"type:text" json:"error"`
	CreatedBy     uint       `gorm:"index;not null" json:"createdBy"`
	CreatedByName string     `gorm:"size:50" json:"createdByName"`
	CreatedAt     time.Time  `json:"createdAt"`
	StartedAt     *time.Time `json:"startedAt,omitempty"`
	FinishedAt    *time.Time `json:"finishedAt,omitempty"`

	Script EnvironmentScript `gorm:"foreignKey:ScriptID" json:"script,omitempty"`
	Target DeploymentTarget  `gorm:"foreignKey:TargetID" json:"target,omitempty"`
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

// DeploymentUploadSession persists the confirmed offset of a browser artifact
// upload. The corresponding .part file lives below the deployment storage root,
// so an interrupted transfer can continue after a browser or Server restart.
type DeploymentUploadSession struct {
	ID            string    `gorm:"primaryKey;size:36" json:"id"`
	ProjectID     uint      `gorm:"uniqueIndex:idx_deployment_upload_version;index;not null" json:"projectId"`
	Version       string    `gorm:"uniqueIndex:idx_deployment_upload_version;size:64;not null" json:"version"`
	ArtifactName  string    `gorm:"size:255;not null" json:"artifactName"`
	ArtifactSize  int64     `gorm:"not null" json:"artifactSize"`
	UploadedSize  int64     `gorm:"not null;default:0" json:"uploadOffset"`
	Extract       *bool     `json:"extract,omitempty"`
	StripTopLevel bool      `gorm:"not null;default:false" json:"stripTopLevel"`
	Notes         string    `gorm:"type:text" json:"notes"`
	CreatedBy     uint      `gorm:"index;not null" json:"createdBy"`
	ExpiresAt     time.Time `gorm:"index;not null" json:"expiresAt"`
	CreatedAt     time.Time `json:"createdAt"`
	UpdatedAt     time.Time `json:"updatedAt"`
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
