package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"gorm.io/gorm"
)

var (
	ErrProfileNotFound    = errors.New("profile not found")
	ErrProfileNameExists  = errors.New("profile name already exists")
	ErrNoActiveProfile    = errors.New("no active profile")
	ErrInvalidProvider    = errors.New("invalid provider")
	ErrModelListingFailed = errors.New("failed to list models from provider")
)

// SecretCodec encrypts and decrypts provider API keys. LLMSettingsManager
// implements it, so profiles reuse the same AES-GCM key derived from the server
// JWT secret rather than introducing a second secret store.
type SecretCodec interface {
	EncryptSecret(plain string) (string, error)
	DecryptSecret(value string) (string, error)
}

type LLMProfileService struct {
	db        *gorm.DB
	encryptor SecretCodec
	client    *http.Client
}

func NewLLMProfileService(db *gorm.DB, encryptor SecretCodec) *LLMProfileService {
	return &LLMProfileService{
		db:        db,
		encryptor: encryptor,
		client:    &http.Client{Timeout: 15 * time.Second},
	}
}

// ActiveConfig resolves the active profile into a runtime LLMConfig with the
// API key decrypted. It is used to serve assistant chat from the selected
// profile without exposing the secret to the browser.
func (s *LLMProfileService) ActiveConfig() (LLMConfig, error) {
	profile, err := s.GetActiveProfile()
	if err != nil {
		return LLMConfig{}, err
	}
	return s.ConfigForProfile(profile)
}

// ConfigForProfile decrypts a profile's stored key and returns a runtime config.
func (s *LLMProfileService) ConfigForProfile(profile *database.LLMProfile) (LLMConfig, error) {
	apiKey := ""
	if profile.APIKey != "" {
		plain, err := s.encryptor.DecryptSecret(profile.APIKey)
		if err != nil {
			return LLMConfig{}, fmt.Errorf("failed to decrypt profile API key: %w", err)
		}
		apiKey = plain
	}
	return LLMConfig{
		Enabled:   true,
		Provider:  profile.Provider,
		Model:     profile.Model,
		BaseURL:   profile.BaseURL,
		APIKey:    apiKey,
		MaxTokens: profile.MaxTokens,
	}, nil
}

// ResolveAPIKey returns the plaintext key for a saved profile so a model-listing
// request can reuse it without the browser holding the secret.
func (s *LLMProfileService) ResolveAPIKey(id uint) (string, error) {
	profile, err := s.GetProfile(id)
	if err != nil {
		return "", err
	}
	if profile.APIKey == "" {
		return "", nil
	}
	return s.encryptor.DecryptSecret(profile.APIKey)
}

// ListProfiles returns all LLM profiles (API keys encrypted, never returned)
func (s *LLMProfileService) ListProfiles() ([]database.LLMProfile, error) {
	var profiles []database.LLMProfile
	if err := s.db.Find(&profiles).Error; err != nil {
		return nil, err
	}
	return profiles, nil
}

// GetProfile returns a single profile by ID
func (s *LLMProfileService) GetProfile(id uint) (*database.LLMProfile, error) {
	var profile database.LLMProfile
	if err := s.db.First(&profile, id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrProfileNotFound
		}
		return nil, err
	}
	return &profile, nil
}

// GetActiveProfile returns the currently active profile
func (s *LLMProfileService) GetActiveProfile() (*database.LLMProfile, error) {
	var profile database.LLMProfile
	if err := s.db.Where("is_active = ?", true).First(&profile).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrNoActiveProfile
		}
		return nil, err
	}
	return &profile, nil
}

// CreateProfile creates a new LLM profile
func (s *LLMProfileService) CreateProfile(name, provider, model, baseURL, apiKey string, maxTokens int) (*database.LLMProfile, error) {
	// Check for duplicate name
	var existing database.LLMProfile
	if err := s.db.Where("name = ?", name).First(&existing).Error; err == nil {
		return nil, ErrProfileNameExists
	}

	// Encrypt API key if provided
	encryptedKey := ""
	if apiKey != "" {
		var err error
		encryptedKey, err = s.encryptor.EncryptSecret(apiKey)
		if err != nil {
			return nil, fmt.Errorf("failed to encrypt API key: %w", err)
		}
	}

	profile := &database.LLMProfile{
		Name:      name,
		Provider:  provider,
		Model:     model,
		BaseURL:   baseURL,
		APIKey:    encryptedKey,
		MaxTokens: maxTokens,
		IsActive:  false,
	}

	if err := s.db.Create(profile).Error; err != nil {
		return nil, err
	}

	return profile, nil
}

