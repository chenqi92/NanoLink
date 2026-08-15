package handler

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/chenqi92/NanoLink/apps/server/internal/config"
	"github.com/chenqi92/NanoLink/apps/server/internal/service"
	"github.com/chenqi92/NanoLink/apps/server/internal/version"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

const (
	defaultAgentGRPCPort  = 39100
	agentInstallScriptURL = "https://agent.download.kkape.com/newest/install.sh"
	nasPackageMaxBytes    = 1 << 20
	nasPackageCacheTTL    = 15 * time.Minute
)

// ConfigGenHandler handles agent configuration generation
type ConfigGenHandler struct {
	cfg          *config.Config
	logger       *zap.SugaredLogger
	tokenService *service.AgentTokenService
	nasClient    *http.Client
	nasMu        sync.Mutex
	nasCached    *NASPackageManifest
	nasCachedAt  time.Time
}

// NewConfigGenHandler creates a new configuration generator handler
func NewConfigGenHandler(cfg *config.Config, logger *zap.SugaredLogger, tokenServices ...*service.AgentTokenService) *ConfigGenHandler {
	h := &ConfigGenHandler{
		cfg:       cfg,
		logger:    logger,
		nasClient: &http.Client{Timeout: 10 * time.Second},
	}
	if len(tokenServices) > 0 {
		h.tokenService = tokenServices[0]
	}
	return h
}

// GenerateConfigRequest represents a request to generate agent configuration
type GenerateConfigRequest struct {
	// Server URL (ws:// or wss://) - can be IP or domain
	ServerURL string `json:"serverUrl" binding:"required"`
	// Token for authentication
	Token string `json:"token"`
	// Permission level (0-3)
	Permission int `json:"permission"`
	// Enable TLS. Certificate verification is mandatory whenever this is true.
	TLSVerify bool `json:"tlsVerify"`
	// Optional Agent-local trust and mutual-TLS file paths.
	TLSCACert     string `json:"tlsCaCert"`
	TLSServerName string `json:"tlsServerName"`
	TLSClientCert string `json:"tlsClientCert"`
	TLSClientKey  string `json:"tlsClientKey"`
	// Hostname override (optional)
	Hostname string `json:"hostname"`
	// Enable shell commands
	ShellEnabled bool `json:"shellEnabled"`
	// Super token for shell commands
	SuperToken string `json:"superToken"`
}

// GenerateConfigResponse represents the generated configuration
type GenerateConfigResponse struct {
	// YAML configuration content
	ConfigYAML string `json:"configYaml"`
	// Installation command for Linux/macOS
	InstallCommandUnix string `json:"installCommandUnix"`
	// Installation command for Windows
	InstallCommandWindows string `json:"installCommandWindows"`
	// Generated token (if not provided)
	GeneratedToken string `json:"generatedToken,omitempty"`
	// Server ID (hash of URL for identification)
	ServerID string `json:"serverId"`
}

// NASPackage describes one native NAS package published with the current Agent release.
type NASPackage struct {
	Platform    string `json:"platform"`
	Arch        string `json:"arch"`
	Filename    string `json:"filename"`
	DownloadURL string `json:"downloadUrl"`
	SHA256      string `json:"sha256,omitempty"`
}

// NASPackageManifest is the dashboard-facing package index.
type NASPackageManifest struct {
	Version    string       `json:"version"`
	ReleaseURL string       `json:"releaseUrl"`
	Packages   []NASPackage `json:"packages"`
}

