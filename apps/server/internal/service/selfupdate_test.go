package service

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"go.uber.org/zap"

	"github.com/chenqi92/NanoLink/apps/server/internal/config"
	"github.com/chenqi92/NanoLink/apps/server/internal/version"
)

// newTestService returns a service wired to talk to an httptest TLS server.
// getJSON refuses plain http, so the transport has to trust the test CA.
func newTestService(t *testing.T, cfg config.UpdateConfig, srv *httptest.Server) *SelfUpdateService {
	t.Helper()
	s := NewSelfUpdateService(cfg, zap.NewNop().Sugar())
	if srv != nil {
		s.client = srv.Client()
	}
	return s
}

func TestFetchManifestReleaseResolvesThisPlatform(t *testing.T) {
	platform := version.Platform()
	manifest := ReleaseManifest{
		Version:     "v9.9.9",
		ReleaseDate: "2026-08-11T00:00:00Z",
		Changelog:   "notes",
		MinVersion:  "v0.4.0",
		Assets:      map[string]string{platform: "nanolink-server-" + platform},
		Checksums:   map[string]string{platform: "deadbeef"},
		Signatures:  map[string]string{platform: "cafebabe"},
	}

	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/version.json" {
			t.Errorf("unexpected manifest path %q", r.URL.Path)
		}
		_ = json.NewEncoder(w).Encode(manifest)
	}))
	defer srv.Close()

	s := newTestService(t, config.UpdateConfig{Source: "custom", CustomURL: srv.URL}, srv)
	rel, err := s.fetchManifestRelease(context.Background(), srv.URL)
	if err != nil {
		t.Fatalf("fetchManifestRelease: %v", err)
	}

	// The "v" prefix must be stripped so comparisons against version.Version work.
	if rel.version != "9.9.9" {
		t.Errorf("version = %q, want 9.9.9", rel.version)
	}
	if rel.minVersion != "0.4.0" {
		t.Errorf("minVersion = %q, want 0.4.0", rel.minVersion)
	}
	if want := srv.URL + "/nanolink-server-" + platform; rel.downloadURL != want {
		t.Errorf("downloadURL = %q, want %q", rel.downloadURL, want)
	}
	if rel.signature != "cafebabe" || rel.checksum != "deadbeef" {
		t.Errorf("signature/checksum not picked up: %+v", rel)
	}
}

func TestFetchManifestReleaseWithoutAssetForThisPlatform(t *testing.T) {
	// A manifest that only publishes some other platform must parse cleanly and
	// leave downloadURL empty, so applyBlocker can explain the gap.
	manifest := ReleaseManifest{
		Version: "9.9.9",
		Assets:  map[string]string{"solaris-sparc": "nanolink-server-solaris-sparc"},
	}
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(manifest)
	}))
	defer srv.Close()

	s := newTestService(t, config.UpdateConfig{Source: "custom", CustomURL: srv.URL}, srv)
	rel, err := s.fetchManifestRelease(context.Background(), srv.URL)
	if err != nil {
		t.Fatalf("fetchManifestRelease: %v", err)
	}
	if rel.downloadURL != "" {
		t.Errorf("downloadURL = %q, want empty", rel.downloadURL)
	}

	blocker := s.applyBlocker(DeploymentSystemd, rel)
	if !strings.Contains(blocker, version.Platform()) {
		t.Errorf("blocker should name the missing platform, got %q", blocker)
	}
}

func TestFetchManifestReleaseRejectsEmptyVersion(t *testing.T) {
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"version":"  "}`))
	}))
	defer srv.Close()

	s := newTestService(t, config.UpdateConfig{Source: "custom", CustomURL: srv.URL}, srv)
	if _, err := s.fetchManifestRelease(context.Background(), srv.URL); err == nil {
		t.Fatal("expected an error for a manifest with no version")
	}
}

func TestGetJSONRefusesPlainHTTP(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"version":"9.9.9"}`))
	}))
	defer srv.Close()

	s := newTestService(t, config.UpdateConfig{Source: "custom", CustomURL: srv.URL}, srv)
	err := s.getJSON(context.Background(), srv.URL+"/version.json", &ReleaseManifest{})
	if err == nil {
		t.Fatal("expected plain http to be refused")
	}
	if !strings.Contains(err.Error(), "https") {
		t.Errorf("error should mention https, got %v", err)
	}
}

