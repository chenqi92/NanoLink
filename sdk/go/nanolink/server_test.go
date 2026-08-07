package nanolink

import (
	"context"
	"testing"

	"google.golang.org/grpc/metadata"
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

func TestStreamBearerMetadataIsValidated(t *testing.T) {
	server := NewServer(Config{TokenValidator: func(token string) ValidationResult {
		return ValidationResult{Valid: token == "valid", PermissionLevel: PermissionSystemAdmin}
	}})
	servicer := NewNanoLinkServicer(server)
	ctx := metadata.NewIncomingContext(context.Background(), metadata.Pairs("authorization", "Bearer valid"))
	result, authenticated, err := servicer.authenticateStream(ctx)
	if err != nil || !authenticated || result.PermissionLevel != PermissionSystemAdmin {
		t.Fatalf("valid stream credential rejected: authenticated=%v result=%+v err=%v", authenticated, result, err)
	}

	badCtx := metadata.NewIncomingContext(context.Background(), metadata.Pairs("authorization", "Bearer invalid"))
	if _, _, err := servicer.authenticateStream(badCtx); err == nil {
		t.Fatal("invalid stream credential was accepted")
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

	if result.Valid {
		t.Error("Expected default validator to reject tokens")
	}
}

func TestNewServerRequiresAuthenticationByDefault(t *testing.T) {
	server := NewServer(Config{})
	if !server.config.RequireAuthentication {
		t.Fatal("expected authentication to be required by default")
	}
}

func TestUnauthenticatedMetricsRequireExplicitOptOut(t *testing.T) {
	server := NewServer(Config{AllowUnauthenticatedMetrics: true})
	if server.config.RequireAuthentication {
		t.Fatal("expected explicit compatibility opt-out to allow anonymous metrics")
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
