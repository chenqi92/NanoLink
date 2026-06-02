package database

import (
	"crypto/sha256"
	"encoding/hex"
	"strings"

	"go.uber.org/zap"
	"gorm.io/gorm"
)

// tokenHashPrefix tags a stored token as hashed-at-rest, so plaintext rows from
// older schema versions can be detected and migrated. It also keeps the stored
// value self-describing across drivers.
const tokenHashPrefix = "sha256:"

// HashToken returns the at-rest representation of an agent/device token.
// Tokens are high-entropy (256-bit) random values, so a single SHA-256 is
// sufficient (no need for a slow KDF) and lets lookups stay an indexed equality
// match. The plaintext is shown to the operator only once at creation; only the
// hash is ever persisted.
func HashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return tokenHashPrefix + hex.EncodeToString(sum[:])
}

// IsHashedToken reports whether a stored value is already in hashed form.
func IsHashedToken(stored string) bool {
	return strings.HasPrefix(stored, tokenHashPrefix)
}

// MigratePlaintextTokens rewrites any agent/device tokens still stored in
// plaintext (pre-hash schema) to their hashed form. It is idempotent:
// already-hashed rows match the prefix and are skipped, so it is safe to run on
// every startup.
func MigratePlaintextTokens(db *gorm.DB, log *zap.SugaredLogger) error {
	var agentTokens []AgentToken
	if err := db.Where("token NOT LIKE ?", tokenHashPrefix+"%").Find(&agentTokens).Error; err != nil {
		return err
	}
	migratedAgents := 0
	for _, t := range agentTokens {
		if t.Token == "" || IsHashedToken(t.Token) {
			continue
		}
		hint := t.TokenHint
		if hint == "" {
			hint = MaskToken(t.Token)
		}
		if err := db.Model(&AgentToken{}).Where("id = ?", t.ID).Updates(map[string]interface{}{
			"token":      HashToken(t.Token),
			"token_hint": hint,
		}).Error; err != nil {
			return err
		}
		migratedAgents++
	}

	var deviceTokens []DeviceToken
	if err := db.Where("token NOT LIKE ?", tokenHashPrefix+"%").Find(&deviceTokens).Error; err != nil {
		return err
	}
	migratedDevices := 0
	for _, t := range deviceTokens {
		if t.Token == "" || IsHashedToken(t.Token) {
			continue
		}
		if err := db.Model(&DeviceToken{}).Where("id = ?", t.ID).Update("token", HashToken(t.Token)).Error; err != nil {
			return err
		}
		migratedDevices++
	}

	if migratedAgents > 0 || migratedDevices > 0 {
		log.Infof("Token migration: hashed %d agent and %d device plaintext tokens at rest", migratedAgents, migratedDevices)
	}
	return nil
}
