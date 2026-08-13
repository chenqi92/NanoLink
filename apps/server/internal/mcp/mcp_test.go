package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"go.uber.org/zap"
)

// mockAgentService implements a minimal AgentService for testing
type mockAgentService struct{}

func (m *mockAgentService) GetAllAgents() []mockAgent {
	return []mockAgent{
		{ID: "agent-1", Hostname: "server-1", OS: "linux", Arch: "amd64"},
		{ID: "agent-2", Hostname: "server-2", OS: "windows", Arch: "amd64"},
	}
}

func (m *mockAgentService) GetAgent(id string) *mockAgent {
	for _, a := range m.GetAllAgents() {
		if a.ID == id {
			return &a
		}
	}
	return nil
}

func (m *mockAgentService) GetAgentByHostname(hostname string) *mockAgent {
	for _, a := range m.GetAllAgents() {
		if a.Hostname == hostname {
			return &a
		}
	}
	return nil
}

type mockAgent struct {
	ID       string
	Hostname string
	OS       string
	Arch     string
}

// mockMetricsService implements a minimal MetricsService for testing
type mockMetricsService struct{}

func (m *mockMetricsService) GetCurrentMetrics(agentID string) map[string]interface{} {
	return map[string]interface{}{
		"cpu": map[string]interface{}{
			"usage_percent": 45.5,
		},
		"memory": map[string]interface{}{
			"total": uint64(16000000000),
			"used":  uint64(8000000000),
		},
	}
}

func (m *mockMetricsService) GetAllCurrentMetrics() map[string]map[string]interface{} {
	return map[string]map[string]interface{}{
		"agent-1": m.GetCurrentMetrics("agent-1"),
		"agent-2": m.GetCurrentMetrics("agent-2"),
	}
}

func (m *mockMetricsService) GetSummary() map[string]interface{} {
	return map[string]interface{}{
		"total_agents":           2,
		"average_cpu_percent":    45.5,
		"average_memory_percent": 50.0,
	}
}