func TestFetchGitHubReleasePicksAssetAndSignature(t *testing.T) {
	asset := serverAssetName()
	body := map[string]any{
		"tag_name":     "v9.9.9",
		"body":         "changelog text",
		"published_at": "2026-08-11T00:00:00Z",
		"assets": []map[string]string{
			{"name": "some-other-file.tar.gz", "browser_download_url": "https://example.test/other"},
			{"name": asset, "browser_download_url": "https://example.test/" + asset},
			{"name": asset + ".sig", "browser_download_url": "https://example.test/" + asset + ".sig"},
		},
	}
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(body)
	}))
	defer srv.Close()

	s := newTestService(t, config.UpdateConfig{Source: "github"}, srv)
	// fetchGitHubRelease builds an api.github.com URL, so exercise the parsing
	// path directly against the test server.
	var gh githubRelease
	if err := s.getJSON(context.Background(), srv.URL, &gh); err != nil {
		t.Fatalf("getJSON: %v", err)
	}
	if gh.TagName != "v9.9.9" || len(gh.Assets) != 3 {
		t.Fatalf("unexpected release payload: %+v", gh)
	}

	var download, sig string
	for _, a := range gh.Assets {
		switch a.Name {
		case asset:
			download = a.BrowserDownloadURL
		case asset + ".sig":
			sig = a.BrowserDownloadURL
		}
	}
	if download == "" || sig == "" {
		t.Errorf("asset matching failed for %q: download=%q sig=%q", asset, download, sig)
	}
}

func TestServerAssetNameMatchesPlatform(t *testing.T) {
	name := serverAssetName()
	if !strings.HasPrefix(name, serverBinaryName+"-") {
		t.Errorf("asset name %q lacks the %q stem", name, serverBinaryName)
	}
	if !strings.Contains(name, version.Platform()) {
		t.Errorf("asset name %q does not contain platform %q", name, version.Platform())
	}
	if runtime.GOOS == "windows" && !strings.HasSuffix(name, ".exe") {
		t.Errorf("windows asset name %q should end in .exe", name)
	}
}

func TestApplyBlockerPerDeploymentMode(t *testing.T) {
	rel := &release{
		version:     "9.9.9",
		downloadURL: "https://example.test/nanolink-server",
		signature:   "aa",
	}
	signed := config.UpdateConfig{RequireSignature: true, PublicKey: "bb"}

	t.Run("docker is check-only", func(t *testing.T) {
		s := newTestService(t, signed, nil)
		blocker := s.applyBlocker(DeploymentDocker, rel)
		if blocker == "" {
			t.Fatal("docker should always be blocked from self-update")
		}
		if !strings.Contains(blocker, "recreate") {
			t.Errorf("docker blocker should point at image recreate, got %q", blocker)
		}
	})

	t.Run("systemd is allowed", func(t *testing.T) {
		s := newTestService(t, signed, nil)
		if blocker := s.applyBlocker(DeploymentSystemd, rel); blocker != "" {
			t.Errorf("systemd should be allowed, got %q", blocker)
		}
	})

	t.Run("bare without restart command is blocked", func(t *testing.T) {
		s := newTestService(t, signed, nil)
		if blocker := s.applyBlocker(DeploymentBare, rel); blocker == "" {
			t.Error("bare deployment with no supervisor should be blocked")
		}
	})

	t.Run("bare with restart command is allowed", func(t *testing.T) {
		cfg := signed
		cfg.RestartCommand = "systemctl restart nanoops-server"
		s := newTestService(t, cfg, nil)
		if blocker := s.applyBlocker(DeploymentBare, rel); blocker != "" {
			t.Errorf("bare deployment with a restart command should be allowed, got %q", blocker)
		}
	})
}

