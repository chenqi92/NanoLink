package database

import (
	"time"

	"gorm.io/gorm"
)

// Role represents an IAM role with a set of permissions
type Role struct {
	ID          uint           `gorm:"primarykey" json:"id"`
	Name        string         `gorm:"uniqueIndex;size:100;not null" json:"name"` // e.g. "platform-owner", "ops-admin"
	DisplayName string         `gorm:"size:100" json:"displayName"`               // Human-readable name
	Description string         `gorm:"type:text" json:"description"`
	IsBuiltin   bool           `gorm:"default:false" json:"isBuiltin"`     // System role, cannot be deleted
	IsReadOnly  bool           `gorm:"default:false" json:"isReadOnly"`    // Read-only observer role
	IsDanger    bool           `gorm:"default:false" json:"isDanger"`      // Full admin/owner role
	Scope       string         `gorm:"type:text" json:"scope"`             // Default resource scope filter
	Conditions  string         `gorm:"type:text" json:"conditions"`        // Conditional constraints (JSON array)
	CreatedAt   time.Time      `json:"createdAt"`
	UpdatedAt   time.Time      `json:"updatedAt"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`

	// Relations
	Permissions []RolePermission `gorm:"foreignKey:RoleID" json:"permissions,omitempty"`
	Bindings    []RoleBinding    `gorm:"foreignKey:RoleID" json:"bindings,omitempty"`
}

func (Role) TableName() string {
	return "roles"
}

// RolePermission represents a permission grant within a role
type RolePermission struct {
	ID         uint           `gorm:"primarykey" json:"id"`
	RoleID     uint           `gorm:"index;not null" json:"roleId"`
	Permission string         `gorm:"size:100;not null" json:"permission"` // e.g. "node.read", "shell.execute", "deploy.*"
	Effect     string         `gorm:"size:10;default:allow" json:"effect"` // "allow" or "deny"
	CreatedAt  time.Time      `json:"createdAt"`
	DeletedAt  gorm.DeletedAt `gorm:"index" json:"-"`

	// Relations
	Role Role `gorm:"foreignKey:RoleID" json:"role,omitempty"`
}

func (RolePermission) TableName() string {
	return "role_permissions"
}

// Policy represents an IAM policy with conditions
type Policy struct {
	ID          uint           `gorm:"primarykey" json:"id"`
	Name        string         `gorm:"uniqueIndex;size:100;not null" json:"name"`
	DisplayName string         `gorm:"size:100" json:"displayName"`
	Description string         `gorm:"type:text" json:"description"`
	Effect      string         `gorm:"size:10;not null" json:"effect"` // "allow" or "deny"
	Actions     string         `gorm:"type:text" json:"actions"`       // JSON array of action patterns
	Resources   string         `gorm:"type:text" json:"resources"`     // Resource scope expression
	Conditions  string         `gorm:"type:text" json:"conditions"`    // Condition expression
	Priority    int            `gorm:"default:0" json:"priority"`      // Higher priority evaluated first
	Enabled     bool           `gorm:"default:true" json:"enabled"`
	ExpiresAt   *time.Time     `json:"expiresAt,omitempty"` // Temporary policy (e.g. break-glass)
	CreatedAt   time.Time      `json:"createdAt"`
	UpdatedAt   time.Time      `json:"updatedAt"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`

	// Relations
	Bindings []PolicyBinding `gorm:"foreignKey:PolicyID" json:"bindings,omitempty"`
}

func (Policy) TableName() string {
	return "policies"
}

