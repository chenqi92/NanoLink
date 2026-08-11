package service

import (
	"context"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/version"
)

// DeploymentMode is how this server process is being supervised. It decides
// whether a self-update can work at all.
type DeploymentMode string

const (
	// DeploymentDocker means the process runs inside a container, where
	// replacing the binary is discarded on the next container recreate.
	DeploymentDocker DeploymentMode = "docker"
	// DeploymentSystemd means a systemd unit supervises the process and will
	// bring it back up after it exits.
	DeploymentSystemd DeploymentMode = "systemd"
	// DeploymentBare means no supervisor was detected.
	DeploymentBare DeploymentMode = "bare"
)

// DetectDeploymentMode inspects the runtime for container and systemd markers.
func DetectDeploymentMode() DeploymentMode {
	if inContainer() {
		return DeploymentDocker
	}
	// systemd sets INVOCATION_ID for every unit it starts (v232+).
	if os.Getenv("INVOCATION_ID") != "" {
		return DeploymentSystemd
	}
	return DeploymentBare
}

func inContainer() bool {
	for _, marker := range []string{"/.dockerenv", "/run/.containerenv"} {
		if _, err := os.Stat(marker); err == nil {
			return true
		}
	}
	// Kubernetes injects this into every pod.
	return os.Getenv("KUBERNETES_SERVICE_HOST") != ""
}

// ApplyResult describes a completed binary swap.
type ApplyResult struct {
	FromVersion string `json:"fromVersion"`
	ToVersion   string `json:"toVersion"`
	// Restarting is true when the server will bring itself back up; false means
	// the operator must restart it.
	Restarting bool   `json:"restarting"`
	Message    string `json:"message"`
}

// Apply downloads the latest release, verifies it, and replaces the running
// binary. It does not restart the server; call ScheduleRestart after the HTTP
// response has been written.
//
// expectVersion, when non-empty, must match the version actually found upstream.
// It closes the window where a release is published between the operator's check
// and their click, so what gets installed is always what they approved.
//
// The integrity gate is a detached Ed25519 signature over the downloaded bytes,
// verified against the operator-configured update.public_key. That key is the
// only thing an attacker who controls the release origin cannot forge, which is
// why a checksum is treated as a corruption check and never as authorisation.
func (s *SelfUpdateService) Apply(ctx context.Context, expectVersion string) (*ApplyResult, error) {
	if !s.applying.CompareAndSwap(false, true) {
		return nil, errors.New("an update is already being applied")
	}
	defer s.applying.Store(false)

	if !s.Enabled() {
		return nil, errors.New("version checking is disabled (update.source=disabled)")
	}

	rel, err := s.fetchRelease(ctx)
	if err != nil {
		return nil, err
	}
	if want := strings.TrimPrefix(strings.TrimSpace(expectVersion), "v"); want != "" && want != rel.version {
		return nil, fmt.Errorf("upstream now offers %s, not the %s you approved; re-check before applying", rel.version, want)
	}
	if !version.IsNewer(rel.version, version.Version) {
		return nil, fmt.Errorf("already running the latest version (%s)", version.Version)
	}
	mode := DetectDeploymentMode()
	if blocker := s.applyBlocker(mode, rel); blocker != "" {
		return nil, errors.New(blocker)
	}

	target, err := os.Executable()
	if err != nil {
		return nil, fmt.Errorf("locate the running binary: %w", err)
	}
	if target, err = filepath.EvalSymlinks(target); err != nil {
		return nil, fmt.Errorf("resolve the running binary path: %w", err)
	}

	s.logger.Infof("[AUDIT] Applying server update %s -> %s from %s", version.Version, rel.version, rel.downloadURL)

	// Stage into the target's own directory so the final rename is atomic
	// (same filesystem) rather than a copy with a torn-write window.
	staged := target + ".update"
	if err := s.downloadTo(ctx, rel.downloadURL, staged); err != nil {
		os.Remove(staged)
		return nil, err
	}
	defer os.Remove(staged)

	if err := s.verifyStaged(ctx, staged, rel); err != nil {
		s.logger.Warnf("[AUDIT] Server update rejected: %v", err)
		return nil, err
	}
	// Refuse to install a binary that cannot even report its own version: this
	// catches a truncated or architecture-mismatched artifact before it becomes
	// the live binary.
	if err := smokeTest(staged, rel.version); err != nil {
		return nil, err
	}
	if err := swapBinary(staged, target); err != nil {
		return nil, err
	}

	s.logger.Infof("[AUDIT] Server binary replaced: %s -> %s", version.Version, rel.version)

	restarting := mode == DeploymentSystemd || s.cfg.RestartCommand != ""
	msg := "Update applied. Restart the server to run the new version."
	if restarting {
		msg = "Update applied. The server is restarting now."
	}
	return &ApplyResult{
		FromVersion: version.Version,
		ToVersion:   rel.version,
		Restarting:  restarting,
		Message:     msg,
	}, nil
}