func TestApplyBlockerRequiresVerifiableBinary(t *testing.T) {
	rel := &release{version: "9.9.9", downloadURL: "https://example.test/bin", signature: "aa"}

	t.Run("missing public key", func(t *testing.T) {
		s := newTestService(t, config.UpdateConfig{RequireSignature: true}, nil)
		blocker := s.applyBlocker(DeploymentSystemd, rel)
		if !strings.Contains(blocker, "public_key") {
			t.Errorf("blocker should name the missing key, got %q", blocker)
		}
	})

	t.Run("release publishes no signature", func(t *testing.T) {
		unsigned := &release{version: "9.9.9", downloadURL: "https://example.test/bin"}
		s := newTestService(t, config.UpdateConfig{RequireSignature: true, PublicKey: "bb"}, nil)
		if blocker := s.applyBlocker(DeploymentSystemd, unsigned); blocker == "" {
			t.Error("an unsigned release must be refused when signatures are required")
		}
	})

	t.Run("minVersion gate", func(t *testing.T) {
		gated := &release{
			version:     "9.9.9",
			downloadURL: "https://example.test/bin",
			signature:   "aa",
			minVersion:  "99.0.0",
		}
		s := newTestService(t, config.UpdateConfig{RequireSignature: true, PublicKey: "bb"}, nil)
		blocker := s.applyBlocker(DeploymentSystemd, gated)
		if !strings.Contains(blocker, "99.0.0") {
			t.Errorf("blocker should name the required version, got %q", blocker)
		}
	})
}

func TestBuildCheckPrereleaseGating(t *testing.T) {
	rel := &release{version: "99.0.0-rc.1", downloadURL: "https://example.test/bin", signature: "aa"}

	s := newTestService(t, config.UpdateConfig{Source: "github", AllowPrerelease: false}, nil)
	if got := s.buildCheck(rel); got.UpdateAvailable {
		t.Error("a prerelease must not be offered when allow_prerelease is off")
	}

	s = newTestService(t, config.UpdateConfig{Source: "github", AllowPrerelease: true}, nil)
	if got := s.buildCheck(rel); !got.UpdateAvailable {
		t.Error("a newer prerelease should be offered when allow_prerelease is on")
	}
}

func TestBuildCheckSameVersionIsNotAnUpdate(t *testing.T) {
	rel := &release{version: version.Version, downloadURL: "https://example.test/bin"}
	s := newTestService(t, config.UpdateConfig{Source: "github"}, nil)
	got := s.buildCheck(rel)
	if got.UpdateAvailable {
		t.Errorf("current version %q must not report an available update", version.Version)
	}
	if got.CurrentVersion != version.Version {
		t.Errorf("CurrentVersion = %q, want %q", got.CurrentVersion, version.Version)
	}
	if got.CheckedAt == "" || got.DeploymentMode == "" {
		t.Errorf("check result is missing metadata: %+v", got)
	}
}

