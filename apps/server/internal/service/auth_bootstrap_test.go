package service

import (
	"testing"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"go.uber.org/zap"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func TestBootstrapAdminPasswordRotationRevokesExistingSessions(t *testing.T) {
	db, err := gorm.Open(sqlite.Open("file:auth-bootstrap?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&database.User{}); err != nil {
		t.Fatal(err)
	}

	newService := func(password string) *AuthService {
		svc := NewAuthService(db, AuthConfig{
			JWTSecret: "0123456789abcdef0123456789abcdef",
			JWTExpire: time.Hour,
			AdminUser: "admin",
			AdminPass: password,
		}, zap.NewNop().Sugar())
		t.Cleanup(svc.loginLimiter.Stop)
		return svc
	}

	first := newService("InitialPass1")
	user, err := first.GetUserByUsername("admin")
	if err != nil {
		t.Fatal(err)
	}
	oldVersion := user.TokenVersion

	newService("RotatedPass2")
	rotated, err := first.GetUserByUsername("admin")
	if err != nil {
		t.Fatal(err)
	}
	if rotated.TokenVersion <= oldVersion {
		t.Fatalf("token version did not increase: old=%d new=%d", oldVersion, rotated.TokenVersion)
	}
	if err := bcrypt.CompareHashAndPassword([]byte(rotated.PasswordHash), []byte("RotatedPass2")); err != nil {
		t.Fatalf("rotated password was not persisted: %v", err)
	}
	if err := bcrypt.CompareHashAndPassword([]byte(rotated.PasswordHash), []byte("InitialPass1")); err == nil {
		t.Fatal("old bootstrap password is still valid")
	}
}
