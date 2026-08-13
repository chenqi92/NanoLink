package service

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"net/url"
	"os"
	"strconv"
	"strings"
	"unicode"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"gorm.io/gorm"
)

const (
	llmSettingEnabled   = "llm.enabled"
	llmSettingProvider  = "llm.provider"
	llmSettingModel     = "llm.model"
	llmSettingBaseURL   = "llm.base_url"
	llmSettingMaxTokens = "llm.max_tokens"
	llmSettingAPIKey    = "llm.api_key"
	llmSecretPrefix     = "enc:v1:"
)

var llmSettingKeys = []string{
	llmSettingEnabled,
	llmSettingProvider,
	llmSettingModel,
	llmSettingBaseURL,
	llmSettingMaxTokens,
	llmSettingAPIKey,
}

// ErrInvalidLLMSettings distinguishes user input errors from persistence or
// encryption failures so handlers can return a safe 400 response.
var ErrInvalidLLMSettings = errors.New("invalid LLM settings")

// LLMSettingsView contains the editable provider settings but never the API
// key. APIKeySource is one of "stored", "environment", or "none".
type LLMSettingsView struct {
	Enabled          bool   `json:"enabled"`
	Provider         string `json:"provider"`
	Model            string `json:"model"`
	BaseURL          string `json:"baseUrl"`
	MaxTokens        int    `json:"maxTokens"`
	APIKeyConfigured bool   `json:"apiKeyConfigured"`
	APIKeySource     string `json:"apiKeySource"`
}

// LLMSettingsUpdate is the complete editable settings document. An empty
// APIKey preserves the existing secret unless ClearAPIKey is true.
type LLMSettingsUpdate struct {
	Enabled     bool   `json:"enabled"`
	Provider    string `json:"provider"`
	Model       string `json:"model"`
	BaseURL     string `json:"baseUrl"`
	MaxTokens   int    `json:"maxTokens"`
	APIKey      string `json:"apiKey"`
	ClearAPIKey bool   `json:"clearApiKey"`
}

// LLMSettingsManager persists dashboard-managed provider settings and applies
// them to the live client. Secrets are encrypted with AES-GCM using a key
// derived from the server JWT secret, and are never exposed through View.
type LLMSettingsManager struct {
	db       *gorm.DB
	client   *LLMClient
	defaults LLMConfig
	aead     cipher.AEAD
}

