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

func TestBootstrapStatusClosesRegistrationAfterFirstAccount(t *testing.T) {
	db, err := gorm.Open(sqlite.Open("file:auth-bootstrap-status?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&database.User{}); err != nil {
		t.Fatal(err)
	}
	svc := NewAuthService(db, AuthConfig{
		JWTSecret:               "0123456789abcdef0123456789abcdef",
		AllowPublicRegistration: true,
	}, zap.NewNop().Sugar())
	t.Cleanup(svc.loginLimiter.Stop)

	hasUsers, registrationEnabled, err := svc.BootstrapStatus()
	if err != nil || hasUsers || !registrationEnabled {
		t.Fatalf("unexpected empty bootstrap status: hasUsers=%v registration=%v err=%v", hasUsers, registrationEnabled, err)
	}
	if _, err := svc.RegisterFirstSuperAdmin("admin", "InitialPass1", ""); err != nil {
		t.Fatal(err)
	}
	hasUsers, registrationEnabled, err = svc.BootstrapStatus()
	if err != nil || !hasUsers || registrationEnabled {
		t.Fatalf("unexpected initialized bootstrap status: hasUsers=%v registration=%v err=%v", hasUsers, registrationEnabled, err)
	}
}
