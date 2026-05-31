package database

import "time"

// AlertRule defines a threshold rule evaluated against live agent metrics.
// Metric: cpu | memory | disk | offline. Operator: gt | lt (ignored for offline).
type AlertRule struct {
	ID          uint      `gorm:"primarykey" json:"id"`
	Name        string    `gorm:"size:100;not null" json:"name"`
	Metric      string    `gorm:"size:20;not null" json:"metric"`
	Operator    string    `gorm:"size:4;default:'gt'" json:"operator"`
	Threshold   float64   `gorm:"default:0" json:"threshold"`
	DurationSec int       `gorm:"default:0" json:"durationSec"`
	Severity    string    `gorm:"size:10;default:'warn'" json:"severity"`
	Scope       string    `gorm:"size:120;default:'all'" json:"scope"`
	Enabled     bool      `gorm:"default:true" json:"enabled"`
	CreatedAt   time.Time `json:"createdAt"`
	UpdatedAt   time.Time `json:"updatedAt"`
}

// AlertInstance is a firing/acked/resolved occurrence of a rule on an agent.
type AlertInstance struct {
	ID            uint       `gorm:"primarykey" json:"id"`
	RuleID        uint       `gorm:"index" json:"ruleId"`
	RuleName      string     `gorm:"size:100" json:"ruleName"`
	AgentID       string     `gorm:"size:64;index" json:"agentId"`
	AgentHostname string     `gorm:"size:255" json:"agentHostname"`
	Level         string     `gorm:"size:10" json:"level"`
	Title         string     `gorm:"size:255" json:"title"`
	Description   string     `gorm:"size:500" json:"description"`
	Value         float64    `json:"value"`
	Status        string     `gorm:"size:12;index;default:'firing'" json:"status"`
	AckBy         string     `gorm:"size:50" json:"ackBy"`
	AckedAt       *time.Time `json:"ackedAt,omitempty"`
	FirstSeenAt   time.Time  `json:"firstSeenAt"`
	LastSeenAt    time.Time  `json:"lastSeenAt"`
}

// NotifyChannel is a notification destination (slack/email/webhook/...).
type NotifyChannel struct {
	ID        uint      `gorm:"primarykey" json:"id"`
	Kind      string    `gorm:"size:20;not null" json:"kind"`
	Name      string    `gorm:"size:100;not null" json:"name"`
	Target    string    `gorm:"size:500" json:"target"`
	Enabled   bool      `gorm:"default:true" json:"enabled"`
	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`
}