// downloadTo streams url into dest, refusing non-https origins and stopping at
// maxBinaryBytes so a hostile response cannot fill the disk.
func (s *SelfUpdateService) downloadTo(ctx context.Context, url, dest string) error {
	if !strings.HasPrefix(strings.ToLower(url), "https://") {
		return errors.New("refusing to download an update over a non-https URL")
	}
	ctx, cancel := context.WithTimeout(ctx, downloadTimeout)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "NanoOps-Server/"+version.Version)

	client := &http.Client{Timeout: downloadTimeout}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("download update: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("download update: upstream returned HTTP %d", resp.StatusCode)
	}

	f, err := os.OpenFile(dest, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o755)
	if err != nil {
		return fmt.Errorf("create staging file: %w", err)
	}
	written, copyErr := io.Copy(f, io.LimitReader(resp.Body, maxBinaryBytes+1))
	closeErr := f.Close()
	if copyErr != nil {
		return fmt.Errorf("write update: %w", copyErr)
	}
	if closeErr != nil {
		return fmt.Errorf("flush update: %w", closeErr)
	}
	if written > maxBinaryBytes {
		return fmt.Errorf("update exceeds the %d byte limit", int64(maxBinaryBytes))
	}
	if written == 0 {
		return errors.New("upstream returned an empty update")
	}
	return nil
}

// verifyStaged enforces the signature (and, when published, the checksum) over
// the staged bytes.
func (s *SelfUpdateService) verifyStaged(ctx context.Context, staged string, rel *release) error {
	data, err := os.ReadFile(staged)
	if err != nil {
		return fmt.Errorf("read staged update: %w", err)
	}

	if rel.checksum != "" {
		sum := sha256.Sum256(data)
		if !strings.EqualFold(hex.EncodeToString(sum[:]), strings.TrimSpace(rel.checksum)) {
			return errors.New("checksum mismatch: the downloaded update is corrupt or was tampered with")
		}
	}

	if !s.cfg.RequireSignature && s.cfg.PublicKey == "" {
		s.logger.Warn("[SECURITY] Applying a server update without signature verification (update.require_signature=false)")
		return nil
	}

	signature := strings.TrimSpace(rel.signature)
	if signature == "" && rel.sigURL != "" {
		if signature, err = s.fetchSignature(ctx, rel.sigURL); err != nil {
			return err
		}
	}
	if signature == "" {
		return errors.New("update rejected: no signature is published for this platform")
	}
	return verifyEd25519(data, s.cfg.PublicKey, signature)
}

