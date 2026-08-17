package database

import (
	"net/url"
	"strings"
	"testing"
)

func TestSQLiteDSNEnablesWALAndConcurrencyGuards(t *testing.T) {
	dsn := sqliteDSN("/tmp/nanolink test.db")

	for _, expected := range []string{
		"_journal_mode=WAL",
		"_busy_timeout=10000",
		"_foreign_keys=on",
		"_synchronous=NORMAL",
	} {
		if !strings.Contains(dsn, expected) {
			t.Fatalf("sqliteDSN() = %q, missing %q", dsn, expected)
		}
	}
}

func TestSQLiteDSNPreservesExistingParameters(t *testing.T) {
	dsn := sqliteDSN("file:/tmp/nanolink.db?cache=shared")
	if !strings.Contains(dsn, "cache=shared&_busy_timeout=") {
		t.Fatalf("sqliteDSN() did not append parameters correctly: %q", dsn)
	}
}

func TestPostgresDSNPreservesCredentialsAndTLSMode(t *testing.T) {
	dsn, err := postgresDSN(Config{
		Host:     "db.internal",
		Port:     5432,
		Database: "nanoops",
		Username: "nanoops_app",
		Password: "a password/with:specials",
		SSLMode:  "require",
	})
	if err != nil {
		t.Fatalf("postgresDSN() error = %v", err)
	}

	parsed, err := url.Parse(dsn)
	if err != nil {
		t.Fatalf("url.Parse() error = %v", err)
	}
	password, ok := parsed.User.Password()
	if !ok || password != "a password/with:specials" {
		t.Fatal("password was not preserved")
	}
	if got := parsed.Query().Get("sslmode"); got != "require" {
		t.Fatalf("sslmode = %q, want require", got)
	}
}

func TestPostgresDSNRejectsInvalidTLSMode(t *testing.T) {
	_, err := postgresDSN(Config{
		Host:     "db.internal",
		Port:     5432,
		Database: "nanoops",
		Username: "nanoops_app",
		SSLMode:  "unsafe-mode",
	})
	if err == nil {
		t.Fatal("postgresDSN() accepted an invalid sslmode")
	}
}
