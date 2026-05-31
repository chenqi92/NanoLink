package handler

import "testing"

func TestMapRequestTypeRejectsUnknown(t *testing.T) {
	if _, ok := mapRequestType("everything"); ok {
		t.Fatal("unknown request type should be rejected")
	}
}

func TestMapRequestTypeAcceptsKnown(t *testing.T) {
	for _, reqType := range []string{"full", "static", "disk_usage", "network_info", "user_sessions", "gpu_info", "health"} {
		if _, ok := mapRequestType(reqType); !ok {
			t.Fatalf("known request type %q should be accepted", reqType)
		}
	}
}
