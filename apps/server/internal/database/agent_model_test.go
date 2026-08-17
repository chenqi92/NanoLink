package database

import (
	"testing"
	"time"
)

func TestAgentTokenOnlineWindowAllowsMissedHeartbeats(t *testing.T) {
	recent := time.Now().Add(-90 * time.Second)
	stale := time.Now().Add(-150 * time.Second)

	if !(&AgentToken{LastSeenAt: &recent}).IsOnline() {
		t.Fatal("agent seen 90 seconds ago should remain online")
	}
	if (&AgentToken{LastSeenAt: &stale}).IsOnline() {
		t.Fatal("agent seen 150 seconds ago should be offline")
	}
	if (&AgentToken{}).IsOnline() {
		t.Fatal("agent without a last-seen timestamp should be offline")
	}
}