func NewLLMSettingsManager(db *gorm.DB, client *LLMClient, defaults LLMConfig, masterSecret string) (*LLMSettingsManager, error) {
	if db == nil || client == nil {
		return nil, errors.New("LLM settings require a database and client")
	}
	if strings.TrimSpace(masterSecret) == "" {
		return nil, errors.New("LLM settings encryption requires the server JWT secret")
	}
	if defaults.APIKey == "" {
		defaults.APIKey = os.Getenv("NANOLINK_LLM_API_KEY")
	}
	defaults = normalizeLLMRuntimeConfig(defaults)

	key := sha256.Sum256([]byte("nanoops/llm-settings/v1\x00" + masterSecret))
	block, err := aes.NewCipher(key[:])
	if err != nil {
		return nil, err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	return &LLMSettingsManager{db: db, client: client, defaults: defaults, aead: aead}, nil
}

// Reload loads persisted settings and atomically applies them to the live LLM
// client. It is called once during startup and after every successful update.
func (m *LLMSettingsManager) Reload(ctx context.Context) (LLMSettingsView, error) {
	cfg, source, err := m.load(ctx)
	if err != nil {
		return LLMSettingsView{}, err
	}
	m.client.Configure(cfg)
	return llmSettingsView(cfg, source), nil
}

// Current returns the persisted/effective non-secret settings.
func (m *LLMSettingsManager) Current(ctx context.Context) (LLMSettingsView, error) {
	cfg, source, err := m.load(ctx)
	if err != nil {
		return LLMSettingsView{}, err
	}
	return llmSettingsView(cfg, source), nil
}

// Test sends a minimal request using the effective saved configuration.
func (m *LLMSettingsManager) Test(ctx context.Context) error {
	return m.client.Test(ctx)
}

// Update validates and stores the full provider document, preserving the
// existing API key when no new secret is supplied.
func (m *LLMSettingsManager) Update(ctx context.Context, update LLMSettingsUpdate) (LLMSettingsView, error) {
	normalized, err := validateLLMSettingsUpdate(update)
	if err != nil {
		return LLMSettingsView{}, fmt.Errorf("%w: %v", ErrInvalidLLMSettings, err)
	}
	if update.ClearAPIKey && strings.TrimSpace(update.APIKey) != "" {
		return LLMSettingsView{}, fmt.Errorf("%w: apiKey and clearApiKey cannot be used together", ErrInvalidLLMSettings)
	}
	if len(strings.TrimSpace(update.APIKey)) > 16*1024 {
		return LLMSettingsView{}, fmt.Errorf("%w: API key is too long", ErrInvalidLLMSettings)
	}

	err = m.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		values := map[string]string{
			llmSettingEnabled:   strconv.FormatBool(normalized.Enabled),
			llmSettingProvider:  normalized.Provider,
			llmSettingModel:     normalized.Model,
			llmSettingBaseURL:   normalized.BaseURL,
			llmSettingMaxTokens: strconv.Itoa(normalized.MaxTokens),
		}
		for key, value := range values {
			if err := tx.Save(&database.Setting{Key: key, Value: value}).Error; err != nil {
				return err
			}
		}

		if update.ClearAPIKey {
			return tx.Delete(&database.Setting{}, "key = ?", llmSettingAPIKey).Error
		}
		if apiKey := strings.TrimSpace(update.APIKey); apiKey != "" {
			sealed, err := m.encrypt(apiKey)
			if err != nil {
				return err
			}
			return tx.Save(&database.Setting{Key: llmSettingAPIKey, Value: sealed}).Error
		}
		return nil
	})
	if err != nil {
		return LLMSettingsView{}, err
	}
	return m.Reload(ctx)
}

func (m *LLMSettingsManager) load(ctx context.Context) (LLMConfig, string, error) {
	var rows []database.Setting
	if err := m.db.WithContext(ctx).Where("key IN ?", llmSettingKeys).Find(&rows).Error; err != nil {
		return LLMConfig{}, "none", err
	}
	values := make(map[string]string, len(rows))
	for _, row := range rows {
		values[row.Key] = row.Value
	}

	cfg := m.defaults
	if raw, ok := values[llmSettingEnabled]; ok {
		value, err := strconv.ParseBool(raw)
		if err != nil {
			return LLMConfig{}, "none", fmt.Errorf("invalid stored llm.enabled: %w", err)
		}
		cfg.Enabled = value
	}
	if value, ok := values[llmSettingProvider]; ok {
		cfg.Provider = value
	}
	if value, ok := values[llmSettingModel]; ok {
		cfg.Model = value
	}
	if value, ok := values[llmSettingBaseURL]; ok {
		cfg.BaseURL = value
	}
	if raw, ok := values[llmSettingMaxTokens]; ok {
		value, err := strconv.Atoi(raw)
		if err != nil {
			return LLMConfig{}, "none", fmt.Errorf("invalid stored llm.max_tokens: %w", err)
		}
		cfg.MaxTokens = value
	}

	keySource := "none"
	if sealed, ok := values[llmSettingAPIKey]; ok {
		plain, err := m.decrypt(sealed)
		if err != nil {
			return LLMConfig{}, "none", fmt.Errorf("decrypt stored LLM API key: %w", err)
		}
		cfg.APIKey = plain
		keySource = "stored"
	} else if cfg.APIKey != "" {
		keySource = "environment"
	}
	apiKey := cfg.APIKey
	normalized, err := validateLLMSettingsUpdate(LLMSettingsUpdate{
		Enabled:   cfg.Enabled,
		Provider:  cfg.Provider,
		Model:     cfg.Model,
		BaseURL:   cfg.BaseURL,
		MaxTokens: cfg.MaxTokens,
	})
	if err != nil {
		return LLMConfig{}, "none", fmt.Errorf("invalid effective LLM settings: %w", err)
	}
	normalized.APIKey = apiKey
	return normalized, keySource, nil
}

