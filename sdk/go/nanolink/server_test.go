package nanolink

import (
	"testing"
)

func TestNewServer(t *testing.T) {
	server := NewServer(Config{})

	if server == nil {
		t.Fatal("Expected server to be created")
	}

	if server.config.GrpcPort != DefaultGrpcPort {
		t.Errorf("Expected default gRPC port %d, got %d", DefaultGrpcPort, server.config.GrpcPort)
	}
}

func TestNewServerWithCustomConfig(t *testing.T) {
	config := Config{
		GrpcPort: 40000,
	}
	server := NewServer(config)

	if server.config.GrpcPort != 40000 {
		t.Errorf("Expected gRPC port 40000, got %d", server.config.GrpcPort)
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