// UpdateProfile updates an existing profile
func (s *LLMProfileService) UpdateProfile(id uint, name, provider, model, baseURL string, maxTokens int, apiKey *string) (*database.LLMProfile, error) {
	var profile database.LLMProfile
	if err := s.db.First(&profile, id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrProfileNotFound
		}
		return nil, err
	}

	// Check for duplicate name (excluding self)
	if name != profile.Name {
		var existing database.LLMProfile
		if err := s.db.Where("name = ? AND id != ?", name, id).First(&existing).Error; err == nil {
			return nil, ErrProfileNameExists
		}
	}

	profile.Name = name
	profile.Provider = provider
	profile.Model = model
	profile.BaseURL = baseURL
	profile.MaxTokens = maxTokens

	// Update API key if provided
	if apiKey != nil && *apiKey != "" {
		encryptedKey, err := s.encryptor.EncryptSecret(*apiKey)
		if err != nil {
			return nil, fmt.Errorf("failed to encrypt API key: %w", err)
		}
		profile.APIKey = encryptedKey
	}

	if err := s.db.Save(&profile).Error; err != nil {
		return nil, err
	}

	return &profile, nil
}

// DeleteProfile deletes a profile by ID
func (s *LLMProfileService) DeleteProfile(id uint) error {
	result := s.db.Delete(&database.LLMProfile{}, id)
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return ErrProfileNotFound
	}
	return nil
}

// SetActiveProfile sets a profile as active (deactivates all others)
func (s *LLMProfileService) SetActiveProfile(id uint) error {
	return s.db.Transaction(func(tx *gorm.DB) error {
		// Check profile exists
		var profile database.LLMProfile
		if err := tx.First(&profile, id).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrProfileNotFound
			}
			return err
		}

		// Deactivate all profiles
		if err := tx.Model(&database.LLMProfile{}).Where("is_active = ?", true).Update("is_active", false).Error; err != nil {
			return err
		}

		// Activate target profile
		profile.IsActive = true
		return tx.Save(&profile).Error
	})
}

// ProviderModelList represents a model from a provider's API
type ProviderModelList struct {
	Models []ProviderModel `json:"models"`
}

type ProviderModel struct {
	ID          string `json:"id"`
	DisplayName string `json:"displayName,omitempty"`
}

// ProviderInfo describes a selectable vendor in the settings UI.
type ProviderInfo struct {
	ID             string `json:"id"`
	Label          string `json:"label"`
	DefaultBaseURL string `json:"defaultBaseUrl"`
	// Wire is the request/response dialect: "anthropic" or "openai".
	Wire string `json:"wire"`
	// CanListModels reports whether the vendor exposes a models endpoint we can
	// query. When false the UI still offers the curated fallback list.
	CanListModels bool `json:"canListModels"`
	Region        string `json:"region"` // "international" | "china"
}