// GenerateConfig generates agent configuration
func (h *ConfigGenHandler) GenerateConfig(c *gin.Context) {
	var req GenerateConfigRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Permission < 0 || req.Permission > 3 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "permission must be between 0 and 3"})
		return
	}
	req.TLSCACert = strings.TrimSpace(req.TLSCACert)
	req.TLSServerName = strings.TrimSpace(req.TLSServerName)
	req.TLSClientCert = strings.TrimSpace(req.TLSClientCert)
	req.TLSClientKey = strings.TrimSpace(req.TLSClientKey)
	if !req.TLSVerify && (req.TLSCACert != "" || req.TLSServerName != "" || req.TLSClientCert != "" || req.TLSClientKey != "") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "TLS certificate options require TLS to be enabled"})
		return
	}
	if (req.TLSClientCert == "") != (req.TLSClientKey == "") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "tlsClientCert and tlsClientKey must be configured together"})
		return
	}

	host, port, err := parseServerEndpoint(req.ServerURL, h.defaultGRPCPort())
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid serverUrl: " + err.Error()})
		return
	}
	connString := net.JoinHostPort(host, strconv.Itoa(port))

	generatedToken := ""
	token := strings.TrimSpace(req.Token)
	if token == "" {
		name := strings.TrimSpace(req.Hostname)
		if name == "" {
			name = "Generated config for " + host
		}

		if h.tokenService != nil {
			_, fullToken, err := h.tokenService.Create(name, req.Permission)
			if err != nil {
				h.logger.Errorf("Failed to create agent token for generated config: %v", err)
				c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create agent token"})
				return
			}
			token = fullToken
		} else {
			token = generateSecureToken(32)
			h.logger.Warn("Generated agent config with a non-persisted token because no token service was configured")
		}
		generatedToken = token
	} else if !h.isAcceptedAgentToken(token) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "provided token is not registered as an agent token"})
		return
	}

	if req.ShellEnabled {
		req.SuperToken = resolveShellSuperToken(req.SuperToken)
	}

	// Generate server ID from URL
	serverID := generateServerID(connString)

	// Generate YAML configuration (using gRPC format: host:port)
	configYAML := generateYAMLConfig(req, token, host, port)

	// Generate installation commands
	installUnix := generateUnixInstallCommand(req, token, connString)
	installWindows := generateWindowsInstallCommand(req, token, connString)

	c.JSON(http.StatusOK, GenerateConfigResponse{
		ConfigYAML:            configYAML,
		InstallCommandUnix:    installUnix,
		InstallCommandWindows: installWindows,
		GeneratedToken:        generatedToken,
		ServerID:              serverID,
	})
}

// AddServerRequest represents a request to add a server to existing agent
type AddServerRequest struct {
	ServerURL  string `json:"serverUrl" binding:"required"`
	Token      string `json:"token" binding:"required"`
	Permission int    `json:"permission"`
	TLSVerify  bool   `json:"tlsVerify"`
}

// GenerateAddServerCommand generates command to add a server to existing agent
func (h *ConfigGenHandler) GenerateAddServerCommand(c *gin.Context) {
	var req AddServerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Permission < 0 || req.Permission > 3 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "permission must be between 0 and 3"})
		return
	}
	if !h.isAcceptedAgentToken(req.Token) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "provided token is not registered as an agent token"})
		return
	}

	host, port, err := parseServerEndpoint(req.ServerURL, h.defaultGRPCPort())
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid serverUrl: " + err.Error()})
		return
	}
	connString := net.JoinHostPort(host, strconv.Itoa(port))
	cliHost := hostForCLI(host)

	// Generate commands
	unixCmd := fmt.Sprintf(
		`nanolink-agent server add --host %s --port %d --token %s --permission %d --tls-enabled=%t --tls-verify=%t`,
		shellQuote(cliHost), port, shellQuote(req.Token), req.Permission, req.TLSVerify, true,
	)

	windowsCmd := fmt.Sprintf(
		`nanolink-agent.exe server add --host %s --port %d --token %s --permission %d --tls-enabled=%t --tls-verify=%t`,
		windowsQuote(cliHost), port, windowsQuote(req.Token), req.Permission, req.TLSVerify, true,
	)

	payload, err := json.Marshal(gin.H{
		"host":        host,
		"port":        port,
		"token":       req.Token,
		"permission":  req.Permission,
		"tls_enabled": req.TLSVerify,
		"tls_verify":  true,
	})
	if err != nil {
		h.logger.Errorf("Failed to marshal add-server payload: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate command"})
		return
	}

	// Alternative: using curl to agent's local API (requires management_token if configured)
	curlCmd := fmt.Sprintf(
		`curl -X POST http://localhost:9101/api/servers -H %s -H %s -d %s`,
		shellQuote("Content-Type: application/json"),
		shellQuote("Authorization: Bearer <management_token>"),
		shellQuote(string(payload)),
	)

	c.JSON(http.StatusOK, gin.H{
		"unixCommand":    unixCmd,
		"windowsCommand": windowsCmd,
		"curlCommand":    curlCmd,
		"serverId":       generateServerID(connString),
	})
}

