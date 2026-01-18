package service

import (
	"crypto/rand"
	"encoding/hex"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// AgentTokenService manages agent tokens
type AgentTokenService struct {
	db     *gorm.DB
	logger *zap.SugaredLogger
}

// NewAgentTokenService creates a new agent token service
func NewAgentTokenService(db *gorm.DB, logger *zap.SugaredLogger) *AgentTokenService {
	return &AgentTokenService{
		db:     db,
		logger: logger,
	}
}

// GenerateToken generates a secure random token
func GenerateToken() (string, error) {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}

// Create creates a new agent token
func (s *AgentTokenService) Create(name string, permission int) (*database.AgentToken, string, error) {
	token, err := GenerateToken()
	if err != nil {
		return nil, "", err
	}

	// Set expiry to 24 hours from now (will be cleared on first connection)
	expiresAt := time.Now().Add(24 * time.Hour)

	agentToken := &database.AgentToken{
		Token:      token,
		TokenHint:  database.MaskToken(token),
		Name:       name,
		Permission: permission,
		ExpiresAt:  &expiresAt,
	}

	if err := s.db.Create(agentToken).Error; err != nil {
		return nil, "", err
	}

	s.logger.Infof("Created new agent token: %s (name: %s)", agentToken.TokenHint, name)
	return agentToken, token, nil // Return full token only on creation
}

// GetByID retrieves an agent token by ID
func (s *AgentTokenService) GetByID(id uint) (*database.AgentToken, error) {
	var token database.AgentToken
	if err := s.db.First(&token, id).Error; err != nil {
		return nil, err
	}
	return &token, nil
}

// GetByToken retrieves an agent token by the token string
func (s *AgentTokenService) GetByToken(tokenStr string) (*database.AgentToken, error) {
	var token database.AgentToken
	if err := s.db.Where("token = ?", tokenStr).First(&token).Error; err != nil {
		return nil, err
	}
	return &token, nil
}

// GetByAgentID retrieves an agent token by the agent's hardware ID
func (s *AgentTokenService) GetByAgentID(agentID string) (*database.AgentToken, error) {
	var token database.AgentToken
	if err := s.db.Where("agent_id = ?", agentID).First(&token).Error; err != nil {
		return nil, err
	}
	return &token, nil
}

// GetAll retrieves all agent tokens ordered by SortOrder
func (s *AgentTokenService) GetAll() ([]database.AgentToken, error) {
	var tokens []database.AgentToken
	if err := s.db.Order("sort_order ASC, created_at DESC").Find(&tokens).Error; err != nil {
		return nil, err
	}
	return tokens, nil
}

// Update updates an agent token
func (s *AgentTokenService) Update(id uint, name string, permission int) error {
	return s.db.Model(&database.AgentToken{}).Where("id = ?", id).Updates(map[string]interface{}{
		"name":       name,
		"permission": permission,
	}).Error
}

// Delete deletes an agent token
func (s *AgentTokenService) Delete(id uint) error {
	return s.db.Delete(&database.AgentToken{}, id).Error
}

// RegenerateToken regenerates the token for an agent
func (s *AgentTokenService) RegenerateToken(id uint) (string, error) {
	token, err := GenerateToken()
	if err != nil {
		return "", err
	}

	if err := s.db.Model(&database.AgentToken{}).Where("id = ?", id).Updates(map[string]interface{}{
		"token":      token,
		"token_hint": database.MaskToken(token),
	}).Error; err != nil {
		return "", err
	}

	s.logger.Infof("Regenerated token for agent ID %d", id)
	return token, nil
}

// ValidateAndUpdateToken validates a token and updates the agent info
// Returns the token record and permission level if valid
func (s *AgentTokenService) ValidateAndUpdateToken(tokenStr string, agentID string, hostname string, os string, arch string, version string) (*database.AgentToken, bool) {
	var token database.AgentToken
	if err := s.db.Where("token = ?", tokenStr).First(&token).Error; err != nil {
		return nil, false
	}

	now := time.Now()

	// Update agent info on connection
	updates := map[string]interface{}{
		"last_seen_at": now,
	}

	// Update agent details if provided
	if agentID != "" {
		updates["agent_id"] = agentID
	}
	if hostname != "" {
		updates["hostname"] = hostname
	}
	if os != "" {
		updates["os"] = os
	}
	if arch != "" {
		updates["arch"] = arch
	}
	if version != "" {
		updates["version"] = version
	}

	// Clear expiry and set first seen on first connection
	if token.FirstSeenAt == nil {
		updates["first_seen_at"] = now
		updates["expires_at"] = nil // Clear expiry after first connection
	}

	if err := s.db.Model(&token).Updates(updates).Error; err != nil {
		s.logger.Errorf("Failed to update agent token: %v", err)
	}

	return &token, true
}

// UpdateLastSeen updates the last seen time for an agent
func (s *AgentTokenService) UpdateLastSeen(agentID string) {
	now := time.Now()
	s.db.Model(&database.AgentToken{}).Where("agent_id = ?", agentID).Update("last_seen_at", now)
}

// CleanupExpired removes tokens that have expired AND were never connected
func (s *AgentTokenService) CleanupExpired() (int64, error) {
	// Only delete if expired AND never connected (first_seen_at is NULL)
	result := s.db.Where("expires_at IS NOT NULL AND expires_at < ? AND first_seen_at IS NULL", time.Now()).Delete(&database.AgentToken{})
	if result.Error != nil {
		return 0, result.Error
	}
	if result.RowsAffected > 0 {
		s.logger.Infof("Cleaned up %d expired never-connected agent tokens", result.RowsAffected)
	}
	return result.RowsAffected, nil
}

// Reorder updates the sort order of agent tokens
func (s *AgentTokenService) Reorder(orderedIDs []uint) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		for i, id := range orderedIDs {
			if err := tx.Model(&database.AgentToken{}).Where("id = ?", id).Update("sort_order", i).Error; err != nil {
				return err
			}
		}
		return nil
	})
}