// providerCatalog is the supported vendor list. Domestic vendors are included
// with their OpenAI-compatible endpoints, which is how each of them documents
// third-party client access.
var providerCatalog = []ProviderInfo{
	{ID: "anthropic", Label: "Anthropic", DefaultBaseURL: "https://api.anthropic.com", Wire: "anthropic", CanListModels: true, Region: "international"},
	{ID: "openai", Label: "OpenAI", DefaultBaseURL: "https://api.openai.com", Wire: "openai", CanListModels: true, Region: "international"},
	{ID: "gemini", Label: "Google Gemini", DefaultBaseURL: "https://generativelanguage.googleapis.com/v1beta/openai", Wire: "openai", CanListModels: true, Region: "international"},
	{ID: "mistral", Label: "Mistral AI", DefaultBaseURL: "https://api.mistral.ai", Wire: "openai", CanListModels: true, Region: "international"},
	{ID: "groq", Label: "Groq", DefaultBaseURL: "https://api.groq.com/openai", Wire: "openai", CanListModels: true, Region: "international"},
	{ID: "openrouter", Label: "OpenRouter", DefaultBaseURL: "https://openrouter.ai/api", Wire: "openai", CanListModels: true, Region: "international"},
	{ID: "deepseek", Label: "DeepSeek 深度求索", DefaultBaseURL: "https://api.deepseek.com", Wire: "openai", CanListModels: true, Region: "china"},
	{ID: "zhipu", Label: "智谱 GLM", DefaultBaseURL: "https://open.bigmodel.cn/api/paas/v4", Wire: "openai", CanListModels: true, Region: "china"},
	{ID: "moonshot", Label: "月之暗面 Kimi", DefaultBaseURL: "https://api.moonshot.cn", Wire: "openai", CanListModels: true, Region: "china"},
	{ID: "qwen", Label: "阿里通义千问", DefaultBaseURL: "https://dashscope.aliyuncs.com/compatible-mode", Wire: "openai", CanListModels: true, Region: "china"},
	{ID: "minimax", Label: "MiniMax", DefaultBaseURL: "https://api.minimax.chat", Wire: "openai", CanListModels: false, Region: "china"},
	{ID: "baichuan", Label: "百川智能", DefaultBaseURL: "https://api.baichuan-ai.com", Wire: "openai", CanListModels: false, Region: "china"},
	{ID: "stepfun", Label: "阶跃星辰 Step", DefaultBaseURL: "https://api.stepfun.com", Wire: "openai", CanListModels: true, Region: "china"},
	{ID: "siliconflow", Label: "硅基流动 SiliconFlow", DefaultBaseURL: "https://api.siliconflow.cn", Wire: "openai", CanListModels: true, Region: "china"},
	{ID: "hunyuan", Label: "腾讯混元", DefaultBaseURL: "https://api.hunyuan.cloud.tencent.com", Wire: "openai", CanListModels: false, Region: "china"},
	{ID: "ernie", Label: "百度文心一言", DefaultBaseURL: "https://qianfan.baidubce.com/v2", Wire: "openai", CanListModels: false, Region: "china"},
	{ID: "openai-compatible", Label: "OpenAI-compatible (custom)", DefaultBaseURL: "", Wire: "openai", CanListModels: true, Region: "international"},
}

// fallbackModels are curated model IDs used when a vendor has no queryable
// models endpoint, or when the query fails.
var fallbackModels = map[string][]ProviderModel{
	"anthropic": {
		{ID: "claude-opus-4-5", DisplayName: "Claude Opus 4.5"},
		{ID: "claude-sonnet-4-5", DisplayName: "Claude Sonnet 4.5"},
		{ID: "claude-haiku-4-5", DisplayName: "Claude Haiku 4.5"},
	},
	"deepseek": {
		{ID: "deepseek-chat", DisplayName: "DeepSeek Chat"},
		{ID: "deepseek-reasoner", DisplayName: "DeepSeek Reasoner"},
	},
	"zhipu": {
		{ID: "glm-4-plus", DisplayName: "GLM-4-Plus"},
		{ID: "glm-4-air", DisplayName: "GLM-4-Air"},
		{ID: "glm-4-flash", DisplayName: "GLM-4-Flash"},
	},
	"moonshot": {
		{ID: "moonshot-v1-8k", DisplayName: "Moonshot v1 8K"},
		{ID: "moonshot-v1-32k", DisplayName: "Moonshot v1 32K"},
		{ID: "moonshot-v1-128k", DisplayName: "Moonshot v1 128K"},
	},
	"qwen": {
		{ID: "qwen-max", DisplayName: "Qwen Max"},
		{ID: "qwen-plus", DisplayName: "Qwen Plus"},
		{ID: "qwen-turbo", DisplayName: "Qwen Turbo"},
	},
	"minimax": {
		{ID: "abab6.5s-chat", DisplayName: "abab6.5s"},
		{ID: "abab6.5g-chat", DisplayName: "abab6.5g"},
	},
	"baichuan": {
		{ID: "Baichuan4", DisplayName: "Baichuan4"},
		{ID: "Baichuan3-Turbo", DisplayName: "Baichuan3 Turbo"},
	},
	"hunyuan": {
		{ID: "hunyuan-pro", DisplayName: "Hunyuan Pro"},
		{ID: "hunyuan-standard", DisplayName: "Hunyuan Standard"},
		{ID: "hunyuan-lite", DisplayName: "Hunyuan Lite"},
	},
	"ernie": {
		{ID: "ernie-4.0-8k", DisplayName: "ERNIE 4.0 8K"},
		{ID: "ernie-3.5-8k", DisplayName: "ERNIE 3.5 8K"},
		{ID: "ernie-speed-8k", DisplayName: "ERNIE Speed 8K"},
	},
}

