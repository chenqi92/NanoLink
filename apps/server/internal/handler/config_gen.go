package handler

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net/http"
	"net/url"
	"strings"

	"github.com/chenqi92/NanoLink/apps/server/internal/config"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// ConfigGenHandler handles agent configuration generation
type ConfigGenHandler struct {
	cfg    *config.Config
	logger *zap.SugaredLogger
}

// NewConfigGenHandler creates a new configuration generator handler
func NewConfigGenHandler(cfg *config.Config, logger *zap.SugaredLogger) *ConfigGenHandler {
	return &ConfigGenHandler{
		cfg:    cfg,
		logger: logger,
	}
}

// GenerateConfigRequest represents a request to generate agent configuration
type GenerateConfigRequest struct {
	// Server URL (ws:// or wss://) - can be IP or domain
	ServerURL string `json:"serverUrl" binding:"required"`
	// Token for authentication
	Token string `json:"token"`
	// Permission level (0-3)
	Permission int `json:"permission"`
	// Enable TLS verification
	TLSVerify bool `json:"tlsVerify"`
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

// GenerateConfig generates agent configuration
func (h *ConfigGenHandler) GenerateConfig(c *gin.Context) {
	var req GenerateConfigRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate server URL - support both legacy ws:// and new host:port format
	serverURL := req.ServerURL
	host := ""
	port := 0

	if strings.HasPrefix(serverURL, "ws://") || strings.HasPrefix(serverURL, "wss://") {
		// Legacy WebSocket format - extract host and port
		parsedURL, err := url.Parse(serverURL)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid serverUrl: " + err.Error()})
			return
		}
		host = parsedURL.Hostname()
		if parsedURL.Port() != "" {
			fmt.Sscanf(parsedURL.Port(), "%d", &port)
		} else {
			port = 39102 // Default gRPC port
		}
	} else {
		// New format: host:port or just host
		if strings.Contains(serverURL, "://") {
			c.JSON(http.StatusBadRequest, gin.H{"error": "serverUrl should be host:port format, not URL"})
			return
		}
		parts := strings.Split(serverURL, ":")
		host = parts[0]
		if len(parts) > 1 {
			fmt.Sscanf(parts[1], "%d", &port)
		} else {
			port = 39102 // Default gRPC port
		}
	}

	// Build the final connection string for gRPC
	connString := fmt.Sprintf("%s:%d", host, port)

	// Generate token if not provided
	generatedToken := ""
	token := req.Token
	if token == "" {
		token = generateSecureToken(32)
		generatedToken = token
	}

	// Validate permission level
	if req.Permission < 0 || req.Permission > 3 {
		req.Permission = 0
	}

	// Generate server ID from URL
	serverID := generateServerID(req.ServerURL)

	// Generate YAML configuration (using gRPC format: host:port)
	configYAML := generateYAMLConfig(req, token, connString)

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

	// Generate commands
	unixCmd := fmt.Sprintf(
		`nanolink-agent server add --url "%s" --token "%s" --permission %d --tls-verify=%v`,
		req.ServerURL, req.Token, req.Permission, req.TLSVerify,
	)

	windowsCmd := fmt.Sprintf(
		`nanolink-agent.exe server add --url "%s" --token "%s" --permission %d --tls-verify=%v`,
		req.ServerURL, req.Token, req.Permission, req.TLSVerify,
	)

	// Alternative: using curl to agent's local API (requires api_token if configured)
	curlCmd := fmt.Sprintf(
		`curl -X POST http://localhost:9101/api/servers -H "Content-Type: application/json" -H "Authorization: Bearer <api_token>" -d '{"url":"%s","token":"%s","permission":%d,"tls_verify":%v}'`,
		req.ServerURL, req.Token, req.Permission, req.TLSVerify,
	)

	c.JSON(http.StatusOK, gin.H{
		"unixCommand":    unixCmd,
		"windowsCommand": windowsCmd,
		"curlCommand":    curlCmd,
		"serverId":       generateServerID(req.ServerURL),
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

	serverID := generateServerID(req.ServerURL)

	unixCmd := fmt.Sprintf(`nanolink-agent server remove --url "%s"`, req.ServerURL)
	windowsCmd := fmt.Sprintf(`nanolink-agent.exe server remove --url "%s"`, req.ServerURL)
	curlCmd := fmt.Sprintf(`curl -X DELETE -H "Authorization: Bearer <api_token>" "http://localhost:9101/api/servers?url=%s"`, url.QueryEscape(req.ServerURL))

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

	// Use gRPC port for agent connection
	grpcPort := h.cfg.Server.GRPCPort

	// Build gRPC connection URL (host:port format for gRPC)
	grpcURL := fmt.Sprintf("%s:%d", stripPort(host), grpcPort)

	c.JSON(http.StatusOK, gin.H{
		"wsUrl":       grpcURL, // Keep field name for backward compatibility
		"grpcUrl":     grpcURL,
		"grpcPort":    grpcPort,
		"wsPort":      h.cfg.Server.WSPort, // Deprecated, kept for compatibility
		"httpPort":    h.cfg.Server.HTTPPort,
		"host":        host,
		"authEnabled": h.cfg.Auth.Enabled,
	})
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

func generateSecureToken(length int) string {
	bytes := make([]byte, length)
	rand.Read(bytes)
	return hex.EncodeToString(bytes)
}

func generateServerID(serverURL string) string {
	// Create a short ID from the URL
	bytes := make([]byte, 4)
	rand.Read(bytes)
	return hex.EncodeToString(bytes)
}

func stripPort(host string) string {
	if idx := strings.LastIndex(host, ":"); idx != -1 {
		// Check if it's not an IPv6 address
		if !strings.Contains(host[idx:], "]") {
			return host[:idx]
		}
	}
	return host
}

func maskToken(token string) string {
	if len(token) <= 8 {
		return "****"
	}
	return token[:4] + "****" + token[len(token)-4:]
}

func generateYAMLConfig(req GenerateConfigRequest, token string, connString string) string {
	hostnameConfig := ""
	if req.Hostname != "" {
		hostnameConfig = fmt.Sprintf("  hostname: \"%s\"", req.Hostname)
	}

	shellConfig := ""
	if req.ShellEnabled {
		superToken := req.SuperToken
		if superToken == "" {
			superToken = generateSecureToken(32)
		}
		shellConfig = fmt.Sprintf(`
shell:
  enabled: true
  super_token: "%s"
  timeout_seconds: 30
  whitelist:
    - pattern: "df -h"
      description: "Show disk space"
    - pattern: "free -m"
      description: "Show memory"
  blacklist:
    - "rm -rf"
    - "mkfs"
    - "> /dev"`, superToken)
	}

	// Extract host and port from connString
	parts := strings.Split(connString, ":")
	host := parts[0]
	port := "39102"
	if len(parts) > 1 {
		port = parts[1]
	}

	return fmt.Sprintf(`# NanoLink Agent Configuration
# Generated by NanoLink Server

agent:
  heartbeat_interval: 30
  reconnect_delay: 5
  max_reconnect_delay: 300
%s

servers:
  - host: "%s"
    port: %s
    token: "%s"
    permission: %d
    tls_enabled: %v
    tls_verify: %v

collector:
  realtime_interval_ms: 1000
  enable_per_core_cpu: true

buffer:
  capacity: 600
%s

logging:
  level: info
  audit_enabled: true
`, hostnameConfig, host, port, token, req.Permission, req.TLSVerify, req.TLSVerify, shellConfig)
}

func generateUnixInstallCommand(req GenerateConfigRequest, token string, connString string) string {
	// Primary: Cloudflare R2 (China optimized)
	// Fallback: GitHub raw
	baseCmd := "curl -fsSL https://nanolink.r2.kkape.cn/install.sh | sudo bash -s --"

	params := fmt.Sprintf(` --silent --url "%s" --token "%s" --permission %d`,
		connString, token, req.Permission)

	if !req.TLSVerify {
		params += " --skip-tls-verify"
	}

	if req.Hostname != "" {
		params += fmt.Sprintf(` --hostname "%s"`, req.Hostname)
	}

	return baseCmd + params
}

func generateWindowsInstallCommand(req GenerateConfigRequest, token string, host string) string {
	baseCmd := `$params = @{
  Url = "%s"
  Token = "%s"
  Permission = %d
  TlsVerify = $%v
}
irm https://raw.githubusercontent.com/chenqi92/NanoLink/main/agent/scripts/install.ps1 | iex`

	return fmt.Sprintf(baseCmd, req.ServerURL, token, req.Permission, req.TLSVerify)
}
