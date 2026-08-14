package service

import (
	"errors"
	"testing"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"go.uber.org/zap"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func TestGroupAgentRangeDrivesEffectivePermissions(t *testing.T) {
	db, err := gorm.Open(sqlite.Open("file:"+t.Name()+"?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(
		&database.User{},
		&database.Group{},
		&database.AgentGroup{},
		&database.UserAgentPermission{},
	); err != nil {
		t.Fatal(err)
	}

	groups := NewGroupService(db, zap.NewNop().Sugar())
	permissions := NewPermissionService(db, zap.NewNop().Sugar())
	group, err := groups.CreateGroup("developers", "", 2, "legacy text", []string{"agent-a", "agent-b", "agent-a"})
	if err != nil {
		t.Fatal(err)
	}
	if len(group.AgentGroups) != 2 {
		t.Fatalf("agent assignments = %d, want 2", len(group.AgentGroups))
	}

	user := database.User{Username: "operator", PasswordHash: "unused"}
	if err := db.Create(&user).Error; err != nil {
		t.Fatal(err)
	}
	if err := groups.AddUserToGroup(user.ID, group.ID); err != nil {
		t.Fatal(err)
	}
	if got, err := permissions.GetUserAgentPermission(user.ID, "agent-a"); err != nil || got != 2 {
		t.Fatalf("initial group permission = %d, err=%v, want 2", got, err)
	}

	level := 3
	rangeIDs := []string{"agent-b", "agent-c"}
	group, err = groups.UpdateGroup(group.ID, group.Name, group.Description, &level, nil, &rangeIDs)
	if err != nil {
		t.Fatal(err)
	}
	if len(group.AgentGroups) != 2 {
		t.Fatalf("updated assignments = %d, want 2", len(group.AgentGroups))
	}
	for _, assignment := range group.AgentGroups {
		if assignment.PermissionLevel != 3 {
			t.Fatalf("assignment %s level = %d, want 3", assignment.AgentID, assignment.PermissionLevel)
		}
	}
	if _, err := permissions.GetUserAgentPermission(user.ID, "agent-a"); !errors.Is(err, ErrPermissionDenied) {
		t.Fatalf("removed agent remains visible: %v", err)
	}
	if got, err := permissions.GetUserAgentPermission(user.ID, "agent-c"); err != nil || got != 3 {
		t.Fatalf("new group permission = %d, err=%v, want 3", got, err)
	}
}