// RemoveServerRequest represents a request to remove a server
type RemoveServerRequest struct {
	ServerURL string `json:"serverUrl" binding:"required"`
}

// GenerateRemoveServerCommand generates command to remove a server
func (h *ConfigGenHandler) GenerateRemoveServerCommand(c *gin.Context) {
	var req RemoveServerRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	host, port, err := parseServerEndpoint(req.ServerURL, h.defaultGRPCPort())
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid serverUrl: " + err.Error()})
		return
	}
	connString := net.JoinHostPort(host, strconv.Itoa(port))
	serverID := generateServerID(connString)
	cliHost := hostForCLI(host)

	unixCmd := fmt.Sprintf(`nanolink-agent server remove --host %s --port %d`, shellQuote(cliHost), port)
	windowsCmd := fmt.Sprintf(`nanolink-agent.exe server remove --host %s --port %d`, windowsQuote(cliHost), port)
	query := url.Values{}
	query.Set("host", host)
	query.Set("port", strconv.Itoa(port))
	curlCmd := fmt.Sprintf(
		`curl -X DELETE -H %s %s`,
		shellQuote("Authorization: Bearer <management_token>"),
		shellQuote("http://localhost:9101/api/servers?"+query.Encode()),
	)

	c.JSON(http.StatusOK, gin.H{
		"unixCommand":    unixCmd,
		"windowsCommand": windowsCmd,
		"curlCommand":    curlCmd,
		"serverId":       serverID,
	})
}

// GetServerURLInfo returns information about the current server
func (h *ConfigGenHandler) GetServerURLInfo(c *gin.Context) {
	// Get the request host (could be IP or domain)
	host := c.Request.Host
	agentHost := stripPort(host)
	if externalURL := strings.TrimSpace(h.cfg.Server.ExternalURL); externalURL != "" {
		if parsed, err := url.Parse(externalURL); err == nil && parsed.Hostname() != "" {
			agentHost = parsed.Hostname()
		}
	}

	// Use gRPC port for agent connection
	grpcPort := h.cfg.Server.GRPCPort

	// Build gRPC connection URL (host:port format for gRPC)
	grpcURL := net.JoinHostPort(agentHost, strconv.Itoa(grpcPort))

	c.JSON(http.StatusOK, gin.H{
		"wsUrl":       grpcURL, // Keep field name for backward compatibility
		"grpcUrl":     grpcURL,
		"grpcPort":    grpcPort,
		"wsPort":      h.cfg.Server.WSPort, // Deprecated, kept for compatibility
		"httpPort":    h.cfg.Server.HTTPPort,
		"host":        host,
		"agentHost":   agentHost,
		"authEnabled": h.cfg.Auth.Enabled,
		// Read-only server configuration surfaced in the Settings screen.
		"serverName":          "NanoOps",
		"version":             version.Version,
		"externalUrl":         h.cfg.Server.ExternalURL,
		"agentReleaseUrl":     h.currentAgentReleaseURL(),
		"retentionDays":       h.cfg.Metrics.RetentionDays,
		"hourlyRetentionDays": h.cfg.Metrics.HourlyRetentionDays,
		"dailyRetentionDays":  h.cfg.Metrics.DailyRetentionDays,
		"tlsEnabled":          h.cfg.Server.TLSCert != "",
		"grpcVersion":         "1.68.1", // gRPC version
	})
}

