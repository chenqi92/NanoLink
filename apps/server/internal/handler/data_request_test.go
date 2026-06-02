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

func TestParseTimestampRejectsInvalidInput(t *testing.T) {
	if _, err := parseTimestamp("not-a-date"); err == nil {
		t.Fatal("expected invalid timestamp to return an error")
	}
}

func TestParseTimestampAcceptsUnixMilliseconds(t *testing.T) {
	got, err := parseTimestamp("1717200000000")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got.IsZero() {
		t.Fatal("expected a parsed timestamp")
	}
}
