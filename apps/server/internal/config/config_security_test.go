package config

import "testing"

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