// GetNASPackages returns native fnOS, Synology DSM and UGOS Pro packages for
// the Agent version that matches this server build.
func (h *ConfigGenHandler) GetNASPackages(c *gin.Context) {
	manifest, err := h.loadNASPackages(c.Request.Context())
	if err != nil {
		h.logger.Warnf("Failed to load NAS package manifest: %v", err)
		c.JSON(http.StatusBadGateway, gin.H{"error": "failed to load NAS package downloads"})
		return
	}
	c.JSON(http.StatusOK, manifest)
}

func (h *ConfigGenHandler) loadNASPackages(ctx context.Context) (*NASPackageManifest, error) {
	h.nasMu.Lock()
	defer h.nasMu.Unlock()
	if h.nasCached != nil && time.Since(h.nasCachedAt) < nasPackageCacheTTL {
		return h.nasCached, nil
	}

	var (
		manifest *NASPackageManifest
		err      error
	)
	if strings.EqualFold(strings.TrimSpace(h.cfg.Update.Source), "custom") && strings.TrimSpace(h.cfg.Update.CustomURL) != "" {
		manifest, err = h.fetchCustomNASPackages(ctx)
	} else {
		manifest, err = h.fetchGitHubNASPackages(ctx)
	}
	if err != nil {
		return nil, err
	}
	if err := validateNASPackageManifest(manifest); err != nil {
		return nil, err
	}
	h.nasCached = manifest
	h.nasCachedAt = time.Now()
	return manifest, nil
}

func (h *ConfigGenHandler) fetchGitHubNASPackages(ctx context.Context) (*NASPackageManifest, error) {
	repo := strings.Trim(strings.TrimSpace(h.cfg.Update.Repo), "/")
	parts := strings.Split(repo, "/")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return nil, fmt.Errorf("invalid GitHub update repo %q", repo)
	}
	tag := "v" + version.Version
	apiURL := fmt.Sprintf(
		"https://api.github.com/repos/%s/%s/releases/tags/%s",
		url.PathEscape(parts[0]),
		url.PathEscape(parts[1]),
		url.PathEscape(tag),
	)
	var release struct {
		HTMLURL string `json:"html_url"`
		Assets  []struct {
			Name               string `json:"name"`
			BrowserDownloadURL string `json:"browser_download_url"`
		} `json:"assets"`
	}
	if err := h.fetchNASJSON(ctx, apiURL, &release); err != nil {
		return nil, err
	}

	manifest := &NASPackageManifest{
		Version:    version.Version,
		ReleaseURL: release.HTMLURL,
		Packages:   make([]NASPackage, 0, 6),
	}
	if manifest.ReleaseURL == "" {
		manifest.ReleaseURL = h.currentAgentReleaseURL()
	}
	packagesByTarget := make(map[string]NASPackage, 6)
	for _, asset := range release.Assets {
		platform, arch, ok := classifyNASPackageAsset(asset.Name)
		if !ok {
			continue
		}
		pkg := NASPackage{
			Platform:    platform,
			Arch:        arch,
			Filename:    asset.Name,
			DownloadURL: asset.BrowserDownloadURL,
		}
		key := platform + "/" + arch
		if existing, found := packagesByTarget[key]; !found || pkg.Filename > existing.Filename {
			packagesByTarget[key] = pkg
		}
	}
	for _, pkg := range packagesByTarget {
		manifest.Packages = append(manifest.Packages, pkg)
	}
	sortNASPackages(manifest.Packages)
	return manifest, nil
}

func (h *ConfigGenHandler) currentAgentReleaseURL() string {
	if strings.EqualFold(strings.TrimSpace(h.cfg.Update.Source), "custom") {
		return strings.TrimRight(strings.TrimSpace(h.cfg.Update.CustomURL), "/")
	}
	repo := strings.Trim(strings.TrimSpace(h.cfg.Update.Repo), "/")
	parts := strings.Split(repo, "/")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return ""
	}
	return fmt.Sprintf("https://github.com/%s/releases/tag/v%s", repo, version.Version)
}

