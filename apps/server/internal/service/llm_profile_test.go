package service

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func newLLMProfileTestService(t *testing.T) *LLMProfileService {
	t.Helper()
	db, err := gorm.Open(sqlite.Open("file:"+t.Name()+"?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&database.Setting{}, &database.LLMProfile{}); err != nil {
		t.Fatal(err)
	}
	client := NewLLMClient(LLMConfig{Provider: "anthropic", Model: "m", MaxTokens: 1024})
	manager, err := NewLLMSettingsManager(db, client, LLMConfig{Provider: "anthropic", Model: "m", MaxTokens: 1024}, strings.Repeat("k", 64))
	if err != nil {
		t.Fatal(err)
	}
	return NewLLMProfileService(db, manager)
}

func TestProfileAPIKeyIsEncryptedAtRestAndDecryptsBack(t *testing.T) {
	svc := newLLMProfileTestService(t)

	created, err := svc.CreateProfile("prod", "deepseek", "deepseek-chat", "", "plaintext-secret", 2048)
	if err != nil {
		t.Fatal(err)
	}
	if created.APIKey == "plaintext-secret" {
		t.Fatal("API key was stored in plaintext")
	}
	if !strings.HasPrefix(created.APIKey, "enc:v1:") {
		t.Fatalf("expected encrypted prefix, got %q", created.APIKey)
	}

	cfg, err := svc.ConfigForProfile(created)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.APIKey != "plaintext-secret" {
		t.Fatalf("round-trip failed: got %q", cfg.APIKey)
	}
	if cfg.Model != "deepseek-chat" || cfg.Provider != "deepseek" {
		t.Fatalf("unexpected config: %+v", cfg)
	}
}

func TestUpdateProfileKeepsExistingKeyWhenNoneSupplied(t *testing.T) {
	svc := newLLMProfileTestService(t)

	created, err := svc.CreateProfile("p1", "openai", "gpt-4o", "", "first-key", 1024)
	if err != nil {
		t.Fatal(err)
	}
	stored := created.APIKey

	updated, err := svc.UpdateProfile(created.ID, "p1-renamed", "openai", "gpt-4o-mini", "", 4096, nil)
	if err != nil {
		t.Fatal(err)
	}
	if updated.APIKey != stored {
		t.Fatal("API key changed when no new key was supplied")
	}
	if updated.Name != "p1-renamed" || updated.Model != "gpt-4o-mini" || updated.MaxTokens != 4096 {
		t.Fatalf("update did not apply: %+v", updated)
	}

	newKey := "second-key"
	rotated, err := svc.UpdateProfile(created.ID, "p1-renamed", "openai", "gpt-4o-mini", "", 4096, &newKey)
	if err != nil {
		t.Fatal(err)
	}
	if rotated.APIKey == stored {
		t.Fatal("API key was not rotated when a new key was supplied")
	}
	plain, err := svc.ResolveAPIKey(created.ID)
	if err != nil {
		t.Fatal(err)
	}
	if plain != "second-key" {
		t.Fatalf("expected rotated key, got %q", plain)
	}
}

func TestSetActiveProfileIsExclusive(t *testing.T) {
	svc := newLLMProfileTestService(t)

	a, err := svc.CreateProfile("a", "openai", "gpt-4o", "", "ka", 1024)
	if err != nil {
		t.Fatal(err)
	}
	b, err := svc.CreateProfile("b", "deepseek", "deepseek-chat", "", "kb", 1024)
	if err != nil {
		t.Fatal(err)
	}

	if _, err := svc.GetActiveProfile(); !errors.Is(err, ErrNoActiveProfile) {
		t.Fatalf("expected ErrNoActiveProfile, got %v", err)
	}

	if err := svc.SetActiveProfile(a.ID); err != nil {
		t.Fatal(err)
	}
	if err := svc.SetActiveProfile(b.ID); err != nil {
		t.Fatal(err)
	}

	active, err := svc.GetActiveProfile()
	if err != nil {
		t.Fatal(err)
	}
	if active.ID != b.ID {
		t.Fatalf("expected profile b active, got %d", active.ID)
	}

	profiles, err := svc.ListProfiles()
	if err != nil {
		t.Fatal(err)
	}
	activeCount := 0
	for _, p := range profiles {
		if p.IsActive {
			activeCount++
		}
	}
	if activeCount != 1 {
		t.Fatalf("expected exactly 1 active profile, got %d", activeCount)
	}
}

func TestCreateProfileRejectsDuplicateName(t *testing.T) {
	svc := newLLMProfileTestService(t)
	if _, err := svc.CreateProfile("dup", "openai", "gpt-4o", "", "k", 1024); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.CreateProfile("dup", "deepseek", "deepseek-chat", "", "k", 1024); !errors.Is(err, ErrProfileNameExists) {
		t.Fatalf("expected ErrProfileNameExists, got %v", err)
	}
}

func TestListModelsQueriesProviderEndpoint(t *testing.T) {
	var gotAuth, gotPath string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		gotPath = r.URL.Path
		json.NewEncoder(w).Encode(map[string]any{
			"data": []map[string]string{
				{"id": "zeta-model"},
				{"id": "alpha-model", "display_name": "Alpha"},
			},
		})
	}))
	defer srv.Close()

	svc := newLLMProfileTestService(t)
	models, err := svc.ListModels(context.Background(), "openai-compatible", srv.URL, "test-key")
	if err != nil {
		t.Fatal(err)
	}
	if gotPath != "/v1/models" {
		t.Fatalf("expected /v1/models, got %q", gotPath)
	}
	if gotAuth != "Bearer test-key" {
		t.Fatalf("unexpected auth header %q", gotAuth)
	}
	if len(models) != 2 {
		t.Fatalf("expected 2 models, got %d", len(models))
	}
	// Sorted by ID.
	if models[0].ID != "alpha-model" || models[0].DisplayName != "Alpha" {
		t.Fatalf("unexpected first model: %+v", models[0])
	}
	if models[1].DisplayName != "zeta-model" {
		t.Fatalf("expected ID used as label fallback, got %q", models[1].DisplayName)
	}
}

func TestListModelsFallsBackWhenProviderQueryFails(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer srv.Close()

	svc := newLLMProfileTestService(t)
	models, err := svc.ListModels(context.Background(), "deepseek", srv.URL, "bad-key")
	if err != nil {
		t.Fatal(err)
	}
	if len(models) == 0 {
		t.Fatal("expected curated fallback models")
	}
	if models[0].ID != "deepseek-chat" {
		t.Fatalf("unexpected fallback list: %+v", models)
	}
}

func TestListModelsRejectsUnknownProvider(t *testing.T) {
	svc := newLLMProfileTestService(t)
	if _, err := svc.ListModels(context.Background(), "not-a-vendor", "", "k"); !errors.Is(err, ErrInvalidProvider) {
		t.Fatalf("expected ErrInvalidProvider, got %v", err)
	}
}

func TestProvidersCatalogIncludesDomesticAndInternational(t *testing.T) {
	svc := newLLMProfileTestService(t)
	providers := svc.Providers()
	if len(providers) < 10 {
		t.Fatalf("expected a broad catalog, got %d", len(providers))
	}
	var china, intl int
	for _, p := range providers {
		switch p.Region {
		case "china":
			china++
		case "international":
			intl++
		}
	}
	if china < 5 {
		t.Fatalf("expected several domestic vendors, got %d", china)
	}
	if intl < 3 {
		t.Fatalf("expected several international vendors, got %d", intl)
	}
}