// RoleBinding binds a role to a principal (user or group)
type RoleBinding struct {
	ID             uint           `gorm:"primarykey" json:"id"`
	RoleID         uint           `gorm:"index;not null" json:"roleId"`
	PrincipalType  string         `gorm:"size:20;not null" json:"principalType"`  // "user" or "group"
	PrincipalID    uint           `gorm:"index;not null" json:"principalId"`      // User ID or Group ID
	ResourceScope  string         `gorm:"type:text" json:"resourceScope"`         // Optional scope override
	GrantedBy      uint           `json:"grantedBy"`                              // Admin who created this binding
	CreatedAt      time.Time      `json:"createdAt"`
	UpdatedAt      time.Time      `json:"updatedAt"`
	DeletedAt      gorm.DeletedAt `gorm:"index" json:"-"`

	// Relations
	Role    Role  `gorm:"foreignKey:RoleID" json:"role,omitempty"`
	Granter User  `gorm:"foreignKey:GrantedBy" json:"granter,omitempty"`
}

func (RoleBinding) TableName() string {
	return "role_bindings"
}

// PolicyBinding attaches a policy to a principal
type PolicyBinding struct {
	ID            uint           `gorm:"primarykey" json:"id"`
	PolicyID      uint           `gorm:"index;not null" json:"policyId"`
	PrincipalType string         `gorm:"size:20;not null" json:"principalType"` // "user" or "group"
	PrincipalID   uint           `gorm:"index;not null" json:"principalId"`
	GrantedBy     uint           `json:"grantedBy"`
	CreatedAt     time.Time      `json:"createdAt"`
	UpdatedAt     time.Time      `json:"updatedAt"`
	DeletedAt     gorm.DeletedAt `gorm:"index" json:"-"`

	// Relations
	Policy  Policy `gorm:"foreignKey:PolicyID" json:"policy,omitempty"`
	Granter User   `gorm:"foreignKey:GrantedBy" json:"granter,omitempty"`
}

func (PolicyBinding) TableName() string {
	return "policy_bindings"
}

// NodeCapability represents the maximum permission ceiling for a specific node
// This is separate from user roles - it limits what operations the node itself allows
type NodeCapability struct {
	ID               uint           `gorm:"primarykey" json:"id"`
	AgentID          string         `gorm:"size:50;uniqueIndex;not null" json:"agentId"`
	MaxPermission    int            `gorm:"default:3" json:"maxPermission"`         // 0-3, node's capability ceiling
	AllowShell       bool           `gorm:"default:true" json:"allowShell"`         // Allow shell/terminal access
	AllowFileWrite   bool           `gorm:"default:true" json:"allowFileWrite"`     // Allow file uploads/modifications
	AllowReboot      bool           `gorm:"default:true" json:"allowReboot"`        // Allow system reboot
	AllowProcessKill bool           `gorm:"default:true" json:"allowProcessKill"`   // Allow killing processes
	CustomLimits     string         `gorm:"type:text" json:"customLimits"`          // JSON object of additional limits
	UpdatedBy        uint           `json:"updatedBy"`
	CreatedAt        time.Time      `json:"createdAt"`
	UpdatedAt        time.Time      `json:"updatedAt"`
	DeletedAt        gorm.DeletedAt `gorm:"index" json:"-"`

	// Relations
	Updater User `gorm:"foreignKey:UpdatedBy" json:"updater,omitempty"`
}

func (NodeCapability) TableName() string {
	return "node_capabilities"
}

// PermissionHistory tracks all permission changes for audit
type PermissionHistory struct {
	ID            uint      `gorm:"primarykey" json:"id"`
	Timestamp     time.Time `gorm:"index;not null" json:"timestamp"`
	ActorID       uint      `gorm:"index" json:"actorId"`
	ActorUsername string    `gorm:"size:50" json:"actorUsername"`
	Action        string    `gorm:"size:50;index" json:"action"` // "role.create", "binding.add", "policy.update", etc.
	TargetType    string    `gorm:"size:50" json:"targetType"`   // "role", "policy", "binding", "user", "group"
	TargetID      uint      `json:"targetId"`
	TargetName    string    `gorm:"size:100" json:"targetName"`
	Changes       string    `gorm:"type:text" json:"changes"` // JSON object of before/after
	IPAddress     string    `gorm:"size:50" json:"ipAddress"`
	Reason        string    `gorm:"type:text" json:"reason"` // Optional justification
}

func (PermissionHistory) TableName() string {
	return "permission_history"
}