func (h *ConfigGenHandler) fetchCustomNASPackages(ctx context.Context) (*NASPackageManifest, error) {
	baseURL, err := url.Parse(strings.TrimRight(strings.TrimSpace(h.cfg.Update.CustomURL), "/") + "/")
	if err != nil || baseURL.Scheme != "https" || baseURL.Host == "" {
		return nil, fmt.Errorf("invalid custom update URL")
	}
	manifestURL := baseURL.ResolveReference(&url.URL{Path: "nas-packages.json"}).String()
	manifest := &NASPackageManifest{}
	if err := h.fetchNASJSON(ctx, manifestURL, manifest); err != nil {
		return nil, err
	}
	if manifest.Version == "" {
		manifest.Version = version.Version
	}
	for i := range manifest.Packages {
		packageURL, parseErr := url.Parse(strings.TrimSpace(manifest.Packages[i].DownloadURL))
		if parseErr == nil && !packageURL.IsAbs() {
			manifest.Packages[i].DownloadURL = baseURL.ResolveReference(packageURL).String()
		}
	}
	sortNASPackages(manifest.Packages)
	return manifest, nil
}

func (h *ConfigGenHandler) fetchNASJSON(ctx context.Context, sourceURL string, target any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, sourceURL, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Accept", "application/vnd.github+json, application/json")
	req.Header.Set("User-Agent", "NanoLink-Server/"+version.Version)
	resp, err := h.nasClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("package source returned HTTP %d", resp.StatusCode)
	}
	payload, err := io.ReadAll(io.LimitReader(resp.Body, nasPackageMaxBytes+1))
	if err != nil {
		return err
	}
	if len(payload) > nasPackageMaxBytes {
		return fmt.Errorf("package manifest exceeds %d bytes", nasPackageMaxBytes)
	}
	if err := json.Unmarshal(payload, target); err != nil {
		return fmt.Errorf("decode package manifest: %w", err)
	}
	return nil
}

func classifyNASPackageAsset(filename string) (platform string, arch string, ok bool) {
	name := strings.ToLower(strings.TrimSpace(filename))
	switch {
	case strings.HasSuffix(name, "_x86.fpk"):
		return "fnos", "x86_64", true
	case strings.HasSuffix(name, "_arm.fpk"):
		return "fnos", "arm64", true
	case strings.HasSuffix(name, "_x86_64.spk"):
		return "synology", "x86_64", true
	case strings.HasSuffix(name, "_armv8.spk"):
		return "synology", "arm64", true
	case strings.HasPrefix(name, "amd64_com.nanoops.nanolinkagent_") && strings.HasSuffix(name, ".upk"):
		return "ugos", "x86_64", true
	case strings.HasPrefix(name, "arm64_com.nanoops.nanolinkagent_") && strings.HasSuffix(name, ".upk"):
		return "ugos", "arm64", true
	default:
		return "", "", false
	}
}

func sortNASPackages(packages []NASPackage) {
	order := map[string]int{
		"fnos/x86_64":     0,
		"fnos/arm64":      1,
		"synology/x86_64": 2,
		"synology/arm64":  3,
		"ugos/x86_64":     4,
		"ugos/arm64":      5,
	}
	sort.Slice(packages, func(i, j int) bool {
		return order[packages[i].Platform+"/"+packages[i].Arch] < order[packages[j].Platform+"/"+packages[j].Arch]
	})
}

