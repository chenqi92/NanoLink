package service

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/config"
	"github.com/chenqi92/NanoLink/apps/server/internal/version"
	"go.uber.org/zap"
)

const (
	// maxManifestBytes caps a version.json / GitHub API response so a hostile
	// or broken origin cannot stream an unbounded body into memory.
	maxManifestBytes = 1 << 20 // 1 MiB
	// maxBinaryBytes caps a downloaded server binary. Generous for a Go binary
	// with an embedded dashboard, while bounding disk use on a bad response.
	maxBinaryBytes  = 200 << 20 // 200 MiB
	fetchTimeout    = 30 * time.Second
	downloadTimeout = 10 * time.Minute
	// serverBinaryName is the asset stem the release pipeline publishes.
	serverBinaryName = "nanolink-server"
)

// ReleaseManifest is the version.json contract published by the release
// pipeline and consumed when update.source=custom. Signatures are detached
// Ed25519 signatures (hex) over the exact bytes of the matching asset.
type ReleaseManifest struct {
	Version     string            `json:"version"`
	ReleaseDate string            `json:"releaseDate"`
	Changelog   string            `json:"changelog"`
	MinVersion  string            `json:"minVersion"`
	Assets      map[string]string `json:"assets"`
	Checksums   map[string]string `json:"checksums"`
	Signatures  map[string]string `json:"signatures"`
}

// release is the normalised view of an upstream release, whatever the source.
type release struct {
	version     string
	changelog   string
	releaseDate string
	downloadURL string
	sigURL      string
	signature   string
	checksum    string
	minVersion  string
}

// UpdateCheck is the result surfaced to the dashboard.
type UpdateCheck struct {
	CurrentVersion  string `json:"currentVersion"`
	LatestVersion   string `json:"latestVersion"`
	UpdateAvailable bool   `json:"updateAvailable"`
	Changelog       string `json:"changelog,omitempty"`
	ReleaseDate     string `json:"releaseDate,omitempty"`
	DownloadURL     string `json:"downloadUrl,omitempty"`
	Source          string `json:"source"`
	CheckedAt       string `json:"checkedAt"`
	// DeploymentMode is how this process is running: docker, systemd or bare.
	DeploymentMode string `json:"deploymentMode"`
	// CanSelfUpdate reports whether POST /api/version/apply can succeed here.
	CanSelfUpdate bool `json:"canSelfUpdate"`
	// Blocker explains, in one sentence, why CanSelfUpdate is false.
	Blocker string `json:"blocker,omitempty"`
	// UpgradeCommand is the copy-pasteable upgrade for deployments that cannot
	// self-update (notably Docker, where a container cannot replace its image).
	UpgradeCommand string `json:"upgradeCommand,omitempty"`
}

// SelfUpdateService checks an upstream release feed for a newer server build
// and, where the deployment allows it, applies that build after verifying a
// detached Ed25519 signature over the downloaded binary.
//
// Docker deployments are deliberately check-only: replacing the binary inside a
// container is discarded on the next container recreate, and doing it properly
// would require mounting the Docker socket, which is root-equivalent access to
// the host. Those deployments get an upgrade command instead.
type SelfUpdateService struct {
	cfg    config.UpdateConfig
	logger *zap.SugaredLogger
	client *http.Client

	mu       sync.RWMutex
	cached   *UpdateCheck
	cachedAt time.Time

	// applying guards against two concurrent binary swaps.
	applying atomic.Bool

	stop chan struct{}
	done chan struct{}
}

// NewSelfUpdateService creates the service. It never performs I/O; the first
// check happens on demand or on the first background tick.
func NewSelfUpdateService(cfg config.UpdateConfig, logger *zap.SugaredLogger) *SelfUpdateService {
	return &SelfUpdateService{
		cfg:    cfg,
		logger: logger,
		client: &http.Client{Timeout: fetchTimeout},
		stop:   make(chan struct{}),
		done:   make(chan struct{}),
	}
}

// Enabled reports whether version checking is configured.
func (s *SelfUpdateService) Enabled() bool {
	return s.cfg.Source != "disabled" && s.cfg.Source != ""
}