// EnsureAgentExists creates or updates an agent record when it connects
// This is called automatically when an agent connects via gRPC
func (s *AgentTokenService) EnsureAgentExists(agentID, hostname, os, arch, version string, permission int) (*database.AgentToken, error) {
	var token database.AgentToken
	now := time.Now()

	// Try to find existing agent by AgentID
	err := s.db.Where("agent_id = ?", agentID).First(&token).Error
	if err == nil {
		// Agent exists, update last seen
		s.db.Model(&token).Updates(map[string]interface{}{
			"hostname":     hostname,
			"os":           os,
			"arch":         arch,
			"version":      version,
			"last_seen_at": now,
		})
		return &token, nil
	}

	if err != gorm.ErrRecordNotFound {
		return nil, err
	}

	// Agent doesn't exist, create new record (auto-generated token)
	newToken, _ := GenerateToken()

	// Get max sort order to place new agent at the end
	var maxOrder int
	s.db.Model(&database.AgentToken{}).Select("COALESCE(MAX(sort_order), 0)").Scan(&maxOrder)

	token = database.AgentToken{
		Token:       newToken,
		TokenHint:   database.MaskToken(newToken),
		Name:        hostname, // Use hostname as default name
		AgentID:     agentID,
		Hostname:    hostname,
		OS:          os,
		Arch:        arch,
		Version:     version,
		Permission:  permission,
		SortOrder:   maxOrder + 1,
		FirstSeenAt: &now,
		LastSeenAt:  &now,
	}

	if err := s.db.Create(&token).Error; err != nil {
		return nil, err
	}

	s.logger.Infof("Auto-created agent record for %s (%s)", hostname, agentID)
	return &token, nil
}

// StartCleanupJob starts a background job to clean up expired tokens
func (s *AgentTokenService) StartCleanupJob() {
	go func() {
		ticker := time.NewTicker(1 * time.Hour)
		defer ticker.Stop()

		for range ticker.C {
			if _, err := s.CleanupExpired(); err != nil {
				s.logger.Errorf("Failed to cleanup expired tokens: %v", err)
			}
		}
	}()
	s.logger.Info("Started agent token cleanup job (runs every hour)")
}