// Providers returns the supported vendor catalog for the settings UI.
func (s *LLMProfileService) Providers() []ProviderInfo {
	out := make([]ProviderInfo, len(providerCatalog))
	copy(out, providerCatalog)
	return out
}

func providerByID(id string) (ProviderInfo, bool) {
	id = strings.ToLower(strings.TrimSpace(id))
	for _, p := range providerCatalog {
		if p.ID == id {
			return p, true
		}
	}
	return ProviderInfo{}, false
}

// ListModels fetches the models a provider offers. Vendors with a queryable
// models endpoint are asked directly; the rest (and any failed query) fall back
// to the curated list so the UI can still offer a selection instead of forcing
// free-text entry.
func (s *LLMProfileService) ListModels(ctx context.Context, provider, baseURL, apiKey string) ([]ProviderModel, error) {
	info, ok := providerByID(provider)
	if !ok {
		return nil, ErrInvalidProvider
	}
	if baseURL == "" {
		baseURL = info.DefaultBaseURL
	}
	if baseURL == "" {
		return nil, fmt.Errorf("%w: base URL is required for %s", ErrInvalidProvider, info.ID)
	}

	if info.CanListModels {
		models, err := s.fetchModels(ctx, info, baseURL, apiKey)
		if err == nil && len(models) > 0 {
			return models, nil
		}
		if fb, hasFallback := fallbackModels[info.ID]; hasFallback {
			return fb, nil
		}
		if err != nil {
			return nil, err
		}
		return nil, ErrModelListingFailed
	}

	if fb, hasFallback := fallbackModels[info.ID]; hasFallback {
		return fb, nil
	}
	return nil, ErrModelListingFailed
}

// fetchModels queries a /v1/models style endpoint. Anthropic and the
// OpenAI-compatible vendors both expose a {"data":[{"id":...}]} shape.
func (s *LLMProfileService) fetchModels(ctx context.Context, info ProviderInfo, baseURL, apiKey string) ([]ProviderModel, error) {
	url := llmEndpoint(baseURL, info.DefaultBaseURL, "/v1/models")

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	if info.Wire == "anthropic" {
		req.Header.Set("x-api-key", apiKey)
		req.Header.Set("anthropic-version", "2023-06-01")
	} else {
		req.Header.Set("Authorization", "Bearer "+apiKey)
	}

	resp, err := s.client.Do(req)
	if err != nil {
		return nil, ErrModelListingFailed
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("%w: HTTP %d", ErrModelListingFailed, resp.StatusCode)
	}

	var result struct {
		Data []struct {
			ID          string `json:"id"`
			DisplayName string `json:"display_name"`
		} `json:"data"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 2*1024*1024)).Decode(&result); err != nil {
		return nil, ErrModelListingFailed
	}

	models := make([]ProviderModel, 0, len(result.Data))
	for _, m := range result.Data {
		if m.ID == "" {
			continue
		}
		label := m.DisplayName
		if label == "" {
			label = m.ID
		}
		models = append(models, ProviderModel{ID: m.ID, DisplayName: label})
	}
	sort.Slice(models, func(i, j int) bool { return models[i].ID < models[j].ID })
	return models, nil
}