func TestVerifyEd25519(t *testing.T) {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	payload := []byte("pretend this is a server binary")
	sig := ed25519.Sign(priv, payload)

	t.Run("accepts a valid signature", func(t *testing.T) {
		if err := verifyEd25519(payload, hex.EncodeToString(pub), hex.EncodeToString(sig)); err != nil {
			t.Errorf("valid signature rejected: %v", err)
		}
	})

	t.Run("rejects tampered payload", func(t *testing.T) {
		tampered := append([]byte{}, payload...)
		tampered[0] ^= 0xff
		if err := verifyEd25519(tampered, hex.EncodeToString(pub), hex.EncodeToString(sig)); err == nil {
			t.Error("a modified binary must not verify")
		}
	})

	t.Run("rejects a signature from another key", func(t *testing.T) {
		_, otherPriv, _ := ed25519.GenerateKey(rand.Reader)
		otherSig := ed25519.Sign(otherPriv, payload)
		if err := verifyEd25519(payload, hex.EncodeToString(pub), hex.EncodeToString(otherSig)); err == nil {
			t.Error("a signature from an unpinned key must not verify")
		}
	})

	t.Run("rejects malformed inputs", func(t *testing.T) {
		cases := []struct{ name, key, sig string }{
			{"empty key", "", hex.EncodeToString(sig)},
			{"empty signature", hex.EncodeToString(pub), ""},
			{"non-hex key", "zzzz", hex.EncodeToString(sig)},
			{"short key", hex.EncodeToString(pub[:16]), hex.EncodeToString(sig)},
			{"short signature", hex.EncodeToString(pub), hex.EncodeToString(sig[:32])},
		}
		for _, tc := range cases {
			if err := verifyEd25519(payload, tc.key, tc.sig); err == nil {
				t.Errorf("%s: expected rejection", tc.name)
			}
		}
	})
}

func TestFetchSignatureHandlesEmptyFile(t *testing.T) {
	// A published .sig containing only whitespace must be an error, not a panic.
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("   \n"))
	}))
	defer srv.Close()

	s := newTestService(t, config.UpdateConfig{}, srv)
	if _, err := s.fetchSignature(context.Background(), srv.URL+"/bin.sig"); err == nil {
		t.Fatal("expected an error for an empty signature file")
	}
}

func TestFetchSignatureTakesFirstField(t *testing.T) {
	// Signature files are often "<hex>  <filename>", as produced by sha256sum-style tooling.
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("abc123  nanolink-server-linux-x86_64\n"))
	}))
	defer srv.Close()

	s := newTestService(t, config.UpdateConfig{}, srv)
	got, err := s.fetchSignature(context.Background(), srv.URL+"/bin.sig")
	if err != nil {
		t.Fatalf("fetchSignature: %v", err)
	}
	if got != "abc123" {
		t.Errorf("signature = %q, want abc123", got)
	}
}

func TestSwapBinaryReplacesTargetAndKeepsBackup(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "nanolink-server")
	staged := target + ".update"

	if err := os.WriteFile(target, []byte("old binary"), 0o755); err != nil {
		t.Fatalf("seed target: %v", err)
	}
	if err := os.WriteFile(staged, []byte("new binary"), 0o755); err != nil {
		t.Fatalf("seed staged: %v", err)
	}

	if err := swapBinary(staged, target); err != nil {
		t.Fatalf("swapBinary: %v", err)
	}

	got, err := os.ReadFile(target)
	if err != nil {
		t.Fatalf("read target: %v", err)
	}
	if string(got) != "new binary" {
		t.Errorf("target content = %q, want %q", got, "new binary")
	}
	if _, err := os.Stat(staged); !os.IsNotExist(err) {
		t.Errorf("staged file should be consumed by the swap, stat err = %v", err)
	}

	// The rollback copy is what an operator restores if the new build misbehaves.
	backup, err := os.ReadFile(target + ".bak")
	if err != nil {
		t.Fatalf("read backup: %v", err)
	}
	if string(backup) != "old binary" {
		t.Errorf("backup content = %q, want %q", backup, "old binary")
	}
}

func TestDetectDeploymentModeReturnsKnownValue(t *testing.T) {
	switch mode := DetectDeploymentMode(); mode {
	case DeploymentDocker, DeploymentSystemd, DeploymentBare:
	default:
		t.Errorf("unexpected deployment mode %q", mode)
	}
}

func TestDisabledSourceIsNotEnabled(t *testing.T) {
	for _, source := range []string{"disabled", ""} {
		s := newTestService(t, config.UpdateConfig{Source: source}, nil)
		if s.Enabled() {
			t.Errorf("source %q should not be enabled", source)
		}
		if _, err := s.Check(context.Background(), true); err == nil {
			t.Errorf("source %q: Check should refuse", source)
		}
	}
}
