package grpc

import (
	"testing"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	pb "github.com/chenqi92/NanoLink/apps/server/internal/proto"
)

func TestRequiredPermissionMatchesAgentForOperationalCommands(t *testing.T) {
	tests := []struct {
		command pb.CommandType
		want    int
	}{
		{pb.CommandType_SERVICE_LIST, database.PermissionReadOnly},
		{pb.CommandType_FILE_LIST, database.PermissionReadOnly},
		{pb.CommandType_FILE_UPLOAD, database.PermissionSystemAdmin},
		{pb.CommandType_AGENT_APPLY_UPDATE, database.PermissionSystemAdmin},
		{pb.CommandType_DEPLOY_EXECUTE, database.PermissionSystemAdmin},
	}

	for _, test := range tests {
		if got := requiredPermissionForCommand(test.command); got != test.want {
			t.Fatalf("%s permission = %d, want %d", test.command, got, test.want)
		}
	}
}
