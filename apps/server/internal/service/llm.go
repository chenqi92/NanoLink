package service

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

// LLMConfig configures the external LLM backing the assistant chat.
type LLMConfig struct {
	Enabled   bool
	Provider  string // provider catalog ID; non-Anthropic vendors use the OpenAI-compatible wire format
	Model     string
	BaseURL   string
	APIKey    string
	MaxTokens int
}

// ChatMessage is a single turn in an assistant conversation.
type ChatMessage struct {
	Role    string `json:"role"` // "user" | "assistant"
	Content string `json:"content"`
}

// LLMStatus is the non-secret runtime state safe to return to authenticated
// dashboard users. Configured means a model and API key are both available;
// Enabled additionally reflects the operator's on/off switch.
type LLMStatus struct {
	Enabled    bool   `json:"enabled"`
	Configured bool   `json:"configured"`
	Provider   string `json:"provider"`
	Model      string `json:"model"`
}

// LLMModelIdentity identifies the non-secret provider and model used for a chat.
type LLMModelIdentity struct {
	ProfileID   uint   `json:"profileId,omitempty"`
	ProfileName string `json:"profileName,omitempty"`
	Provider    string `json:"provider"`
	Model       string `json:"model"`
}

// LLMChatResult contains an assistant reply and the configuration identity from
// the same immutable snapshot used for the upstream request.
type LLMChatResult struct {
	Reply string
	Model LLMModelIdentity
}

// LLMClient talks to an external LLM over HTTP. It supports the Anthropic
// Messages API and OpenAI-compatible Chat Completions APIs.
type LLMClient struct {
	mu   sync.RWMutex
	cfg  LLMConfig
	http *http.Client
}

// NewLLMClient builds a client, falling back to NANOLINK_LLM_API_KEY for the
// API key so the secret need not be written to the config file.
func NewLLMClient(cfg LLMConfig) *LLMClient {
	if cfg.APIKey == "" {
		cfg.APIKey = os.Getenv("NANOLINK_LLM_API_KEY")
	}
	cfg = normalizeLLMRuntimeConfig(cfg)
	return &LLMClient{cfg: cfg, http: &http.Client{Timeout: 60 * time.Second}}
}

func normalizeLLMRuntimeConfig(cfg LLMConfig) LLMConfig {
	cfg.Provider = strings.ToLower(strings.TrimSpace(cfg.Provider))
	if cfg.Provider == "" {
		cfg.Provider = "anthropic"
	}
	cfg.Model = strings.TrimSpace(cfg.Model)
	cfg.BaseURL = strings.TrimRight(strings.TrimSpace(cfg.BaseURL), "/")
	cfg.APIKey = strings.TrimSpace(cfg.APIKey)
	if cfg.MaxTokens <= 0 {
		cfg.MaxTokens = 1024
	}
	return cfg
}

// Configure atomically replaces the runtime provider configuration. Existing
// in-flight requests keep their snapshot while new chats use the new settings,
// so an admin save does not require a server restart.
func (c *LLMClient) Configure(cfg LLMConfig) {
	if c == nil {
		return
	}
	c.mu.Lock()
	c.cfg = normalizeLLMRuntimeConfig(cfg)
	c.mu.Unlock()
}

func (c *LLMClient) snapshot() LLMConfig {
	if c == nil {
		return LLMConfig{}
	}
	c.mu.RLock()
	cfg := c.cfg
	c.mu.RUnlock()
	return cfg
}

// Status returns the non-secret current provider identity.
func (c *LLMClient) Status() LLMStatus {
	cfg := c.snapshot()
	configured := cfg.APIKey != "" && cfg.Model != ""
	return LLMStatus{
		Enabled:    cfg.Enabled && configured,
		Configured: configured,
		Provider:   cfg.Provider,
		Model:      cfg.Model,
	}
}

// Enabled reports whether the assistant chat can be served.
func (c *LLMClient) Enabled() bool {
	return c.Status().Enabled
}

// Chat sends a system prompt and conversation to the configured provider and
// returns the assistant's text reply.
func (c *LLMClient) Chat(ctx context.Context, system string, messages []ChatMessage) (string, error) {
	result, err := c.ChatResult(ctx, system, messages)
	return result.Reply, err
}

// ChatResult sends a conversation using one global configuration snapshot and
// returns the non-secret identity from that same snapshot.
func (c *LLMClient) ChatResult(ctx context.Context, system string, messages []ChatMessage) (LLMChatResult, error) {
	cfg := c.snapshot()
	if !cfg.Enabled || cfg.APIKey == "" || cfg.Model == "" {
		return LLMChatResult{}, fmt.Errorf("AI assistant is not configured: set llm.enabled, llm.model and NANOLINK_LLM_API_KEY")
	}
	reply, err := c.chatWithConfig(ctx, cfg, system, messages)
	if err != nil {
		return LLMChatResult{}, err
	}
	return LLMChatResult{Reply: reply, Model: LLMModelIdentity{Provider: cfg.Provider, Model: cfg.Model}}, nil
}

// Test verifies the saved provider credentials even when the assistant is
// currently disabled. It intentionally sends a minimal request.
func (c *LLMClient) Test(ctx context.Context) error {
	cfg := c.snapshot()
	if cfg.APIKey == "" || cfg.Model == "" {
		return fmt.Errorf("model and API key are required")
	}
	_, err := c.chatWithConfig(ctx, cfg, "Reply with exactly OK.", []ChatMessage{{Role: "user", Content: "Connection test"}})
	return err
}

