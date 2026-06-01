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
	// Guarantee at most one token row per (live) agent. Partial index so the many
	// admin-created tokens not yet bound to an agent (agent_id == '') don't collide.
	// This is what historically prevented duplicate/auto-mirrored token rows.
	if err := db.Exec(`CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_tokens_agent_id ` +
		`ON agent_tokens(agent_id) WHERE agent_id != '' AND deleted_at IS NULL`).Error; err != nil {
		logger.Warnf("Failed to create unique index on agent_tokens.agent_id: %v", err)
	}
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

// GetPaged returns a page of tokens ordered for display. limit<=0 returns all rows.
func (s *AgentTokenService) GetPaged(offset, limit int) ([]database.AgentToken, error) {
	var tokens []database.AgentToken
	q := s.db.Order("sort_order ASC, created_at DESC")
	if limit > 0 {
		q = q.Limit(limit).Offset(offset)
	}
	if err := q.Find(&tokens).Error; err != nil {
		return nil, err
	}
	return tokens, nil
}

// Stats returns aggregate counts for the token list header. Online status is
// derived from the live connection registry in the handler (single source of
// truth), not from a database timestamp.
func (s *AgentTokenService) Stats() (total, l3 int64, err error) {
	if err = s.db.Model(&database.AgentToken{}).Count(&total).Error; err != nil {
		return
	}
	err = s.db.Model(&database.AgentToken{}).Where("permission = ?", 3).Count(&l3).Error
	return
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
	if token.ExpiresAt != nil && token.ExpiresAt.Before(now) {
		s.logger.Warnf("Rejected expired agent token: %s", token.TokenHint)
		return nil, false
	}

	if agentID != "" && token.AgentID != "" && token.AgentID != agentID {
		s.logger.Warnf("Rejected agent token %s: bound to %s, got %s", token.TokenHint, token.AgentID, agentID)
		return nil, false
	}

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
	if agentID != "" && token.FirstSeenAt == nil {
		updates["first_seen_at"] = now
		updates["expires_at"] = nil // Clear expiry after first connection
	}

	if err := s.db.Model(&token).Updates(updates).Error; err != nil {
		s.logger.Errorf("Failed to update agent token: %v", err)
	}

	return &token, true
}

// UpdateLastSeen updates the last seen time and IP for an agent
func (s *AgentTokenService) UpdateLastSeen(agentID string, ip string) {
	now := time.Now()
	updates := map[string]interface{}{
		"last_seen_at": now,
	}
	if ip != "" {
		updates["last_ip"] = ip
	}
	s.db.Model(&database.AgentToken{}).Where("agent_id = ?", agentID).Updates(updates)
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

// CleanupStaleAnonymous removes auto-created tokens that were never properly
// identified (no name) and have not been seen for a while — the residue of
// agents that connected without a persistent agent_id. Named tokens (real,
// admin-managed agents) are never touched.
func (s *AgentTokenService) CleanupStaleAnonymous() (int64, error) {
	cutoff := time.Now().Add(-7 * 24 * time.Hour)
	result := s.db.Where("(name IS NULL OR name = '') AND (last_seen_at IS NULL OR last_seen_at < ?)", cutoff).Delete(&database.AgentToken{})
	if result.Error != nil {
		return 0, result.Error
	}
	if result.RowsAffected > 0 {
		s.logger.Infof("Cleaned up %d stale anonymous agent tokens", result.RowsAffected)
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

	// No token row bound to this agent_id. Under token auth the agent has already
	// authenticated with a valid token that gets bound to its agent_id during the
	// stream handshake, so a miss here means an agent that does not persist its
	// agent_id (legacy) — auto-minting a token on every such reconnect is exactly
	// what ballooned this table to thousands of rows. Skip instead of creating;
	// tokens are only issued via the admin "create token" / pairing flow.
	s.logger.Warnf("EnsureAgentExists: no token bound to agent_id %s (%s); not auto-creating", agentID, hostname)
	return nil, nil
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
			if _, err := s.CleanupStaleAnonymous(); err != nil {
				s.logger.Errorf("Failed to cleanup stale anonymous tokens: %v", err)
			}
		}
	}()
	s.logger.Info("Started agent token cleanup job (runs every hour)")
}
