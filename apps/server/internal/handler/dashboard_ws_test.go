package handler

import (
	"testing"

	"github.com/chenqi92/NanoLink/apps/server/internal/service"
)

func TestAgentToMapUsesPermissionLevelContract(t *testing.T) {
	payload := agentToMap(&service.Agent{
		ID:              "agent-l3",
		PermissionLevel: 3,
	})

	if got := payload["permissionLevel"]; got != 3 {
		t.Fatalf("permissionLevel = %#v, want 3", got)
	}
	if _, exists := payload["permission"]; exists {
		t.Fatal("legacy permission field must not be emitted")
	}
}