// fetchSignature reads a detached signature file (hex, optionally with a
// trailing filename as produced by sha256sum-style tooling).
func (s *SelfUpdateService) fetchSignature(ctx context.Context, url string) (string, error) {
	if !strings.HasPrefix(strings.ToLower(url), "https://") {
		return "", errors.New("refusing to fetch a signature over a non-https URL")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", "NanoOps-Server/"+version.Version)
	resp, err := s.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("fetch signature: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("fetch signature: upstream returned HTTP %d", resp.StatusCode)
	}
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if err != nil {
		return "", err
	}
	fields := strings.Fields(string(raw))
	if len(fields) == 0 {
		return "", errors.New("the published signature file is empty")
	}
	return fields[0], nil
}

// verifyEd25519 checks a detached hex signature against a pinned hex public key.
func verifyEd25519(data []byte, publicKeyHex, signatureHex string) error {
	key, err := hex.DecodeString(strings.TrimSpace(publicKeyHex))
	if err != nil {
		return fmt.Errorf("update.public_key is not valid hex: %w", err)
	}
	if len(key) != ed25519.PublicKeySize {
		return fmt.Errorf("update.public_key must be %d bytes, got %d", ed25519.PublicKeySize, len(key))
	}
	sig, err := hex.DecodeString(strings.TrimSpace(signatureHex))
	if err != nil {
		return fmt.Errorf("update signature is not valid hex: %w", err)
	}
	if len(sig) != ed25519.SignatureSize {
		return fmt.Errorf("update signature must be %d bytes, got %d", ed25519.SignatureSize, len(sig))
	}
	if !ed25519.Verify(ed25519.PublicKey(key), data, sig) {
		return errors.New("update rejected: signature does not match update.public_key, " +
			"so the binary is not the one the operator signed")
	}
	return nil
}

// smokeTest runs the staged binary with -version and requires it to report the
// version we expect. A truncated download or a binary built for another
// architecture fails here, while the live binary is still untouched.
func smokeTest(staged, expected string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	out, err := exec.CommandContext(ctx, staged, "-version").CombinedOutput()
	if err != nil {
		return fmt.Errorf("the downloaded binary failed to run (%w); the running server was left untouched", err)
	}
	if !strings.Contains(string(out), expected) {
		return fmt.Errorf("the downloaded binary reports %q, expected %s; the running server was left untouched",
			strings.TrimSpace(string(out)), expected)
	}
	return nil
}

// swapBinary moves staged over target, keeping a rollback copy alongside.
//
// On Unix a running binary cannot be written to (ETXTBSY) but its directory
// entry can be replaced: rename() unlinks the old inode, which the kernel keeps
// alive for this process, so the swap is atomic and the running server is
// unaffected until it restarts. Windows refuses to replace a locked image, so
// the live binary is moved aside first.
func swapBinary(staged, target string) error {
	backup := target + ".bak"
	_ = os.Remove(backup)

	if runtime.GOOS == "windows" {
		if err := os.Rename(target, backup); err != nil {
			return fmt.Errorf("move the running binary aside: %w", err)
		}
		if err := os.Rename(staged, target); err != nil {
			// Put the original back so the service can still start.
			if rbErr := os.Rename(backup, target); rbErr != nil {
				return fmt.Errorf("install update: %w (and rollback failed: %v; restore %s manually)", err, rbErr, backup)
			}
			return fmt.Errorf("install update: %w (rolled back)", err)
		}
		return nil
	}

	// Keep a copy for rollback, then replace the directory entry atomically.
	if data, err := os.ReadFile(target); err == nil {
		if err := os.WriteFile(backup, data, 0o755); err != nil {
			return fmt.Errorf("write rollback copy: %w", err)
		}
	}
	if err := os.Rename(staged, target); err != nil {
		return fmt.Errorf("install update: %w", err)
	}
	if err := os.Chmod(target, 0o755); err != nil {
		return fmt.Errorf("set executable permissions: %w", err)
	}
	return nil
}

// ScheduleRestart brings the new binary up after the caller has written its
// HTTP response. With a supervisor (systemd Restart=always) the process simply
// exits; otherwise the configured restart_command is run.
func (s *SelfUpdateService) ScheduleRestart(delay time.Duration) {
	go func() {
		time.Sleep(delay)
		if cmd := strings.TrimSpace(s.cfg.RestartCommand); cmd != "" {
			s.logger.Infof("[AUDIT] Running update restart_command: %s", cmd)
			if err := runRestartCommand(cmd); err != nil {
				s.logger.Errorf("restart_command failed: %v", err)
				return
			}
			return
		}
		s.logger.Info("[AUDIT] Exiting so the supervisor starts the updated binary")
		os.Exit(0)
	}()
}

// runRestartCommand executes the operator-supplied restart command. It is read
// from config (not from any request), so it is intentionally run through the
// platform shell to allow the usual `systemctl restart ...` style one-liners.
func runRestartCommand(command string) error {
	var cmd *exec.Cmd
	if runtime.GOOS == "windows" {
		cmd = exec.Command("cmd", "/C", command)
	} else {
		cmd = exec.Command("sh", "-c", command)
	}
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%w: %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}
