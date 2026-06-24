package nanolink

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// permissionMatrix mirrors the structure of sdk/protocol/permissions.json.
type permissionMatrix struct {
	Levels   map[string]int `json:"levels"`
	Default  int            `json:"default"`
	Commands []struct {
		Name  string `json:"name"`
		Code  int    `json:"code"`
		Level int    `json:"level"`
	} `json:"commands"`
}

func loadPermissionMatrix(t *testing.T) permissionMatrix {
	t.Helper()
	path := filepath.Join("..", "..", "protocol", "permissions.json")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("cannot read %s: %v", path, err)
	}
	var m permissionMatrix
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatalf("cannot parse %s: %v", path, err)
	}
	return m
}

// TestRequiredPermissionMatrix asserts that the Go SDK's RequiredPermission map
// matches the canonical matrix in sdk/protocol/permissions.json for every
// command type, so future drift between the SDKs is caught.
func TestRequiredPermissionMatrix(t *testing.T) {
	m := loadPermissionMatrix(t)

	for _, entry := range m.Commands {
		// CommandType is an int code; build the command directly from the
		// canonical numeric code so the JSON remains the single source of truth.
		cmd := &Command{Type: CommandType(entry.Code)}
		got := cmd.RequiredPermission()
		if got != entry.Level {
			t.Errorf("%s (code %d): got level %d, expected %d",
				entry.Name, entry.Code, got, entry.Level)
		}
	}
}

// TestRequiredPermissionDefaultFailClosed verifies an unknown command code
// resolves to the fail-closed default level from the canonical matrix.
func TestRequiredPermissionDefaultFailClosed(t *testing.T) {
	m := loadPermissionMatrix(t)
	cmd := &Command{Type: CommandType(9999)}
	if got := cmd.RequiredPermission(); got != m.Default {
		t.Errorf("unknown command: got level %d, expected default %d", got, m.Default)
	}
}