func llmSettingsView(cfg LLMConfig, source string) LLMSettingsView {
	return LLMSettingsView{
		Enabled:          cfg.Enabled,
		Provider:         cfg.Provider,
		Model:            cfg.Model,
		BaseURL:          cfg.BaseURL,
		MaxTokens:        cfg.MaxTokens,
		APIKeyConfigured: cfg.APIKey != "",
		APIKeySource:     source,
	}
}

func validateLLMSettingsUpdate(update LLMSettingsUpdate) (LLMConfig, error) {
	provider := strings.ToLower(strings.TrimSpace(update.Provider))
	if _, ok := providerByID(provider); !ok {
		return LLMConfig{}, errors.New("provider is not supported")
	}
	model := strings.TrimSpace(update.Model)
	if len(model) > 200 || strings.IndexFunc(model, unicode.IsControl) >= 0 {
		return LLMConfig{}, errors.New("model is invalid")
	}
	if update.Enabled && model == "" {
		return LLMConfig{}, errors.New("model is required when the assistant is enabled")
	}
	if update.MaxTokens < 1 || update.MaxTokens > 65536 {
		return LLMConfig{}, errors.New("maxTokens must be between 1 and 65536")
	}

	baseURL := strings.TrimRight(strings.TrimSpace(update.BaseURL), "/")
	if baseURL != "" {
		parsed, err := url.Parse(baseURL)
		if err != nil || (parsed.Scheme != "https" && parsed.Scheme != "http") || parsed.Host == "" {
			return LLMConfig{}, errors.New("baseUrl must be an absolute http(s) URL")
		}
		if parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" {
			return LLMConfig{}, errors.New("baseUrl must not contain credentials, query parameters, or a fragment")
		}
	}

	return normalizeLLMRuntimeConfig(LLMConfig{
		Enabled:   update.Enabled,
		Provider:  provider,
		Model:     model,
		BaseURL:   baseURL,
		MaxTokens: update.MaxTokens,
	}), nil
}

// EncryptSecret encrypts a provider API key for at-rest storage. It shares the
// key derivation and payload format used for the singleton llm.api_key setting.
func (m *LLMSettingsManager) EncryptSecret(plain string) (string, error) {
	return m.encrypt(plain)
}

// DecryptSecret decrypts a secret produced by EncryptSecret.
func (m *LLMSettingsManager) DecryptSecret(value string) (string, error) {
	return m.decrypt(value)
}

func (m *LLMSettingsManager) encrypt(plain string) (string, error) {
	nonce := make([]byte, m.aead.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}
	sealed := m.aead.Seal(nil, nonce, []byte(plain), []byte(llmSettingAPIKey))
	payload := append(nonce, sealed...)
	return llmSecretPrefix + base64.RawStdEncoding.EncodeToString(payload), nil
}

func (m *LLMSettingsManager) decrypt(value string) (string, error) {
	if !strings.HasPrefix(value, llmSecretPrefix) {
		return "", errors.New("unsupported secret encoding")
	}
	payload, err := base64.RawStdEncoding.DecodeString(strings.TrimPrefix(value, llmSecretPrefix))
	if err != nil {
		return "", err
	}
	if len(payload) < m.aead.NonceSize() {
		return "", errors.New("encrypted secret is truncated")
	}
	nonce, ciphertext := payload[:m.aead.NonceSize()], payload[m.aead.NonceSize():]
	plain, err := m.aead.Open(nil, nonce, ciphertext, []byte(llmSettingAPIKey))
	if err != nil {
		return "", err
	}
	return string(plain), nil
}
