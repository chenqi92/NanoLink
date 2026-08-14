package service

import (
	"testing"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"go.uber.org/zap"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func TestSuperAdminPermissionUsesAgentTokenCeiling(t *testing.T) {
	db, err := gorm.Open(sqlite.Open("file:"+t.Name()+"?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(
		&database.User{},
		&database.Group{},
		&database.AgentGroup{},
		&database.AgentToken{},
	); err != nil {
		t.Fatal(err)
	}
	admin := database.User{Username: "admin", PasswordHash: "unused", IsSuperAdmin: true}
	if err := db.Create(&admin).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Create(&database.AgentToken{
		Token:      "hashed-token",
		TokenHint:  "****test",
		Name:       "read-only",
		AgentID:    "agent-read-only",
		Permission: database.PermissionReadOnly,
	}).Error; err != nil {
		t.Fatal(err)
	}

	permissions := NewPermissionService(db, zap.NewNop().Sugar())
	level, err := permissions.GetUserAgentPermission(admin.ID, "agent-read-only")
	if err != nil {
		t.Fatal(err)
	}
	if level != database.PermissionReadOnly {
		t.Fatalf("super admin permission = %d, want read-only node ceiling", level)
	}
}
