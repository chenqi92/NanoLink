package handler

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func TestSanitizeAssistantMessagesFiltersAndTrims(t *testing.T) {
	got, err := sanitizeAssistantMessages([]service.ChatMessage{
		{Role: "system", Content: "ignored"},
		{Role: "user", Content: "  hello  "},
		{Role: "assistant", Content: "\nworld\n"},
		{Role: "user", Content: "   "},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("got %d messages, want 2", len(got))
	}
	if got[0].Content != "hello" || got[1].Content != "world" {
		t.Fatalf("messages were not trimmed/filtered: %#v", got)
	}
}

func TestSanitizeAssistantMessagesRejectsTooManyMessages(t *testing.T) {
	messages := make([]service.ChatMessage, maxAssistantMessages+1)
	for i := range messages {
		messages[i] = service.ChatMessage{Role: "user", Content: "hello"}
	}
	_, err := sanitizeAssistantMessages(messages)
	if !errors.Is(err, errAssistantTooManyMessages) {
		t.Fatalf("got %v, want %v", err, errAssistantTooManyMessages)
	}
}

func TestSanitizeAssistantMessagesRejectsLongMessage(t *testing.T) {
	_, err := sanitizeAssistantMessages([]service.ChatMessage{
		{Role: "user", Content: strings.Repeat("a", maxAssistantMessageBytes+1)},
	})
	if !errors.Is(err, errAssistantMessageTooLong) {
		t.Fatalf("got %v, want %v", err, errAssistantMessageTooLong)
	}
}

func newAssistantHandlerTest(t *testing.T, global service.LLMConfig) (*AssistantHandler, *service.LLMProfileService, *gorm.DB) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	db, err := gorm.Open(sqlite.Open("file:"+t.Name()+"?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&database.Setting{}, &database.LLMProfile{}, &database.AgentToken{}); err != nil {
		t.Fatal(err)
	}
	llm := service.NewLLMClient(global)
	settings, err := service.NewLLMSettingsManager(db, llm, global, strings.Repeat("k", 64))
	if err != nil {
		t.Fatal(err)
	}
	profiles := service.NewLLMProfileService(db, settings)
	metrics := service.NewMetricsService(zap.NewNop().Sugar())
	handler := NewAssistantHandler(metrics, service.NewAgentService(zap.NewNop().Sugar(), metrics), db, service.NewPermissionService(db, zap.NewNop().Sugar()), llm, zap.NewNop().Sugar())
	handler.SetProfileService(profiles)
	return handler, profiles, db
}

func createAssistantProfile(t *testing.T, profiles *service.LLMProfileService, name, provider, model string, active bool) *database.LLMProfile {
	t.Helper()
	profile, err := profiles.CreateProfile(name, provider, model, "https://provider.example", "test-key", 128)
	if err != nil {
		t.Fatal(err)
	}
	if active {
		if err := profiles.SetActiveProfile(profile.ID); err != nil {
			t.Fatal(err)
		}
	}
	return profile
}

func TestResolveChatConfigUsesExplicitProfileIdentity(t *testing.T) {
	handler, profiles, _ := newAssistantHandlerTest(t, service.LLMConfig{Enabled: true, Provider: "openai", Model: "global-model", APIKey: "global-key", MaxTokens: 128})
	active := createAssistantProfile(t, profiles, "active", "anthropic", "active-model", true)
	explicit := createAssistantProfile(t, profiles, "explicit", "deepseek", "explicit-model", false)

	cfg, identity, ok := handler.resolveChatConfig(explicit.ID)
	if !ok {
		t.Fatal("explicit profile was not resolved")
	}
	if cfg.Model != "explicit-model" || identity.Provider != "deepseek" || identity.Model != "explicit-model" {
		t.Fatalf("resolved explicit profile = %#v, identity = %#v", cfg, identity)
	}
	if cfg.Model == active.Model {
		t.Fatal("explicit selection silently fell back to the active profile")
	}
}

func TestResolveChatConfigUsesActiveProfileIdentity(t *testing.T) {
	handler, profiles, _ := newAssistantHandlerTest(t, service.LLMConfig{Enabled: true, Provider: "openai", Model: "global-model", APIKey: "global-key", MaxTokens: 128})
	createAssistantProfile(t, profiles, "active", "qwen", "active-model", true)

	cfg, identity, ok := handler.resolveChatConfig(0)
	if !ok || cfg.Model != "active-model" || identity.Provider != "qwen" || identity.Model != "active-model" {
		t.Fatalf("resolved active profile = %#v, identity = %#v, ok = %v", cfg, identity, ok)
	}
}

func TestResolveChatConfigUsesGlobalIdentity(t *testing.T) {
	handler, _, _ := newAssistantHandlerTest(t, service.LLMConfig{Enabled: true, Provider: "openai-compatible", Model: "global-model", APIKey: "global-key", MaxTokens: 128})

	cfg, identity, ok := handler.resolveChatConfig(0)
	if !ok || cfg.Model != "" || identity.Provider != "openai-compatible" || identity.Model != "global-model" {
		t.Fatalf("resolved global config = %#v, identity = %#v, ok = %v", cfg, identity, ok)
	}
}

func TestResolveChatConfigDoesNotFallbackForMissingExplicitProfile(t *testing.T) {
	handler, profiles, _ := newAssistantHandlerTest(t, service.LLMConfig{Enabled: true, Provider: "openai", Model: "global-model", APIKey: "global-key", MaxTokens: 128})
	createAssistantProfile(t, profiles, "active", "anthropic", "active-model", true)

	cfg, identity, ok := handler.resolveChatConfig(999999)
	if ok || cfg.Model != "" || identity.Model != "" {
		t.Fatalf("missing explicit profile silently fell back: cfg = %#v, identity = %#v, ok = %v", cfg, identity, ok)
	}
}

func TestAssistantChatReturnsResolvedModelIdentityWithoutSecrets(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"fleet is healthy"}}]}`))
	}))
	defer upstream.Close()

	handler, profiles, _ := newAssistantHandlerTest(t, service.LLMConfig{Provider: "openai", Model: "unused", MaxTokens: 128})
	profile, err := profiles.CreateProfile("explicit", "openai", "profile-model", upstream.URL, "super-secret-key", 128)
	if err != nil {
		t.Fatal(err)
	}

	router := gin.New()
	router.Use(func(c *gin.Context) {
		c.Set(ContextKeyUser, &database.User{ID: 1, Username: "admin", IsSuperAdmin: true})
	})
	router.POST("/assistant/chat", handler.Chat)
	body := []byte(`{"messages":[{"role":"user","content":"status?"}],"profileId":` + fmt.Sprint(profile.ID) + `}`)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/assistant/chat", bytes.NewReader(body)))
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}

	var got map[string]interface{}
	if err := json.Unmarshal(response.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	model, ok := got["model"].(map[string]interface{})
	if !ok || model["profileId"] != float64(profile.ID) || model["profileName"] != "explicit" || model["provider"] != "openai" || model["model"] != "profile-model" {
		t.Fatalf("model identity = %#v", got["model"])
	}
	serialized := response.Body.String()
	if strings.Contains(serialized, "super-secret-key") || strings.Contains(serialized, upstream.URL) || strings.Contains(serialized, "baseUrl") || strings.Contains(serialized, "apiKey") {
		t.Fatalf("response exposed provider connection details: %s", serialized)
	}
}
