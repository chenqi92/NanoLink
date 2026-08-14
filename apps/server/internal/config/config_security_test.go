package config

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/spf13/viper"
)

func TestWeakSecretDetection(t *testing.T) {
	for _, secret := range []string{"", "short", "your-secret-key-change-me-0123456789"} {
		if !isWeakSecret(secret) {
			t.Fatalf("expected %q to be rejected", secret)
		}
	}
	if isWeakSecret("0123456789abcdef0123456789abcdef") {
		t.Fatal("high-entropy-length secret was rejected")
	}
}

func TestBootstrapPasswordStrength(t *testing.T) {
	for _, password := range []string{"changeme", "password", "12345678", "Short1"} {
		if isStrongBootstrapPassword(password) {
			t.Fatalf("expected %q to be rejected", password)
		}
	}
	if !isStrongBootstrapPassword("StrongPass1") {
		t.Fatal("strong bootstrap password was rejected")
	}
}

func TestReleaseModeIsCaseInsensitive(t *testing.T) {
	for _, mode := range []string{"release", "Release", " RELEASE "} {
		if !isReleaseMode(mode) {
			t.Fatalf("expected %q to be recognized as release mode", mode)
		}
	}
}

func TestServerPortsLoadFromContainerEnvironment(t *testing.T) {
	viper.Reset()
	t.Cleanup(viper.Reset)
	t.Setenv("NANOLINK_SERVER_HTTP_PORT", "18080")
	t.Setenv("NANOLINK_SERVER_WS_PORT", "19100")
	t.Setenv("NANOLINK_SERVER_GRPC_PORT", "19200")
	path := filepath.Join(t.TempDir(), "nanolink.yaml")
	if err := os.WriteFile(path, []byte("{}\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	cfg, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Server.HTTPPort != 18080 || cfg.Server.WSPort != 19100 || cfg.Server.GRPCPort != 19200 {
		t.Fatalf("server port environment ignored: %#v", cfg.Server)
	}
}

func TestPostgresConfigLoadsFromContainerEnvironment(t *testing.T) {
	viper.Reset()
	t.Cleanup(viper.Reset)
	t.Setenv("NANOLINK_DATABASE_TYPE", "postgres")
	t.Setenv("NANOLINK_DATABASE_HOST", "db.internal")
	t.Setenv("NANOLINK_DATABASE_PORT", "15432")
	t.Setenv("NANOLINK_DATABASE_NAME", "nanoops")
	t.Setenv("NANOLINK_DATABASE_USERNAME", "nanoops_app")
	t.Setenv("NANOLINK_DATABASE_PASSWORD", "secret-value")
	t.Setenv("NANOLINK_DATABASE_SSLMODE", "require")
	path := filepath.Join(t.TempDir(), "nanolink.yaml")
	if err := os.WriteFile(path, []byte("{}\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	cfg, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Database.Type != "postgres" || cfg.Database.Host != "db.internal" || cfg.Database.Port != 15432 {
		t.Fatalf("database endpoint environment ignored: %#v", cfg.Database)
	}
	if cfg.Database.Database != "nanoops" || cfg.Database.Username != "nanoops_app" {
		t.Fatalf("database identity environment ignored: %#v", cfg.Database)
	}
	if cfg.Database.Password != "secret-value" || cfg.Database.SSLMode != "require" {
		t.Fatal("database credentials or TLS environment ignored")
	}
}