// Start begins periodic background checks when update.auto_check is on. The
// cached result is what the dashboard reads, so the UI never blocks on a slow
// or unreachable upstream.
func (s *SelfUpdateService) Start() {
	if !s.Enabled() || !s.cfg.AutoCheck {
		close(s.done)
		return
	}
	interval := time.Duration(s.cfg.CheckIntervalHour) * time.Hour
	go func() {
		defer close(s.done)
		// Delay the first check so startup is not blocked on network I/O.
		timer := time.NewTimer(30 * time.Second)
		defer timer.Stop()
		for {
			select {
			case <-s.stop:
				return
			case <-timer.C:
			}
			ctx, cancel := context.WithTimeout(context.Background(), fetchTimeout)
			if _, err := s.Check(ctx, true); err != nil {
				s.logger.Debugf("background update check failed: %v", err)
			}
			cancel()
			timer.Reset(interval)
		}
	}()
	s.logger.Infof("Update checking enabled (source=%s, every %dh)", s.cfg.Source, s.cfg.CheckIntervalHour)
}

// Stop halts background checking.
func (s *SelfUpdateService) Stop() {
	select {
	case <-s.stop:
	default:
		close(s.stop)
	}
	<-s.done
}

// Cached returns the last check result without performing I/O.
func (s *SelfUpdateService) Cached() (*UpdateCheck, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if s.cached == nil {
		return nil, false
	}
	snapshot := *s.cached
	return &snapshot, true
}

// Check queries the configured source. When refresh is false and a result was
// fetched within the check interval, the cached result is returned instead.
func (s *SelfUpdateService) Check(ctx context.Context, refresh bool) (*UpdateCheck, error) {
	if !s.Enabled() {
		return nil, fmt.Errorf("version checking is disabled (update.source=disabled)")
	}
	if !refresh {
		s.mu.RLock()
		fresh := s.cached != nil && time.Since(s.cachedAt) < time.Duration(s.cfg.CheckIntervalHour)*time.Hour
		snapshot := s.cached
		s.mu.RUnlock()
		if fresh {
			out := *snapshot
			return &out, nil
		}
	}

	rel, err := s.fetchRelease(ctx)
	if err != nil {
		return nil, err
	}

	result := s.buildCheck(rel)

	s.mu.Lock()
	s.cached = result
	s.cachedAt = time.Now()
	s.mu.Unlock()

	snapshot := *result
	return &snapshot, nil
}

// buildCheck turns an upstream release into the dashboard-facing result,
// including whether this particular deployment can apply it.
func (s *SelfUpdateService) buildCheck(rel *release) *UpdateCheck {
	current := version.Version
	available := version.IsNewer(rel.version, current)
	if !s.cfg.AllowPrerelease && isPrerelease(rel.version) {
		available = false
	}

	mode := DetectDeploymentMode()
	result := &UpdateCheck{
		CurrentVersion:  current,
		LatestVersion:   rel.version,
		UpdateAvailable: available,
		Changelog:       rel.changelog,
		ReleaseDate:     rel.releaseDate,
		DownloadURL:     rel.downloadURL,
		Source:          s.cfg.Source,
		CheckedAt:       time.Now().UTC().Format(time.RFC3339),
		DeploymentMode:  string(mode),
	}

	blocker := s.applyBlocker(mode, rel)
	result.CanSelfUpdate = blocker == ""
	result.Blocker = blocker
	if mode == DeploymentDocker {
		result.UpgradeCommand = dockerUpgradeCommand(rel.version)
	}
	return result
}

// applyBlocker returns the reason POST /api/version/apply would refuse, or ""
// when a self-update is possible for this deployment and release.
func (s *SelfUpdateService) applyBlocker(mode DeploymentMode, rel *release) string {
	switch mode {
	case DeploymentDocker:
		return "container deployment: pull the new image and recreate the container instead"
	case DeploymentBare:
		if s.cfg.RestartCommand == "" {
			// The binary can be swapped, but nothing would bring the new one up.
			return "no supervisor detected: the binary can be replaced but the server must be restarted manually"
		}
	}
	if rel.downloadURL == "" {
		return fmt.Sprintf("the release publishes no asset for %s", version.Platform())
	}
	if s.cfg.RequireSignature {
		if s.cfg.PublicKey == "" {
			return "update.public_key is not configured, so the downloaded binary cannot be verified"
		}
		if rel.signature == "" && rel.sigURL == "" {
			return "the release publishes no signature for this platform"
		}
	}
	if rel.minVersion != "" && version.IsNewer(rel.minVersion, version.Version) {
		return fmt.Sprintf("this release requires at least v%s; upgrade to that first", rel.minVersion)
	}
	return ""
}