func validateNASPackageManifest(manifest *NASPackageManifest) error {
	if manifest == nil || len(manifest.Packages) == 0 {
		return fmt.Errorf("release contains no supported NAS packages")
	}
	if strings.TrimPrefix(strings.TrimSpace(manifest.Version), "v") != version.Version {
		return fmt.Errorf("NAS package version %q does not match server version %q", manifest.Version, version.Version)
	}
	allowed := map[string]struct{}{
		"fnos/x86_64":     {},
		"fnos/arm64":      {},
		"synology/x86_64": {},
		"synology/arm64":  {},
		"ugos/x86_64":     {},
		"ugos/arm64":      {},
	}
	seen := make(map[string]struct{}, len(manifest.Packages))
	for _, pkg := range manifest.Packages {
		key := pkg.Platform + "/" + pkg.Arch
		if _, supported := allowed[key]; !supported {
			return fmt.Errorf("unsupported NAS package %s", key)
		}
		if _, exists := seen[key]; exists {
			return fmt.Errorf("duplicate NAS package %s", key)
		}
		seen[key] = struct{}{}
		parsed, err := url.Parse(strings.TrimSpace(pkg.DownloadURL))
		if err != nil || parsed.Scheme != "https" || parsed.Host == "" {
			return fmt.Errorf("invalid download URL for %s", key)
		}
	}
	if manifest.ReleaseURL != "" {
		parsed, err := url.Parse(strings.TrimSpace(manifest.ReleaseURL))
		if err != nil || parsed.Scheme != "https" || parsed.Host == "" {
			return fmt.Errorf("invalid release URL")
		}
	}
	return nil
}

// TokenInfo represents token information for the UI
type TokenInfo struct {
	Token      string `json:"token"`
	Permission int    `json:"permission"`
	Name       string `json:"name"`
}

