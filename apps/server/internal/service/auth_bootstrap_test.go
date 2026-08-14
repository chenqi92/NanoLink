package service

import (
	"errors"
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

func TestPublicRegistrationSwitchDefaultsClosedAndCreatesRegularUsersAfterBootstrap(t *testing.T) {
	db, err := gorm.Open(sqlite.Open("file:auth-bootstrap-status?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&database.User{}, &database.Setting{}); err != nil {
		t.Fatal(err)
	}
	svc := NewAuthService(db, AuthConfig{
		JWTSecret: "0123456789abcdef0123456789abcdef",
	}, zap.NewNop().Sugar())
	t.Cleanup(svc.loginLimiter.Stop)

	hasUsers, registrationEnabled, err := svc.BootstrapStatus()
	if err != nil || hasUsers || registrationEnabled {
		t.Fatalf("unexpected empty bootstrap status: hasUsers=%v registration=%v err=%v", hasUsers, registrationEnabled, err)
	}
	if _, err := svc.RegisterPublicUser("blocked", "InitialPass1", ""); !errors.Is(err, ErrRegistrationDisabled) {
		t.Fatalf("registration should be disabled by default, got %v", err)
	}
	if err := svc.SetPublicRegistrationEnabled(true); err != nil {
		t.Fatal(err)
	}
	admin, err := svc.RegisterPublicUser("admin", "InitialPass1", "")
	if err != nil {
		t.Fatal(err)
	}
	if !admin.IsSuperAdmin {
		t.Fatal("first public account must bootstrap the super admin")
	}
	hasUsers, registrationEnabled, err = svc.BootstrapStatus()
	if err != nil || !hasUsers || registrationEnabled {
		t.Fatalf("registration did not auto-close after bootstrap: hasUsers=%v registration=%v err=%v", hasUsers, registrationEnabled, err)
	}
	if _, err := svc.RegisterPublicUser("blocked-after-bootstrap", "BlockedPass2", ""); !errors.Is(err, ErrRegistrationDisabled) {
		t.Fatalf("bootstrap registration remained open: %v", err)
	}
	if err := svc.SetPublicRegistrationEnabled(true); err != nil {
		t.Fatal(err)
	}
	user, err := svc.RegisterPublicUser("operator", "OperatorPass2", "")
	if err != nil {
		t.Fatal(err)
	}
	if user.IsSuperAdmin {
		t.Fatal("subsequent public account must be a regular user")
	}
	hasUsers, registrationEnabled, err = svc.BootstrapStatus()
	if err != nil || !hasUsers || !registrationEnabled {
		t.Fatalf("unexpected initialized bootstrap status: hasUsers=%v registration=%v err=%v", hasUsers, registrationEnabled, err)
	}
	if err := svc.SetPublicRegistrationEnabled(false); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.RegisterPublicUser("blocked-again", "BlockedPass3", ""); !errors.Is(err, ErrRegistrationDisabled) {
		t.Fatalf("registration switch did not close endpoint: %v", err)
	}
}

func TestConfigRegistrationFlagIsOneTimeBootstrapFallback(t *testing.T) {
	db, err := gorm.Open(sqlite.Open("file:auth-config-registration?mode=memory&cache=shared"), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.AutoMigrate(&database.User{}, &database.Setting{}); err != nil {
		t.Fatal(err)
	}
	svc := NewAuthService(db, AuthConfig{
		JWTSecret:               "0123456789abcdef0123456789abcdef",
		AllowPublicRegistration: true,
	}, zap.NewNop().Sugar())
	t.Cleanup(svc.loginLimiter.Stop)

	if enabled, err := svc.PublicRegistrationEnabled(); err != nil || !enabled {
		t.Fatalf("empty-server bootstrap enabled = %v, err = %v", enabled, err)
	}
	if _, err := svc.RegisterPublicUser("admin", "InitialPass1", ""); err != nil {
		t.Fatal(err)
	}
	if enabled, err := svc.PublicRegistrationEnabled(); err != nil || enabled {
		t.Fatalf("config fallback remained open after bootstrap: enabled=%v err=%v", enabled, err)
	}
}