func isPrerelease(v string) bool {
	return strings.Contains(strings.TrimPrefix(v, "v"), "-")
}

func dockerUpgradeCommand(v string) string {
	return fmt.Sprintf("docker compose pull nanolink-server && docker compose up -d nanolink-server\n"+
		"# or pin the tag: ghcr.io/chenqi92/nanolink-server:%s", v)
}

// fetchRelease resolves the latest upstream release for the configured source.
func (s *SelfUpdateService) fetchRelease(ctx context.Context) (*release, error) {
	switch s.cfg.Source {
	case "github":
		return s.fetchGitHubRelease(ctx)
	case "custom":
		return s.fetchManifestRelease(ctx, strings.TrimRight(s.cfg.CustomURL, "/"))
	default:
		return nil, fmt.Errorf("unsupported update source %q", s.cfg.Source)
	}
}

type githubRelease struct {
	TagName     string `json:"tag_name"`
	Body        string `json:"body"`
	PublishedAt string `json:"published_at"`
	Prerelease  bool   `json:"prerelease"`
	Assets      []struct {
		Name               string `json:"name"`
		BrowserDownloadURL string `json:"browser_download_url"`
	} `json:"assets"`
}

// fetchGitHubRelease reads the latest GitHub release and picks the asset for
// this platform, plus its detached "<asset>.sig" sibling when published.
func (s *SelfUpdateService) fetchGitHubRelease(ctx context.Context) (*release, error) {
	url := fmt.Sprintf("https://api.github.com/repos/%s/releases/latest", s.cfg.Repo)
	var gh githubRelease
	if err := s.getJSON(ctx, url, &gh); err != nil {
		return nil, fmt.Errorf("query GitHub releases: %w", err)
	}
	if gh.TagName == "" {
		return nil, fmt.Errorf("GitHub returned a release with no tag")
	}

	want := serverAssetName()
	rel := &release{
		version:     strings.TrimPrefix(gh.TagName, "v"),
		changelog:   gh.Body,
		releaseDate: gh.PublishedAt,
	}
	for _, a := range gh.Assets {
		switch a.Name {
		case want:
			rel.downloadURL = a.BrowserDownloadURL
		case want + ".sig":
			rel.sigURL = a.BrowserDownloadURL
		}
	}
	return rel, nil
}

// fetchManifestRelease reads a version.json published at base and resolves the
// entry for this platform. Asset names in the manifest are resolved relative to
// the manifest's own base URL.
func (s *SelfUpdateService) fetchManifestRelease(ctx context.Context, base string) (*release, error) {
	var m ReleaseManifest
	if err := s.getJSON(ctx, base+"/version.json", &m); err != nil {
		return nil, fmt.Errorf("fetch version.json: %w", err)
	}
	if strings.TrimSpace(m.Version) == "" {
		return nil, fmt.Errorf("version.json has no version field")
	}

	platform := version.Platform()
	rel := &release{
		version:     strings.TrimPrefix(m.Version, "v"),
		changelog:   m.Changelog,
		releaseDate: m.ReleaseDate,
		minVersion:  strings.TrimPrefix(m.MinVersion, "v"),
		signature:   m.Signatures[platform],
		checksum:    m.Checksums[platform],
	}
	if asset := m.Assets[platform]; asset != "" {
		rel.downloadURL = base + "/" + strings.TrimLeft(asset, "/")
	}
	return rel, nil
}

// serverAssetName is the release asset this build would install.
func serverAssetName() string {
	name := serverBinaryName + "-" + version.Platform()
	if strings.HasPrefix(version.Platform(), "windows-") {
		name += ".exe"
	}
	return name
}

// getJSON performs a size-limited JSON GET. Only https origins are accepted,
// so an update feed cannot be redirected onto an unauthenticated channel.
func (s *SelfUpdateService) getJSON(ctx context.Context, url string, out any) error {
	if !strings.HasPrefix(strings.ToLower(url), "https://") {
		return fmt.Errorf("refusing to fetch update metadata over a non-https URL")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "NanoOps-Server/"+version.Version)
	req.Header.Set("Accept", "application/json")

	resp, err := s.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("upstream returned HTTP %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxManifestBytes))
	if err != nil {
		return err
	}
	return json.Unmarshal(body, out)
}
