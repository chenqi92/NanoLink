package database

import (
	"time"

	"gorm.io/gorm"
)

// User represents a system user
type User struct {
	ID           uint           `gorm:"primarykey" json:"id"`
	Username     string         `gorm:"uniqueIndex;size:50;not null" json:"username"`
	PasswordHash string         `gorm:"size:255;not null" json:"-"`
	Email        string         `gorm:"uniqueIndex;size:255" json:"email"`
	IsSuperAdmin bool           `gorm:"default:false" json:"isSuperAdmin"`
	CreatedAt    time.Time      `json:"createdAt"`
	UpdatedAt    time.Time      `json:"updatedAt"`
	DeletedAt    gorm.DeletedAt `gorm:"index" json:"-"`

	// Relations
	Groups []Group `gorm:"many2many:user_groups;" json:"groups,omitempty"`
}

// Group represents a user group for organizing access to agents
type Group struct {
	ID          uint           `gorm:"primarykey" json:"id"`
	Name        string         `gorm:"uniqueIndex;size:100;not null" json:"name"`
	Description string         `gorm:"size:500" json:"description"`
	CreatedAt   time.Time      `json:"createdAt"`
	UpdatedAt   time.Time      `json:"updatedAt"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`

	// Relations
	Users []User `gorm:"many2many:user_groups;" json:"users,omitempty"`
}

// AgentGroup represents the association between an agent and a group
// This determines which group can see which agent and with what max permission level
type AgentGroup struct {
	ID              uint           `gorm:"primarykey" json:"id"`
	AgentID         string         `gorm:"size:50;index;not null" json:"agentId"`
	GroupID         uint           `gorm:"index;not null" json:"groupId"`
	PermissionLevel int            `gorm:"default:0" json:"permissionLevel"` // 0-3, max permission for this group
	CreatedAt       time.Time      `json:"createdAt"`
	UpdatedAt       time.Time      `json:"updatedAt"`
	DeletedAt       gorm.DeletedAt `gorm:"index" json:"-"`

	// Relations
	Group Group `gorm:"foreignKey:GroupID" json:"group,omitempty"`
}

// UserAgentPermission represents a specific permission grant from superadmin to user for an agent
type UserAgentPermission struct {
	ID              uint           `gorm:"primarykey" json:"id"`
	UserID          uint           `gorm:"index;not null" json:"userId"`
	AgentID         string         `gorm:"size:50;index;not null" json:"agentId"`
	PermissionLevel int            `gorm:"default:0" json:"permissionLevel"` // 0=READ_ONLY, 1=BASIC_WRITE, 2=SERVICE_CONTROL, 3=SYSTEM_ADMIN
	GrantedBy       uint           `json:"grantedBy"`                        // SuperAdmin who granted this permission
	CreatedAt       time.Time      `json:"createdAt"`
	UpdatedAt       time.Time      `json:"updatedAt"`
	DeletedAt       gorm.DeletedAt `gorm:"index" json:"-"`

	// Relations
	User    User `gorm:"foreignKey:UserID" json:"user,omitempty"`
	Granter User `gorm:"foreignKey:GrantedBy" json:"granter,omitempty"`
}

// Permission level constants
const (
	PermissionReadOnly       = 0 // Read monitoring data, view process list, view logs
	PermissionBasicWrite     = 1 // Download logs, clean temp files, upload files
	PermissionServiceControl = 2 // Restart services, restart Docker containers, kill processes
	PermissionSystemAdmin    = 3 // Reboot server, execute shell commands (requires SuperToken)
)

// PermissionLevelName returns the human-readable name for a permission level
func PermissionLevelName(level int) string {
	switch level {
	case PermissionReadOnly:
		return "READ_ONLY"
	case PermissionBasicWrite:
		return "BASIC_WRITE"
	case PermissionServiceControl:
		return "SERVICE_CONTROL"
	case PermissionSystemAdmin:
		return "SYSTEM_ADMIN"
	default:
		return "UNKNOWN"
	}
}

// TableName overrides for junction table
func (User) TableName() string {
	return "users"
}

func (Group) TableName() string {
	return "groups"
}

func (AgentGroup) TableName() string {
	return "agent_groups"
}

func (UserAgentPermission) TableName() string {
	return "user_agent_permissions"
}

// AuditLog represents an operation audit record
type AuditLog struct {
	ID            uint      `gorm:"primarykey" json:"id"`
	Timestamp     time.Time `gorm:"index;not null" json:"timestamp"`
	UserID        uint      `gorm:"index" json:"userId"`
	Username      string    `gorm:"size:50;index" json:"username"`
	AgentID       string    `gorm:"size:50;index" json:"agentId"`
	AgentHostname string    `gorm:"size:255" json:"agentHostname"`
	CommandType   string    `gorm:"size:50;index" json:"commandType"`
	CommandID     string    `gorm:"size:50;index" json:"commandId"`
	Target        string    `gorm:"size:500" json:"target"`        // What was operated on (service name, file path, etc.)
	Params        string    `gorm:"type:text" json:"params"`       // JSON params
	Success       bool      `gorm:"default:false" json:"success"`
	Error         string    `gorm:"type:text" json:"error"`
	DurationMs    int64     `gorm:"default:0" json:"durationMs"`
	IPAddress     string    `gorm:"size:50" json:"ipAddress"`
}

func (AuditLog) TableName() string {
	return "audit_logs"
}
