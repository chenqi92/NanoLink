package nanolink

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestNewServer(t *testing.T) {
	server := NewServer(Config{})

	if server == nil {
		t.Fatal("Expected server to be created")
	}

	if server.config.WsPort != DefaultWsPort {
		t.Errorf("Expected default WebSocket port %d, got %d", DefaultWsPort, server.config.WsPort)
	}

	if server.config.GrpcPort != DefaultGrpcPort {
		t.Errorf("Expected default gRPC port %d, got %d", DefaultGrpcPort, server.config.GrpcPort)
	}
}

func TestNewServerWithCustomConfig(t *testing.T) {
	config := Config{
		WsPort:   8080,
		GrpcPort: 40000,
	}
	server := NewServer(config)

	if server.config.WsPort != 8080 {
		t.Errorf("Expected WebSocket port 8080, got %d", server.config.WsPort)
	}

	if server.config.GrpcPort != 40000 {
		t.Errorf("Expected gRPC port 40000, got %d", server.config.GrpcPort)
	}
}

func TestNewServerWithStaticFilesPath(t *testing.T) {
	config := Config{
		StaticFilesPath: "/path/to/dashboard",
	}
	server := NewServer(config)

	if server.config.StaticFilesPath != "/path/to/dashboard" {
		t.Errorf("Expected StaticFilesPath '/path/to/dashboard', got '%s'", server.config.StaticFilesPath)
	}
}

func TestDefaultTokenValidator(t *testing.T) {
	result := DefaultTokenValidator("any-token")

	if !result.Valid {
		t.Error("Expected default validator to accept all tokens")
	}

	if result.PermissionLevel != 0 {
		t.Errorf("Expected permission level 0, got %d", result.PermissionLevel)
	}
}

func TestCustomTokenValidator(t *testing.T) {
	customValidator := func(token string) ValidationResult {
		if token == "valid-token" {
			return ValidationResult{Valid: true, PermissionLevel: 3}
		}
		return ValidationResult{Valid: false, ErrorMessage: "Invalid token"}
	}

	server := NewServer(Config{
		TokenValidator: customValidator,
	})

	result := server.config.TokenValidator("valid-token")
	if !result.Valid {
		t.Error("Expected valid token to be accepted")
	}
	if result.PermissionLevel != 3 {
		t.Errorf("Expected permission level 3, got %d", result.PermissionLevel)
	}

	result = server.config.TokenValidator("invalid-token")
	if result.Valid {
		t.Error("Expected invalid token to be rejected")
	}
}

func TestGetAgentByHostname(t *testing.T) {
	server := NewServer(Config{})

	// Test with no agents
	agent := server.GetAgentByHostname("test-host")
	if agent != nil {
		t.Error("Expected nil when no agents exist")
	}
}

func TestGetAgents(t *testing.T) {
	server := NewServer(Config{})

	agents := server.GetAgents()
	if len(agents) != 0 {
		t.Errorf("Expected 0 agents, got %d", len(agents))
	}
}

func TestAPIHealth(t *testing.T) {
	server := NewServer(Config{})

	req, err := http.NewRequest("GET", "/api/health", nil)
	if err != nil {
		t.Fatal(err)
	}

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(server.handleAPIHealth)
	handler.ServeHTTP(rr, req)

	if status := rr.Code; status != http.StatusOK {
		t.Errorf("Expected status OK, got %d", status)
	}

	var response map[string]string
	if err := json.NewDecoder(rr.Body).Decode(&response); err != nil {
		t.Errorf("Failed to decode response: %v", err)
	}

	if response["status"] != "ok" {
		t.Errorf("Expected status 'ok', got '%s'", response["status"])
	}
}

func TestAPIAgents(t *testing.T) {
	server := NewServer(Config{})

	req, err := http.NewRequest("GET", "/api/agents", nil)
	if err != nil {
		t.Fatal(err)
	}

	rr := httptest.NewRecorder()
	handler := http.HandlerFunc(server.handleAPIAgents)
	handler.ServeHTTP(rr, req)

	if status := rr.Code; status != http.StatusOK {
		t.Errorf("Expected status OK, got %d", status)
	}

	var response map[string]interface{}
	if err := json.NewDecoder(rr.Body).Decode(&response); err != nil {
		t.Errorf("Failed to decode response: %v", err)
	}

	agents, ok := response["agents"].([]interface{})
	if !ok {
		t.Error("Expected agents array in response")
	}

	if len(agents) != 0 {
		t.Errorf("Expected 0 agents, got %d", len(agents))
	}
}

func TestPermissionConstants(t *testing.T) {
	if PermissionReadOnly != 0 {
		t.Errorf("Expected PermissionReadOnly to be 0, got %d", PermissionReadOnly)
	}
	if PermissionBasicWrite != 1 {
		t.Errorf("Expected PermissionBasicWrite to be 1, got %d", PermissionBasicWrite)
	}
	if PermissionServiceControl != 2 {
		t.Errorf("Expected PermissionServiceControl to be 2, got %d", PermissionServiceControl)
	}
	if PermissionSystemAdmin != 3 {
		t.Errorf("Expected PermissionSystemAdmin to be 3, got %d", PermissionSystemAdmin)
	}
}