// ChatWithConfig serves a conversation from an explicit provider configuration
// instead of the globally configured one, so a caller can chat through a saved
// profile without mutating shared state.
func (c *LLMClient) ChatWithConfig(ctx context.Context, cfg LLMConfig, system string, messages []ChatMessage) (string, error) {
	result, err := c.ChatWithConfigResult(ctx, cfg, system, messages)
	return result.Reply, err
}

// ChatWithConfigResult normalizes and uses one explicit configuration snapshot,
// returning the non-secret identity that was sent upstream.
func (c *LLMClient) ChatWithConfigResult(ctx context.Context, cfg LLMConfig, system string, messages []ChatMessage) (LLMChatResult, error) {
	cfg = normalizeLLMRuntimeConfig(cfg)
	if cfg.APIKey == "" || cfg.Model == "" {
		return LLMChatResult{}, fmt.Errorf("AI provider is not configured: model and API key are required")
	}
	reply, err := c.chatWithConfig(ctx, cfg, system, messages)
	if err != nil {
		return LLMChatResult{}, err
	}
	return LLMChatResult{Reply: reply, Model: LLMModelIdentity{Provider: cfg.Provider, Model: cfg.Model}}, nil
}

// TestConfig verifies an explicit provider configuration with a minimal request.
func (c *LLMClient) TestConfig(ctx context.Context, cfg LLMConfig) error {
	_, err := c.ChatWithConfig(ctx, cfg, "Reply with exactly OK.", []ChatMessage{{Role: "user", Content: "Connection test"}})
	return err
}

func (c *LLMClient) chatWithConfig(ctx context.Context, cfg LLMConfig, system string, messages []ChatMessage) (string, error) {
	switch cfg.Provider {
	case "anthropic":
		return c.chatAnthropic(ctx, cfg, system, messages)
	default: // openai and openai-compatible
		return c.chatOpenAI(ctx, cfg, system, messages)
	}
}

func (c *LLMClient) chatAnthropic(ctx context.Context, cfg LLMConfig, system string, messages []ChatMessage) (string, error) {
	payload := map[string]interface{}{
		"model":      cfg.Model,
		"max_tokens": cfg.MaxTokens,
		"system":     system,
		"messages":   messages,
	}
	respBody, err := c.post(ctx, llmEndpoint(cfg.BaseURL, "https://api.anthropic.com", "/v1/messages"), payload, map[string]string{
		"x-api-key":         cfg.APIKey,
		"anthropic-version": "2023-06-01",
	})
	if err != nil {
		return "", err
	}
	var out struct {
		Content []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
		Error *struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(respBody, &out); err != nil {
		return "", fmt.Errorf("invalid LLM response: %w", err)
	}
	if out.Error != nil {
		return "", fmt.Errorf("LLM error: %s", out.Error.Message)
	}
	var sb strings.Builder
	for _, b := range out.Content {
		if b.Type == "text" {
			sb.WriteString(b.Text)
		}
	}
	return strings.TrimSpace(sb.String()), nil
}

func (c *LLMClient) chatOpenAI(ctx context.Context, cfg LLMConfig, system string, messages []ChatMessage) (string, error) {
	msgs := make([]map[string]string, 0, len(messages)+1)
	if system != "" {
		msgs = append(msgs, map[string]string{"role": "system", "content": system})
	}
	for _, m := range messages {
		msgs = append(msgs, map[string]string{"role": m.Role, "content": m.Content})
	}
	payload := map[string]interface{}{
		"model":      cfg.Model,
		"messages":   msgs,
		"max_tokens": cfg.MaxTokens,
	}
	respBody, err := c.post(ctx, llmEndpoint(cfg.BaseURL, "https://api.openai.com", "/v1/chat/completions"), payload, map[string]string{
		"Authorization": "Bearer " + cfg.APIKey,
	})
	if err != nil {
		return "", err
	}
	var out struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
		Error *struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(respBody, &out); err != nil {
		return "", fmt.Errorf("invalid LLM response: %w", err)
	}
	if out.Error != nil {
		return "", fmt.Errorf("LLM error: %s", out.Error.Message)
	}
	if len(out.Choices) == 0 {
		return "", fmt.Errorf("LLM returned no choices")
	}
	return strings.TrimSpace(out.Choices[0].Message.Content), nil
}

// llmEndpoint accepts either a service root (https://host), a conventional
// version root (https://host/v1), or the full endpoint. This avoids the common
// custom-provider failure where /v1 is accidentally appended twice.
func llmEndpoint(base, defaultBase, endpoint string) string {
	base = strings.TrimRight(strings.TrimSpace(base), "/")
	if base == "" {
		base = defaultBase
	}
	if strings.HasSuffix(base, endpoint) {
		return base
	}
	if strings.HasSuffix(base, "/v1") && strings.HasPrefix(endpoint, "/v1/") {
		return base + strings.TrimPrefix(endpoint, "/v1")
	}
	return base + endpoint
}

// post sends a JSON payload and returns the raw response body, treating non-2xx
// responses as errors (with the body included for diagnostics).
func (c *LLMClient) post(ctx context.Context, url string, payload interface{}, headers map[string]string) ([]byte, error) {
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	respBody, err := io.ReadAll(io.LimitReader(resp.Body, 4*1024*1024))
	if err != nil {
		return nil, err
	}
	if resp.StatusCode >= 300 {
		detail := strings.TrimSpace(string(respBody))
		if len(detail) > 2048 {
			detail = detail[:2048] + "…"
		}
		return nil, fmt.Errorf("LLM API returned %d: %s", resp.StatusCode, detail)
	}
	return respBody, nil
}
