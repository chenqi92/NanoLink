package database

import (
	"time"

	"gorm.io/gorm"
)

// LLMProfile represents a saved LLM provider configuration
type LLMProfile struct {
	ID          uint           `gorm:"primarykey" json:"id"`
	Name        string         `gorm:"size:100;not null" json:"name"`
	Provider    string         `gorm:"size:50;not null" json:"provider"` // anthropic, openai, openai-compatible, zhipu, qwen, deepseek, moonshot, ernie
	Model       string         `gorm:"size:100;not null" json:"model"`
	BaseURL     string         `gorm:"size:500" json:"baseUrl"`
	APIKey      string         `gorm:"type:text" json:"-"` // Encrypted, never sent to frontend
	MaxTokens   int            `gorm:"default:4096" json:"maxTokens"`
	IsActive    bool           `gorm:"default:false" json:"isActive"` // Only one profile can be active at a time
	CreatedAt   time.Time      `json:"createdAt"`
	UpdatedAt   time.Time      `json:"updatedAt"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`
}

func (LLMProfile) TableName() string {
	return "llm_profiles"
}
