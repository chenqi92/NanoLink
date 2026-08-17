package handler

import (
	"testing"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	pb "github.com/chenqi92/NanoLink/apps/server/internal/proto"
)

func TestPackageInstallRequiresSystemAdmin(t *testing.T) {
	if got := commandRequiredPermission(pb.CommandType_PACKAGE_INSTALL); got != database.PermissionSystemAdmin {
		t.Fatalf("PACKAGE_INSTALL permission = %d, want %d", got, database.PermissionSystemAdmin)
	}
}
