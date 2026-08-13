package service

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
)

func TestLLMEndpointAcceptsRootVersionAndFullURL(t *testing.T) {
	endpoint := "/v1/chat/completions"
	for _, tc := range []struct {
		base string
		want string
	}{
		{base: "https://example.test", want: "https://example.test/v1/chat/completions"},
		{base: "https://example.test/v1", want: "https://example.test/v1/chat/completions"},
		{base: "https://example.test/v1/chat/completions", want: "https://example.test/v1/chat/completions"},
	} {
		if got := llmEndpoint(tc.base, "https://default.test", endpoint); got != tc.want {
			t.Errorf("llmEndpoint(%q) = %q, want %q", tc.base, got, tc.want)
		}
	}
}

func TestLLMClientCanBeReconfiguredAndTestedWhileDisabled(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" {
			t.Fatalf("path = %q", r.URL.Path)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-key" {
			t.Fatalf("authorization = %q", got)
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"choices": []any{map[string]any{"message": map[string]any{"content": "OK"}}},
		})
	}))
	defer server.Close()

	client := NewLLMClient(LLMConfig{})
	client.Configure(LLMConfig{
		Enabled:   false,
		Provider:  "openai-compatible",
		Model:     "test-model",
		BaseURL:   server.URL + "/v1",
		APIKey:    "test-key",
		MaxTokens: 16,
	})
	if client.Enabled() {
		t.Fatal("disabled client reported enabled")
	}
	if err := client.Test(context.Background()); err != nil {
		t.Fatalf("connection test failed: %v", err)
	}
}

func TestChatResultKeepsIdentityFromRequestSnapshot(t *testing.T) {
	requestStarted := make(chan struct{})
	releaseResponse := make(chan struct{})
	var once sync.Once
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		once.Do(func() { close(requestStarted) })
		<-releaseResponse
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"choices": []any{map[string]any{"message": map[string]any{"content": "OK"}}},
		})
	}))
	defer server.Close()

	client := NewLLMClient(LLMConfig{
		Enabled: true, Provider: " OpenAI-Compatible ", Model: " first-model ",
		BaseURL: server.URL, APIKey: "test-key", MaxTokens: 16,
	})
	resultCh := make(chan LLMChatResult, 1)
	errCh := make(chan error, 1)
	go func() {
		result, err := client.ChatResult(context.Background(), "", []ChatMessage{{Role: "user", Content: "hello"}})
		resultCh <- result
		errCh <- err
	}()

	<-requestStarted
	client.Configure(LLMConfig{Enabled: true, Provider: "openai", Model: "second-model", BaseURL: server.URL, APIKey: "test-key", MaxTokens: 16})
	close(releaseResponse)
	if err := <-errCh; err != nil {
		t.Fatal(err)
	}
	result := <-resultCh
	if result.Model.Provider != "openai-compatible" || result.Model.Model != "first-model" {
		t.Fatalf("identity = %#v", result.Model)
	}
}