func TestJSONRPCParsing(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		wantErr bool
	}{
		{
			name:    "valid initialize request",
			input:   `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}`,
			wantErr: false,
		},
		{
			name:    "valid tools/list request",
			input:   `{"jsonrpc":"2.0","id":2,"method":"tools/list"}`,
			wantErr: false,
		},
		{
			name:    "invalid json",
			input:   `{"jsonrpc":"2.0",`,
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var msg JSONRPCMessage
			err := json.Unmarshal([]byte(tt.input), &msg)
			if (err != nil) != tt.wantErr {
				t.Errorf("Unmarshal() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestToolsListResponse(t *testing.T) {
	// Create a mock response
	tools := []map[string]interface{}{
		{
			"name":        "list_agents",
			"description": "List all connected monitoring agents",
			"inputSchema": map[string]interface{}{
				"type":       "object",
				"properties": map[string]interface{}{},
			},
		},
	}

	result := map[string]interface{}{
		"tools": tools,
	}

	response := JSONRPCMessage{
		JSONRPC: "2.0",
		ID:      1,
		Result:  result,
	}

	data, err := json.Marshal(response)
	if err != nil {
		t.Fatalf("Failed to marshal response: %v", err)
	}

	var parsed JSONRPCMessage
	if err := json.Unmarshal(data, &parsed); err != nil {
		t.Fatalf("Failed to unmarshal response: %v", err)
	}

	if parsed.JSONRPC != "2.0" {
		t.Errorf("Expected jsonrpc 2.0, got %s", parsed.JSONRPC)
	}
}

func TestErrorResponse(t *testing.T) {
	response := JSONRPCMessage{
		JSONRPC: "2.0",
		ID:      nil,
		Error: &JSONRPCError{
			Code:    ParseError,
			Message: "Parse error",
		},
	}

	data, err := json.Marshal(response)
	if err != nil {
		t.Fatalf("Failed to marshal error response: %v", err)
	}

	var parsed JSONRPCMessage
	if err := json.Unmarshal(data, &parsed); err != nil {
		t.Fatalf("Failed to unmarshal error response: %v", err)
	}

	if parsed.Error == nil {
		t.Fatal("Expected error in response")
	}

	if parsed.Error.Code != ParseError {
		t.Errorf("Expected error code %d, got %d", ParseError, parsed.Error.Code)
	}
}

func TestFormatToolResult(t *testing.T) {
	tests := []struct {
		name   string
		input  interface{}
		expect string
	}{
		{
			name:   "string result",
			input:  "Hello, World!",
			expect: "Hello, World!",
		},
		{
			name:   "map result",
			input:  map[string]interface{}{"count": 5},
			expect: "", // Will be JSON formatted
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := formatToolResult(tt.input)
			if len(result) == 0 {
				t.Error("Expected non-empty result")
			}
			if result[0]["type"] != "text" {
				t.Errorf("Expected type 'text', got %v", result[0]["type"])
			}
		})
	}
}

func TestPromptMessageFormat(t *testing.T) {
	msg := PromptMessage{
		Role: "user",
		Content: PromptContent{
			Type: "text",
			Text: "Test message",
		},
	}

	data, err := json.Marshal(msg)
	if err != nil {
		t.Fatalf("Failed to marshal prompt message: %v", err)
	}

	var parsed PromptMessage
	if err := json.Unmarshal(data, &parsed); err != nil {
		t.Fatalf("Failed to unmarshal prompt message: %v", err)
	}

	if parsed.Role != "user" {
		t.Errorf("Expected role 'user', got '%s'", parsed.Role)
	}
	if parsed.Content.Text != "Test message" {
		t.Errorf("Expected text 'Test message', got '%s'", parsed.Content.Text)
	}
}

func TestInitializeResponse(t *testing.T) {
	// Simulate initialize response
	result := map[string]interface{}{
		"protocolVersion": "2024-11-05",
		"serverInfo": ServerInfo{
			Name:    "nanolink",
			Version: "0.3.1",
		},
		"capabilities": Capabilities{
			Tools:     &ToolsCapability{ListChanged: false},
			Resources: &ResourcesCapability{Subscribe: false, ListChanged: false},
			Prompts:   &PromptsCapability{ListChanged: false},
		},
	}

	data, err := json.Marshal(result)
	if err != nil {
		t.Fatalf("Failed to marshal initialize result: %v", err)
	}

	if len(data) == 0 {
		t.Error("Expected non-empty initialize result")
	}
}

func TestResourceURIParsing(t *testing.T) {
	tests := []struct {
		uri         string
		wantAgentID string
		wantSub     string
		wantOK      bool
	}{
		{"nanolink://agents/agent-1/metrics", "agent-1", "metrics", true},
		{"nanolink://agents/agent-1/static", "agent-1", "static", true},
		{"nanolink://agents/agent-1", "agent-1", "", true},
		{"nanolink://summary", "", "", false},
		{"invalid://uri", "", "", false},
	}

	for _, tt := range tests {
		t.Run(tt.uri, func(t *testing.T) {
			agentID, sub, ok := parseAgentURI(tt.uri)
			if ok != tt.wantOK {
				t.Errorf("parseAgentURI(%s) ok = %v, want %v", tt.uri, ok, tt.wantOK)
			}
			if ok {
				if agentID != tt.wantAgentID {
					t.Errorf("parseAgentURI(%s) agentID = %v, want %v", tt.uri, agentID, tt.wantAgentID)
				}
				if sub != tt.wantSub {
					t.Errorf("parseAgentURI(%s) sub = %v, want %v", tt.uri, sub, tt.wantSub)
				}
			}
		})
	}
}

type blockingTestTransport struct {
	closed chan struct{}
	once   sync.Once
}

func (t *blockingTestTransport) ReadMessage() ([]byte, error) {
	<-t.closed
	return nil, context.Canceled
}

func (t *blockingTestTransport) WriteMessage([]byte) error { return nil }
func (t *blockingTestTransport) Close() error {
	t.once.Do(func() { close(t.closed) })
	return nil
}

// Benchmark tests
func TestSnapshotSortsToolsAndHidesExecutionData(t *testing.T) {
	s := NewServer(nil, nil, zap.NewNop().Sugar())
	s.tools = map[string]*Tool{
		"z_tool": {Name: "z_tool", Description: "last", InputSchema: map[string]interface{}{"type": "object"}},
		"a_tool": {Name: "a_tool", Description: "first", InputSchema: map[string]interface{}{"type": "object"}},
	}
	s.recordActivity("z_tool", time.Now().Add(-time.Millisecond), true)

	overview := s.Snapshot()
	if overview.Enabled || overview.State != "disabled" {
		t.Fatalf("disabled snapshot = %#v", overview)
	}
	if len(overview.Tools) != 2 || overview.Tools[0].Name != "a_tool" || overview.Tools[1].Name != "z_tool" {
		t.Fatalf("tools were not sorted: %#v", overview.Tools)
	}
	data, err := json.Marshal(overview)
	if err != nil {
		t.Fatal(err)
	}
	for _, forbidden := range []string{"arguments", "result", "apiKey", "token"} {
		if strings.Contains(string(data), forbidden) {
			t.Fatalf("snapshot contains forbidden field %q: %s", forbidden, data)
		}
	}
}

func TestActivityIsNewestFirstAndBounded(t *testing.T) {
	s := NewServer(nil, nil, zap.NewNop().Sugar())
	for i := 0; i < 55; i++ {
		s.recordActivity(fmt.Sprintf("tool-%d", i), time.Now(), i%2 == 0)
	}
	overview := s.Snapshot()
	if len(overview.Activity) != 50 {
		t.Fatalf("activity length = %d, want 50", len(overview.Activity))
	}
	if overview.Activity[0].ToolName != "tool-54" || overview.Activity[49].ToolName != "tool-5" {
		t.Fatalf("activity order = first %q last %q", overview.Activity[0].ToolName, overview.Activity[49].ToolName)
	}
}

func TestSnapshotReportsStoppedAfterServeReturns(t *testing.T) {
	transport := &blockingTestTransport{closed: make(chan struct{})}
	s := NewServer(nil, nil, zap.NewNop().Sugar(), WithTransport(transport), WithTransportName("test"))
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- s.Serve(ctx) }()

	deadline := time.Now().Add(time.Second)
	for s.Snapshot().State != "running" && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if state := s.Snapshot().State; state != "running" {
		t.Fatalf("state before cancellation = %q", state)
	}
	cancel()
	<-done
	if state := s.Snapshot().State; state != "stopped" {
		t.Fatalf("state after cancellation = %q", state)
	}
}

func BenchmarkJSONRPCParsing(b *testing.B) {
	input := []byte(`{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}`)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		var msg JSONRPCMessage
		_ = json.Unmarshal(input, &msg)
	}
}

func BenchmarkFormatToolResult(b *testing.B) {
	input := map[string]interface{}{
		"count":  5,
		"agents": []string{"a", "b", "c"},
	}
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = formatToolResult(input)
	}
}

// Integration-style test for message handling
func TestMessageHandlingFlow(t *testing.T) {
	ctx := context.Background()

	// Test initialize message format
	initMsg := JSONRPCMessage{
		JSONRPC: "2.0",
		ID:      1,
		Method:  "initialize",
		Params:  json.RawMessage(`{}`),
	}

	data, _ := json.Marshal(initMsg)
	var parsed JSONRPCMessage
	_ = json.Unmarshal(data, &parsed)

	if parsed.Method != "initialize" {
		t.Errorf("Expected method 'initialize', got '%s'", parsed.Method)
	}

	// Verify context is usable
	select {
	case <-ctx.Done():
		t.Error("Context should not be done")
	default:
		// OK
	}
}
