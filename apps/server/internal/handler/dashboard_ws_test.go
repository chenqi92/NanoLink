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

func TestCapPermissionLevelUsesLowerBoundary(t *testing.T) {
	tests := []struct {
		name       string
		granted    int
		agentLimit int
		want       int
	}{
		{name: "user grant limits agent", granted: 1, agentLimit: 3, want: 1},
		{name: "agent token limits user", granted: 3, agentLimit: 1, want: 1},
		{name: "read only", granted: 0, agentLimit: 3, want: 0},
		{name: "missing permission is safe", granted: -1, agentLimit: 3, want: 0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := capPermissionLevel(tt.granted, tt.agentLimit); got != tt.want {
				t.Fatalf("capPermissionLevel(%d, %d) = %d, want %d", tt.granted, tt.agentLimit, got, tt.want)
			}
		})
	}
}
