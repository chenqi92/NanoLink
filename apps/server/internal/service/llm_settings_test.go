package service

import (
	"context"
	"strings"
	"testing"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func newLLMSettingsTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	db, err := gorm.Open(sqlite.Open("file:"+t.Name()+"?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&database.Setting{}); err != nil {
		t.Fatal(err)
	}
	return db
}

func TestLLMSettingsEncryptsSecretAndReloadsClient(t *testing.T) {
	t.Setenv("NANOLINK_LLM_API_KEY", "")
	db := newLLMSettingsTestDB(t)
	client := NewLLMClient(LLMConfig{Provider: "anthropic", Model: "default-model", MaxTokens: 1024})
	manager, err := NewLLMSettingsManager(db, client, LLMConfig{Provider: "anthropic", Model: "default-model", MaxTokens: 1024}, strings.Repeat("s", 64))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := manager.Reload(context.Background()); err != nil {
		t.Fatal(err)
	}

	view, err := manager.Update(context.Background(), LLMSettingsUpdate{
		Enabled:   true,
		Provider:  "openai-compatible",
		Model:     "private-model",
		BaseURL:   "https://llm.example.test/v1/",
		MaxTokens: 2048,
		APIKey:    "super-secret-key",
	})
	if err != nil {
		t.Fatal(err)
	}
	if !view.Enabled || !view.APIKeyConfigured || view.APIKeySource != "stored" {
		t.Fatalf("unexpected settings view: %#v", view)
	}
	if view.BaseURL != "https://llm.example.test/v1" {
		t.Fatalf("base URL = %q", view.BaseURL)
	}
	status := client.Status()
	if !status.Enabled || !status.Configured || status.Provider != "openai-compatible" || status.Model != "private-model" {
		t.Fatalf("client was not reconfigured: %#v", status)
	}

	var secret database.Setting
	if err := db.First(&secret, "key = ?", llmSettingAPIKey).Error; err != nil {
		t.Fatal(err)
	}
	if secret.Value == "super-secret-key" || strings.Contains(secret.Value, "super-secret-key") {
		t.Fatal("API key was stored in plaintext")
	}
	if !strings.HasPrefix(secret.Value, llmSecretPrefix) {
		t.Fatalf("unexpected secret encoding: %q", secret.Value)
	}

	reloadedClient := NewLLMClient(LLMConfig{})
	reloaded, err := NewLLMSettingsManager(db, reloadedClient, LLMConfig{Provider: "anthropic", Model: "fallback", MaxTokens: 1024}, strings.Repeat("s", 64))
	if err != nil {
		t.Fatal(err)
	}
	reloadedView, err := reloaded.Reload(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if !reloadedView.APIKeyConfigured || !reloadedClient.Enabled() {
		t.Fatalf("encrypted settings did not survive reload: %#v", reloadedView)
	}
}

func TestLLMSettingsClearStoredKey(t *testing.T) {
	t.Setenv("NANOLINK_LLM_API_KEY", "")
	db := newLLMSettingsTestDB(t)
	client := NewLLMClient(LLMConfig{})
	manager, err := NewLLMSettingsManager(db, client, LLMConfig{Provider: "openai", Model: "model", MaxTokens: 1024}, strings.Repeat("k", 64))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := manager.Update(context.Background(), LLMSettingsUpdate{Provider: "openai", Model: "model", MaxTokens: 1024, APIKey: "key"}); err != nil {
		t.Fatal(err)
	}
	view, err := manager.Update(context.Background(), LLMSettingsUpdate{Provider: "openai", Model: "model", MaxTokens: 1024, ClearAPIKey: true})
	if err != nil {
		t.Fatal(err)
	}
	if view.APIKeyConfigured || client.Status().Configured {
		t.Fatalf("API key was not cleared: %#v", view)
	}
}

func TestValidateLLMSettingsRejectsUnsafeBaseURL(t *testing.T) {
	_, err := validateLLMSettingsUpdate(LLMSettingsUpdate{
		Provider:  "openai-compatible",
		Model:     "model",
		BaseURL:   "https://user:pass@example.test/v1?token=leak",
		MaxTokens: 1024,
	})
	if err == nil {
		t.Fatal("URL credentials/query were accepted")
	}
}

func TestValidateLLMSettingsAcceptsEveryCatalogProvider(t *testing.T) {
	for _, provider := range providerCatalog {
		provider := provider
		t.Run(provider.ID, func(t *testing.T) {
			baseURL := provider.DefaultBaseURL
			if baseURL == "" {
				baseURL = "https://llm.example.test/v1"
			}
			cfg, err := validateLLMSettingsUpdate(LLMSettingsUpdate{
				Provider:  provider.ID,
				Model:     "model",
				BaseURL:   baseURL,
				MaxTokens: 1024,
			})
			if err != nil {
				t.Fatalf("catalog provider was rejected: %v", err)
			}
			if cfg.Provider != provider.ID {
				t.Fatalf("provider = %q, want %q", cfg.Provider, provider.ID)
			}
		})
	}
}
