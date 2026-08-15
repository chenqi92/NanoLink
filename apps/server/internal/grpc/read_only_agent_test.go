package grpc

import (
	"testing"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
)

func TestEffectiveAgentPermissionCapsReadOnlyRuntime(t *testing.T) {
	if got := effectiveAgentPermission(database.PermissionSystemAdmin, true); got != database.PermissionReadOnly {
		t.Fatalf("read-only Agent permission = %d, want %d", got, database.PermissionReadOnly)
	}
	if got := effectiveAgentPermission(database.PermissionServiceControl, false); got != database.PermissionServiceControl {
		t.Fatalf("normal Agent permission = %d, want %d", got, database.PermissionServiceControl)
	}
}
