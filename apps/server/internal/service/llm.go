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
	"time"
)

// LLMConfig configures the external LLM backing the assistant chat.
type LLMConfig struct {
	Enabled   bool
	Provider  string // "anthropic" | "openai" | "openai-compatible"
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

// LLMClient talks to an external LLM over HTTP. It supports the Anthropic
// Messages API and OpenAI-compatible Chat Completions APIs.
type LLMClient struct {
	cfg  LLMConfig
	http *http.Client
}

// NewLLMClient builds a client, falling back to NANOLINK_LLM_API_KEY for the
// API key so the secret need not be written to the config file.
func NewLLMClient(cfg LLMConfig) *LLMClient {
	if cfg.APIKey == "" {
		cfg.APIKey = os.Getenv("NANOLINK_LLM_API_KEY")
	}
	if cfg.MaxTokens <= 0 {
		cfg.MaxTokens = 1024
	}
	return &LLMClient{cfg: cfg, http: &http.Client{Timeout: 60 * time.Second}}
}

// Enabled reports whether the assistant chat can be served.
func (c *LLMClient) Enabled() bool {
	return c != nil && c.cfg.Enabled && c.cfg.APIKey != "" && c.cfg.Model != ""
}

// Chat sends a system prompt and conversation to the configured provider and
// returns the assistant's text reply.
func (c *LLMClient) Chat(ctx context.Context, system string, messages []ChatMessage) (string, error) {
	if !c.Enabled() {
		return "", fmt.Errorf("AI assistant is not configured: set llm.enabled, llm.model and NANOLINK_LLM_API_KEY")
	}
	switch strings.ToLower(c.cfg.Provider) {
	case "anthropic":
		return c.chatAnthropic(ctx, system, messages)
	default: // openai and openai-compatible
		return c.chatOpenAI(ctx, system, messages)
	}
}

func (c *LLMClient) chatAnthropic(ctx context.Context, system string, messages []ChatMessage) (string, error) {
	base := c.cfg.BaseURL
	if base == "" {
		base = "https://api.anthropic.com"
	}
	payload := map[string]interface{}{
		"model":      c.cfg.Model,
		"max_tokens": c.cfg.MaxTokens,
		"system":     system,
		"messages":   messages,
	}
	respBody, err := c.post(ctx, strings.TrimRight(base, "/")+"/v1/messages", payload, map[string]string{
		"x-api-key":         c.cfg.APIKey,
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

func (c *LLMClient) chatOpenAI(ctx context.Context, system string, messages []ChatMessage) (string, error) {
	base := c.cfg.BaseURL
	if base == "" {
		base = "https://api.openai.com"
	}
	msgs := make([]map[string]string, 0, len(messages)+1)
	if system != "" {
		msgs = append(msgs, map[string]string{"role": "system", "content": system})
	}
	for _, m := range messages {
		msgs = append(msgs, map[string]string{"role": m.Role, "content": m.Content})
	}
	payload := map[string]interface{}{
		"model":      c.cfg.Model,
		"messages":   msgs,
		"max_tokens": c.cfg.MaxTokens,
	}
	respBody, err := c.post(ctx, strings.TrimRight(base, "/")+"/v1/chat/completions", payload, map[string]string{
		"Authorization": "Bearer " + c.cfg.APIKey,
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
		return nil, fmt.Errorf("LLM API returned %d: %s", resp.StatusCode, strings.TrimSpace(string(respBody)))
	}
	return respBody, nil
}
