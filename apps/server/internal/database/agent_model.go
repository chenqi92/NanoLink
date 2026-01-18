package database

import (
	"time"

	"gorm.io/gorm"
)

// AgentToken represents a registered agent with its connection token
// Agents must have a token registered here before they can connect
type AgentToken struct {
	ID          uint           `gorm:"primarykey" json:"id"`
	Token       string         `gorm:"uniqueIndex;size:255;not null" json:"-"` // Hidden in JSON responses
	TokenHint   string         `gorm:"size:20" json:"tokenHint"`               // Last 4 chars for display
	Name        string         `gorm:"size:100" json:"name"`                   // Display name
	AgentID     string         `gorm:"size:100;index" json:"agentId"`          // Hardware-based agent ID after connection
	Hostname    string         `gorm:"size:255" json:"hostname"`               // Agent hostname
	OS          string         `gorm:"size:100" json:"os"`                     // Operating system
	Arch        string         `gorm:"size:50" json:"arch"`                    // Architecture
	Version     string         `gorm:"size:50" json:"version"`                 // Agent version
	Permission  int            `gorm:"default:0" json:"permission"`            // Permission level 0-3
	SortOrder   int            `gorm:"default:0" json:"sortOrder"`             // Display order (lower = first)
	CreatedAt   time.Time      `json:"createdAt"`
	UpdatedAt   time.Time      `json:"updatedAt"`
	ExpiresAt   *time.Time     `json:"expiresAt,omitempty"`   // Auto-delete if not connected
	FirstSeenAt *time.Time     `json:"firstSeenAt,omitempty"` // First connection time
	LastSeenAt  *time.Time     `json:"lastSeenAt,omitempty"`  // Last heartbeat time
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`
}

// TableName returns the table name for AgentToken
func (AgentToken) TableName() string {
	return "agent_tokens"
}

// IsOnline returns true if the agent was seen within the last 30 seconds
func (a *AgentToken) IsOnline() bool {
	if a.LastSeenAt == nil {
		return false
	}
	return time.Since(*a.LastSeenAt) < 30*time.Second
}

// MaskToken returns a masked version of the token for display
func MaskToken(token string) string {
	if len(token) <= 4 {
		return "****"
	}
	return "****" + token[len(token)-4:]
}