// ListTokens returns configured tokens (for admin UI)
func (h *ConfigGenHandler) ListTokens(c *gin.Context) {
	tokens := make([]TokenInfo, 0, len(h.cfg.Auth.Tokens))
	for _, t := range h.cfg.Auth.Tokens {
		tokens = append(tokens, TokenInfo{
			Token:      maskToken(t.Token),
			Permission: t.Permission,
			Name:       t.Name,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"authEnabled": h.cfg.Auth.Enabled,
		"tokens":      tokens,
	})
}

// GenerateToken generates a new secure token
func (h *ConfigGenHandler) GenerateToken(c *gin.Context) {
	token := generateSecureToken(32)
	c.JSON(http.StatusOK, gin.H{
		"token": token,
	})
}

// Helper functions

func (h *ConfigGenHandler) defaultGRPCPort() int {
	if h != nil && h.cfg != nil && h.cfg.Server.GRPCPort > 0 {
		return h.cfg.Server.GRPCPort
	}
	return defaultAgentGRPCPort
}

func (h *ConfigGenHandler) isAcceptedAgentToken(token string) bool {
	token = strings.TrimSpace(token)
	if token == "" {
		return false
	}

	if h.tokenService != nil {
		if agentToken, err := h.tokenService.GetByToken(token); err == nil {
			if agentToken.ExpiresAt == nil || agentToken.ExpiresAt.After(time.Now()) {
				return true
			}
			return false
		}
	}

	if h.cfg != nil {
		valid, _ := h.cfg.ValidateToken(token)
		return valid
	}
	return false
}

func resolveShellSuperToken(superToken string) string {
	superToken = strings.TrimSpace(superToken)
	if superToken != "" {
		return superToken
	}
	superToken = strings.TrimSpace(os.Getenv("NANOLINK_SHELL_SUPER_TOKEN"))
	if superToken != "" {
		return superToken
	}
	return generateSecureToken(32)
}

func parseServerEndpoint(serverURL string, defaultPort int) (string, int, error) {
	serverURL = strings.TrimSpace(serverURL)
	if serverURL == "" {
		return "", 0, fmt.Errorf("serverUrl is required")
	}
	if defaultPort <= 0 || defaultPort > 65535 {
		defaultPort = defaultAgentGRPCPort
	}

	if strings.HasPrefix(serverURL, "ws://") || strings.HasPrefix(serverURL, "wss://") {
		parsedURL, err := url.Parse(serverURL)
		if err != nil {
			return "", 0, err
		}
		host := parsedURL.Hostname()
		port := defaultPort
		if parsedURL.Port() != "" {
			parsedPort, err := parsePort(parsedURL.Port())
			if err != nil {
				return "", 0, err
			}
			port = parsedPort
		}
		return validateServerEndpoint(host, port)
	}
	if strings.Contains(serverURL, "://") {
		return "", 0, fmt.Errorf("use host:port or ws(s)://host:port format")
	}

	host := serverURL
	port := defaultPort
	if splitHost, splitPort, err := net.SplitHostPort(serverURL); err == nil {
		host = splitHost
		parsedPort, err := parsePort(splitPort)
		if err != nil {
			return "", 0, err
		}
		port = parsedPort
	} else if strings.Count(serverURL, ":") == 1 {
		splitHost, splitPort, _ := strings.Cut(serverURL, ":")
		host = splitHost
		parsedPort, err := parsePort(splitPort)
		if err != nil {
			return "", 0, err
		}
		port = parsedPort
	} else {
		host = strings.Trim(serverURL, "[]")
	}

	return validateServerEndpoint(host, port)
}

func parsePort(port string) (int, error) {
	parsedPort, err := strconv.Atoi(strings.TrimSpace(port))
	if err != nil || parsedPort <= 0 || parsedPort > 65535 {
		return 0, fmt.Errorf("port must be between 1 and 65535")
	}
	return parsedPort, nil
}

func validateServerEndpoint(host string, port int) (string, int, error) {
	host = strings.TrimSpace(strings.Trim(host, "[]"))
	if host == "" {
		return "", 0, fmt.Errorf("host is required")
	}
	if port <= 0 || port > 65535 {
		return "", 0, fmt.Errorf("port must be between 1 and 65535")
	}
	if strings.ContainsAny(host, " \t\r\n\"'`;$|&<>/\\") {
		return "", 0, fmt.Errorf("host contains invalid characters")
	}
	return host, port, nil
}

func hostForCLI(host string) string {
	if strings.Contains(host, ":") && !strings.HasPrefix(host, "[") {
		return "[" + host + "]"
	}
	return host
}

func shellQuote(value string) string {
	if value == "" {
		return "''"
	}
	return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
}

func windowsQuote(value string) string {
	if value == "" {
		return "''"
	}
	return "'" + strings.ReplaceAll(value, "'", "''") + "'"
}

func yamlString(value string) string {
	encoded, err := json.Marshal(value)
	if err != nil {
		return `""`
	}
	return string(encoded)
}

func generateSecureToken(length int) string {
	bytes := make([]byte, length)
	_, _ = rand.Read(bytes)
	return hex.EncodeToString(bytes)
}

func generateServerID(serverURL string) string {
	sum := sha256.Sum256([]byte(strings.TrimSpace(serverURL)))
	return hex.EncodeToString(sum[:4])
}

func stripPort(host string) string {
	if hostOnly, _, err := net.SplitHostPort(host); err == nil {
		return strings.Trim(hostOnly, "[]")
	}
	if strings.Count(host, ":") == 1 {
		hostOnly, _, _ := strings.Cut(host, ":")
		return hostOnly
	}
	return strings.Trim(host, "[]")
}

func maskToken(token string) string {
	if len(token) <= 8 {
		return "****"
	}
	return token[:4] + "****" + token[len(token)-4:]
}

func generateYAMLConfig(req GenerateConfigRequest, token string, host string, port int) string {
	hostnameConfig := ""
	if req.Hostname != "" {
		hostnameConfig = fmt.Sprintf("  hostname: %s", yamlString(req.Hostname))
	}

	shellConfig := ""
	if req.ShellEnabled {
		shellConfig = fmt.Sprintf(`
shell:
  enabled: true
  super_token: %s
  timeout_seconds: 30
  whitelist:
    - pattern: "df -h"
      description: "Show disk space"
    - pattern: "free -m"
      description: "Show memory"
  blacklist:
    - "rm -rf"
    - "mkfs"
    - "> /dev"`, yamlString(req.SuperToken))
	}

	tlsConfig := ""
	if req.TLSCACert != "" {
		tlsConfig += fmt.Sprintf("    tls_ca_cert: %s\n", yamlString(req.TLSCACert))
	}
	if req.TLSServerName != "" {
		tlsConfig += fmt.Sprintf("    tls_server_name: %s\n", yamlString(req.TLSServerName))
	}
	if req.TLSClientCert != "" {
		tlsConfig += fmt.Sprintf("    tls_client_cert: %s\n", yamlString(req.TLSClientCert))
	}
	if req.TLSClientKey != "" {
		tlsConfig += fmt.Sprintf("    tls_client_key: %s\n", yamlString(req.TLSClientKey))
	}

	return fmt.Sprintf(`# NanoLink Agent Configuration
# Generated by NanoLink Server

agent:
  heartbeat_interval: 30
  reconnect_delay: 5
  max_reconnect_delay: 300
%s

servers:
  - host: %s
    port: %d
    token: %s
    permission: %d
    tls_enabled: %v
    tls_verify: %v
%s

collector:
  realtime_interval_ms: 1000
  enable_per_core_cpu: true

buffer:
  capacity: 600
%s

logging:
  level: info
  audit_enabled: true
`, hostnameConfig, yamlString(host), port, yamlString(token), req.Permission, req.TLSVerify, true, tlsConfig, shellConfig)
}

func generateUnixInstallCommand(req GenerateConfigRequest, token string, connString string) string {
	// Primary: Cloudflare R2 (China optimized)
	// Fallback: GitHub raw
	baseCmd := "curl -fsSL " + agentInstallScriptURL + " | sudo bash -s --"

	params := fmt.Sprintf(` --silent --url %s --token %s --permission %d`,
		shellQuote(connString), shellQuote(token), req.Permission)

	if !req.TLSVerify {
		params += " --no-tls"
	}
	if req.TLSCACert != "" {
		params += fmt.Sprintf(` --tls-ca-cert %s`, shellQuote(req.TLSCACert))
	}
	if req.TLSServerName != "" {
		params += fmt.Sprintf(` --tls-server-name %s`, shellQuote(req.TLSServerName))
	}
	if req.TLSClientCert != "" {
		params += fmt.Sprintf(` --tls-client-cert %s`, shellQuote(req.TLSClientCert))
	}
	if req.TLSClientKey != "" {
		params += fmt.Sprintf(` --tls-client-key %s`, shellQuote(req.TLSClientKey))
	}

	if req.Hostname != "" {
		params += fmt.Sprintf(` --hostname %s`, shellQuote(req.Hostname))
	}

	if req.ShellEnabled {
		params += " --shell-enabled"
		params += fmt.Sprintf(` --shell-token %s`, shellQuote(req.SuperToken))
	}

	return baseCmd + params
}

func generateWindowsInstallCommand(req GenerateConfigRequest, token string, connString string) string {
	params := fmt.Sprintf(`-Silent -Url %s -Token %s -Permission %d`,
		windowsQuote(connString), windowsQuote(token), req.Permission)

	if !req.TLSVerify {
		params += " -NoTls"
	}
	if req.TLSCACert != "" {
		params += fmt.Sprintf(` -TlsCaCert %s`, windowsQuote(req.TLSCACert))
	}
	if req.TLSServerName != "" {
		params += fmt.Sprintf(` -TlsServerName %s`, windowsQuote(req.TLSServerName))
	}
	if req.TLSClientCert != "" {
		params += fmt.Sprintf(` -TlsClientCert %s`, windowsQuote(req.TLSClientCert))
	}
	if req.TLSClientKey != "" {
		params += fmt.Sprintf(` -TlsClientKey %s`, windowsQuote(req.TLSClientKey))
	}

	if req.Hostname != "" {
		params += fmt.Sprintf(` -Hostname %s`, windowsQuote(req.Hostname))
	}

	if req.ShellEnabled {
		params += " -ShellEnabled"
		params += fmt.Sprintf(` -ShellToken %s`, windowsQuote(req.SuperToken))
	}

	return fmt.Sprintf(`$script = Join-Path $env:TEMP 'nanolink-install.ps1'; irm https://raw.githubusercontent.com/chenqi92/NanoLink/main/agent/scripts/install.ps1 -OutFile $script; & $script %s`, params)
}
