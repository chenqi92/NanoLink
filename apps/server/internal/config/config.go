package config

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"log"
	"os"
	"strconv"
	"strings"
	"unicode"

	"github.com/spf13/viper"
)

// Config holds all configuration
type Config struct {
	Server     ServerConfig     `mapstructure:"server"`
	Auth       AuthConfig       `mapstructure:"auth"`
	Storage    StorageConfig    `mapstructure:"storage"`
	Metrics    MetricsConfig    `mapstructure:"metrics"`
	Database   DatabaseConfig   `mapstructure:"database"`
	TimeSeries TimeSeriesConfig `mapstructure:"timeseries"`
	JWT        JWTConfig        `mapstructure:"jwt"`
	SuperAdmin SuperAdminConfig `mapstructure:"superadmin"`
	MCP        MCPConfig        `mapstructure:"mcp"`
	LLM        LLMConfig        `mapstructure:"llm"`
	Deployment DeploymentConfig `mapstructure:"deployment"`
	Build      BuildConfig      `mapstructure:"build"`
	Update     UpdateConfig     `mapstructure:"update"`
}

// ServerConfig holds server configuration
type ServerConfig struct {
	HTTPPort            int      `mapstructure:"http_port"`
	WSPort              int      `mapstructure:"ws_port"`
	GRPCPort            int      `mapstructure:"grpc_port"`
	Mode                string   `mapstructure:"mode"`
	TLSCert             string   `mapstructure:"tls_cert"`
	TLSKey              string   `mapstructure:"tls_key"`
	GRPCClientCA        string   `mapstructure:"grpc_client_ca"`  // Optional CA bundle; when set gRPC requires a verified client certificate
	AllowedOrigins      []string `mapstructure:"allowed_origins"` // CORS whitelist for WebSocket connections
	ExternalURL         string   `mapstructure:"external_url"`    // External URL for device pairing QR codes (e.g., https://myserver.com:8080)
	TrustedProxies      []string `mapstructure:"trusted_proxies"` // Exact proxy IPs/CIDRs allowed to supply forwarding headers
	MaxRequestBodyBytes int64    `mapstructure:"max_request_body_bytes"`
}

// AuthConfig holds authentication configuration
type AuthConfig struct {
	Enabled bool          `mapstructure:"enabled"`
	Tokens  []TokenConfig `mapstructure:"tokens"`
	// AllowPublicRegistration opens the unauthenticated /api/auth/register
	// endpoint. The first account bootstraps the super admin; later accounts are
	// regular users. It is disabled by default so a freshly exposed server
	// cannot be hijacked by whoever registers first;
	// bootstrap the admin via NANOLINK_ADMIN_USERNAME/PASSWORD instead, or set
	// NANOLINK_ALLOW_PUBLIC_REGISTRATION=true to opt in.
	AllowPublicRegistration bool `mapstructure:"allow_public_registration"`
}

// TokenConfig holds token configuration
type TokenConfig struct {
	Token      string `mapstructure:"token"`
	Permission int    `mapstructure:"permission"`
	Name       string `mapstructure:"name"`
}

// StorageConfig holds storage configuration
type StorageConfig struct {
	Type     string `mapstructure:"type"`
	Path     string `mapstructure:"path"`
	Host     string `mapstructure:"host"`
	Port     int    `mapstructure:"port"`
	Database string `mapstructure:"database"`
	Username string `mapstructure:"username"`
	Password string `mapstructure:"password"`
}

// MetricsConfig holds metrics configuration
type MetricsConfig struct {
	RetentionDays       int    `mapstructure:"retention_days"`        // Raw data retention (default 7 days)
	HourlyRetentionDays int    `mapstructure:"hourly_retention_days"` // Hourly data retention (default 30 days)
	DailyRetentionDays  int    `mapstructure:"daily_retention_days"`  // Daily data retention (default 365 days)
	MaxAgents           int    `mapstructure:"max_agents"`
	PersistToDB         bool   `mapstructure:"persist_to_db"`      // Enable DB persistence (default true)
	MaxMemoryHistory    int    `mapstructure:"max_memory_history"` // Max entries in memory per agent (default 600)
	PrometheusEnabled   bool   `mapstructure:"prometheus_enabled"`
	PrometheusToken     string `mapstructure:"prometheus_token"`
}

// DatabaseConfig holds database configuration
type DatabaseConfig struct {
	Type     string `mapstructure:"type"`     // "sqlite" or "postgres"
	Path     string `mapstructure:"path"`     // SQLite file path
	Host     string `mapstructure:"host"`     // PostgreSQL host
	Port     int    `mapstructure:"port"`     // PostgreSQL port
	Database string `mapstructure:"database"` // PostgreSQL database name
	Username string `mapstructure:"username"` // PostgreSQL username
	Password string `mapstructure:"password"` // PostgreSQL password
	SSLMode  string `mapstructure:"sslmode"`  // PostgreSQL TLS mode
}

// TimeSeriesConfig holds time-series storage configuration
type TimeSeriesConfig struct {
	Type          string `mapstructure:"type"`     // "memory", "influxdb", "timescaledb"
	URL           string `mapstructure:"url"`      // Connection URL
	Token         string `mapstructure:"token"`    // InfluxDB token
	Org           string `mapstructure:"org"`      // InfluxDB organization
	Bucket        string `mapstructure:"bucket"`   // InfluxDB bucket
	Database      string `mapstructure:"database"` // TimescaleDB database name
	Username      string `mapstructure:"username"`
	Password      string `mapstructure:"password"`
	RetentionDays int    `mapstructure:"retention_days"` // Data retention (0 = unlimited)
	MaxEntries    int    `mapstructure:"max_entries"`    // Max entries per agent (memory)
}

// JWTConfig holds JWT configuration
type JWTConfig struct {
	Secret     string `mapstructure:"secret"`
	ExpireHour int    `mapstructure:"expire_hour"` // Token expiration in hours
}

// SuperAdminConfig holds super admin configuration
type SuperAdminConfig struct {
	Username string `mapstructure:"username"` // From NANOLINK_ADMIN_USERNAME
	Password string `mapstructure:"password"` // From NANOLINK_ADMIN_PASSWORD
}

// MCPConfig holds MCP (Model Context Protocol) configuration
type MCPConfig struct {
	Enabled        bool   `mapstructure:"enabled"`          // Enable MCP server
	Transport      string `mapstructure:"transport"`        // "stdio" or "sse"
	SSEPort        int    `mapstructure:"sse_port"`         // Port for SSE transport
	SSEBindAddress string `mapstructure:"sse_bind_address"` // Loopback by default
	SSEAuthToken   string `mapstructure:"sse_auth_token"`   // Bearer token required by SSE transport
}

// LLMConfig holds the external LLM settings backing the AI assistant chat.
// APIKey is normally supplied via the NANOLINK_LLM_API_KEY environment variable
// rather than the config file so the secret is not persisted to disk.
type LLMConfig struct {
	Enabled   bool   `mapstructure:"enabled"`    // Enable AI assistant chat
	Provider  string `mapstructure:"provider"`   // "anthropic" | "openai" | "openai-compatible"
	Model     string `mapstructure:"model"`      // Model name, e.g. claude-opus-4-8 or gpt-4o
	BaseURL   string `mapstructure:"base_url"`   // Override API base URL (optional)
	APIKey    string `mapstructure:"api_key"`    // Prefer NANOLINK_LLM_API_KEY env instead
	MaxTokens int    `mapstructure:"max_tokens"` // Max response tokens (default 1024)
}

// DeploymentConfig controls server-side artifact storage. Artifacts are never
// embedded into JSON/gRPC command messages; agents download them through a
// short-lived task token instead.
type DeploymentConfig struct {
	StoragePath      string `mapstructure:"storage_path"`
	MaxArtifactBytes int64  `mapstructure:"max_artifact_bytes"`
	DownloadTTLMin   int    `mapstructure:"download_ttl_minutes"`
}

// BuildConfig controls the control-plane source/artifact cache. Project code is
// never executed by the server process; it is dispatched to an opted-in agent.
type BuildConfig struct {
	StoragePath        string   `mapstructure:"storage_path"`
	AllowedSourceHosts []string `mapstructure:"allowed_source_hosts"`
	MaxSourceBytes     int64    `mapstructure:"max_source_bytes"`
	MaxArtifactBytes   int64    `mapstructure:"max_artifact_bytes"`
	DownloadTTLMin     int      `mapstructure:"download_ttl_minutes"`
	FetchTimeoutSec    int      `mapstructure:"fetch_timeout_seconds"`
	MaxLogBytes        int      `mapstructure:"max_log_bytes"`
}

// UpdateConfig controls server version checking and self-update. The source
// enum intentionally mirrors the agent's UpdateSource (agent/src/config.rs) so
// operators configure both sides the same way.
//
// Applying an update replaces the running server binary, so PublicKey is the
// integrity root: a detached Ed25519 signature over the downloaded binary is
// required unless RequireSignature is explicitly turned off. A checksum alone
// proves nothing when the same origin serves both the binary and the checksum.
type UpdateConfig struct {
	Source            string `mapstructure:"source"`     // "github" | "custom" | "disabled"
	Repo              string `mapstructure:"repo"`       // owner/name, used when source=github
	CustomURL         string `mapstructure:"custom_url"` // Base URL serving version.json, used when source=custom
	AutoCheck         bool   `mapstructure:"auto_check"` // Periodically refresh the cached check result
	CheckIntervalHour int    `mapstructure:"check_interval_hours"`
	AllowPrerelease   bool   `mapstructure:"allow_prerelease"`
	PublicKey         string `mapstructure:"public_key"`        // Ed25519 verify key, hex (32 bytes)
	RequireSignature  bool   `mapstructure:"require_signature"` // Default true; refuses unsigned binaries
	// RestartCommand overrides how the server restarts after a successful
	// binary swap. Empty means: rely on the supervisor (systemd Restart=always).
	RestartCommand string `mapstructure:"restart_command"`
}

// Default returns default configuration
func Default() *Config {
	return &Config{
		Server: ServerConfig{
			HTTPPort:            8080,
			WSPort:              9100,
			GRPCPort:            39100,
			Mode:                "release",
			MaxRequestBodyBytes: 1024 * 1024,
		},
		Auth: AuthConfig{
			Enabled: false,
			Tokens:  []TokenConfig{},
		},
		Storage: StorageConfig{
			Type: "memory",
			Path: "./data/nanolink.db",
		},
		Metrics: MetricsConfig{
			RetentionDays:       7,
			HourlyRetentionDays: 30,
			DailyRetentionDays:  365,
			MaxAgents:           100,
			PersistToDB:         true,
			MaxMemoryHistory:    600,
		},
		Database: DatabaseConfig{
			Type:    "sqlite",
			Path:    "./data/nanolink.db",
			Port:    5432,
			SSLMode: "disable",
		},
		TimeSeries: TimeSeriesConfig{
			Type:          "memory",
			RetentionDays: 7,
			MaxEntries:    600,
		},
		JWT: JWTConfig{
			Secret:     "",
			ExpireHour: 24,
		},
		SuperAdmin: SuperAdminConfig{},
		MCP: MCPConfig{
			Enabled:        false,
			Transport:      "stdio",
			SSEPort:        8081,
			SSEBindAddress: "127.0.0.1",
		},
		LLM: LLMConfig{
			Enabled:   false,
			Provider:  "anthropic",
			Model:     "claude-opus-4-8",
			MaxTokens: 1024,
		},
		Deployment: DeploymentConfig{
			StoragePath:      "./data/artifacts",
			MaxArtifactBytes: 512 * 1024 * 1024,
			DownloadTTLMin:   30,
		},
		Build: BuildConfig{
			StoragePath:      "./data/builds",
			MaxSourceBytes:   512 * 1024 * 1024,
			MaxArtifactBytes: 512 * 1024 * 1024,
			DownloadTTLMin:   60,
			FetchTimeoutSec:  300,
			MaxLogBytes:      2 * 1024 * 1024,
		},
		Update: UpdateConfig{
			Source:            "github",
			Repo:              "chenqi92/NanoLink",
			AutoCheck:         true,
			CheckIntervalHour: 24,
			RequireSignature:  true,
		},
	}
}

// Load loads configuration from file
func Load(path string) (*Config, error) {
	viper.SetConfigFile(path)
	viper.SetConfigType("yaml")

	// Set defaults
	viper.SetDefault("server.http_port", 8080)
	viper.SetDefault("server.ws_port", 9100)
	viper.SetDefault("server.grpc_port", 39100)
	viper.SetDefault("server.mode", "release")
	viper.SetDefault("server.max_request_body_bytes", 1024*1024)
	viper.SetDefault("auth.enabled", false)
	viper.SetDefault("auth.allow_public_registration", false)
	viper.SetDefault("storage.type", "memory")
	viper.SetDefault("storage.path", "./data/nanolink.db")
	viper.SetDefault("metrics.retention_days", 7)
	viper.SetDefault("metrics.hourly_retention_days", 30)
	viper.SetDefault("metrics.daily_retention_days", 365)
	viper.SetDefault("metrics.max_agents", 100)
	viper.SetDefault("metrics.persist_to_db", true)
	viper.SetDefault("metrics.max_memory_history", 600)
	viper.SetDefault("metrics.prometheus_enabled", false)
	viper.SetDefault("database.port", 5432)
	viper.SetDefault("database.sslmode", "disable")
	viper.SetDefault("mcp.sse_bind_address", "127.0.0.1")
	viper.SetDefault("llm.enabled", false)
	viper.SetDefault("llm.provider", "anthropic")
	viper.SetDefault("llm.model", "claude-opus-4-8")
	viper.SetDefault("llm.max_tokens", 1024)
	viper.SetDefault("deployment.storage_path", "./data/artifacts")
	viper.SetDefault("deployment.max_artifact_bytes", int64(512*1024*1024))
	viper.SetDefault("deployment.download_ttl_minutes", 30)
	viper.SetDefault("build.storage_path", "./data/builds")
	viper.SetDefault("build.max_source_bytes", int64(512*1024*1024))
	viper.SetDefault("build.max_artifact_bytes", int64(512*1024*1024))
	viper.SetDefault("build.download_ttl_minutes", 60)
	viper.SetDefault("build.fetch_timeout_seconds", 300)
	viper.SetDefault("build.max_log_bytes", 2*1024*1024)
	viper.SetDefault("update.source", "github")
	viper.SetDefault("update.repo", "chenqi92/NanoLink")
	viper.SetDefault("update.auto_check", true)
	viper.SetDefault("update.check_interval_hours", 24)
	viper.SetDefault("update.allow_prerelease", false)
	viper.SetDefault("update.require_signature", true)

	// Environment variable support
	viper.SetEnvPrefix("NANOLINK")
	viper.AutomaticEnv()

	// Bind environment variables for new auth system
	_ = viper.BindEnv("database.type", "NANOLINK_DATABASE_TYPE")
	_ = viper.BindEnv("database.path", "NANOLINK_DATABASE_PATH")
	_ = viper.BindEnv("database.host", "NANOLINK_DATABASE_HOST")
	_ = viper.BindEnv("database.port", "NANOLINK_DATABASE_PORT")
	_ = viper.BindEnv("database.database", "NANOLINK_DATABASE_NAME")
	_ = viper.BindEnv("database.username", "NANOLINK_DATABASE_USERNAME")
	_ = viper.BindEnv("database.password", "NANOLINK_DATABASE_PASSWORD")
	_ = viper.BindEnv("database.sslmode", "NANOLINK_DATABASE_SSLMODE")
	_ = viper.BindEnv("jwt.secret", "NANOLINK_JWT_SECRET")
	_ = viper.BindEnv("jwt.expire_hour", "NANOLINK_JWT_EXPIRE_HOUR")
	_ = viper.BindEnv("superadmin.username", "NANOLINK_ADMIN_USERNAME")
	_ = viper.BindEnv("superadmin.password", "NANOLINK_ADMIN_PASSWORD")
	_ = viper.BindEnv("server.http_port", "NANOLINK_SERVER_HTTP_PORT")
	_ = viper.BindEnv("server.ws_port", "NANOLINK_SERVER_WS_PORT")
	_ = viper.BindEnv("server.grpc_port", "NANOLINK_SERVER_GRPC_PORT")
	_ = viper.BindEnv("server.external_url", "NANOLINK_EXTERNAL_URL")
	_ = viper.BindEnv("server.tls_cert", "NANOLINK_TLS_CERT")
	_ = viper.BindEnv("server.tls_key", "NANOLINK_TLS_KEY")
	_ = viper.BindEnv("server.grpc_client_ca", "NANOLINK_GRPC_CLIENT_CA")
	_ = viper.BindEnv("server.trusted_proxies", "NANOLINK_TRUSTED_PROXIES")
	_ = viper.BindEnv("server.max_request_body_bytes", "NANOLINK_MAX_REQUEST_BODY_BYTES")
	_ = viper.BindEnv("auth.allow_public_registration", "NANOLINK_ALLOW_PUBLIC_REGISTRATION")
	_ = viper.BindEnv("metrics.prometheus_enabled", "NANOLINK_PROMETHEUS_ENABLED")
	_ = viper.BindEnv("metrics.prometheus_token", "NANOLINK_PROMETHEUS_TOKEN")
	_ = viper.BindEnv("mcp.sse_bind_address", "NANOLINK_MCP_SSE_BIND_ADDRESS")
	_ = viper.BindEnv("mcp.sse_auth_token", "NANOLINK_MCP_SSE_AUTH_TOKEN")
	_ = viper.BindEnv("llm.enabled", "NANOLINK_LLM_ENABLED")
	_ = viper.BindEnv("llm.provider", "NANOLINK_LLM_PROVIDER")
	_ = viper.BindEnv("llm.model", "NANOLINK_LLM_MODEL")
	_ = viper.BindEnv("llm.base_url", "NANOLINK_LLM_BASE_URL")
	_ = viper.BindEnv("llm.api_key", "NANOLINK_LLM_API_KEY")
	_ = viper.BindEnv("llm.max_tokens", "NANOLINK_LLM_MAX_TOKENS")
	_ = viper.BindEnv("deployment.storage_path", "NANOLINK_DEPLOYMENT_STORAGE_PATH")
	_ = viper.BindEnv("deployment.max_artifact_bytes", "NANOLINK_DEPLOYMENT_MAX_ARTIFACT_BYTES")
	_ = viper.BindEnv("deployment.download_ttl_minutes", "NANOLINK_DEPLOYMENT_DOWNLOAD_TTL_MINUTES")
	_ = viper.BindEnv("build.storage_path", "NANOLINK_BUILD_STORAGE_PATH")
	_ = viper.BindEnv("build.allowed_source_hosts", "NANOLINK_BUILD_ALLOWED_SOURCE_HOSTS")
	_ = viper.BindEnv("build.max_source_bytes", "NANOLINK_BUILD_MAX_SOURCE_BYTES")
	_ = viper.BindEnv("build.max_artifact_bytes", "NANOLINK_BUILD_MAX_ARTIFACT_BYTES")
	_ = viper.BindEnv("build.download_ttl_minutes", "NANOLINK_BUILD_DOWNLOAD_TTL_MINUTES")
	_ = viper.BindEnv("build.fetch_timeout_seconds", "NANOLINK_BUILD_FETCH_TIMEOUT_SECONDS")
	_ = viper.BindEnv("build.max_log_bytes", "NANOLINK_BUILD_MAX_LOG_BYTES")
	_ = viper.BindEnv("update.source", "NANOLINK_UPDATE_SOURCE")
	_ = viper.BindEnv("update.repo", "NANOLINK_UPDATE_REPO")
	_ = viper.BindEnv("update.custom_url", "NANOLINK_UPDATE_CUSTOM_URL")
	_ = viper.BindEnv("update.auto_check", "NANOLINK_UPDATE_AUTO_CHECK")
	_ = viper.BindEnv("update.check_interval_hours", "NANOLINK_UPDATE_CHECK_INTERVAL_HOURS")
	_ = viper.BindEnv("update.allow_prerelease", "NANOLINK_UPDATE_ALLOW_PRERELEASE")
	_ = viper.BindEnv("update.public_key", "NANOLINK_UPDATE_PUBLIC_KEY")
	_ = viper.BindEnv("update.require_signature", "NANOLINK_UPDATE_REQUIRE_SIGNATURE")
	_ = viper.BindEnv("update.restart_command", "NANOLINK_UPDATE_RESTART_COMMAND")

	// Try to read config file (optional - environment variables take precedence)
	configErr := viper.ReadInConfig()

	// Always unmarshal to pick up environment variables and defaults
	var cfg Config
	if err := viper.Unmarshal(&cfg); err != nil {
		return Default(), err
	}

	// Manually override with environment variables (viper's nested struct handling is unreliable)
	if username := os.Getenv("NANOLINK_ADMIN_USERNAME"); username != "" {
		cfg.SuperAdmin.Username = username
	}
	if password := os.Getenv("NANOLINK_ADMIN_PASSWORD"); password != "" {
		cfg.SuperAdmin.Password = password
	}
	if jwtSecret := os.Getenv("NANOLINK_JWT_SECRET"); jwtSecret != "" {
		cfg.JWT.Secret = jwtSecret
	}
	if dbPath := os.Getenv("NANOLINK_DATABASE_PATH"); dbPath != "" {
		cfg.Database.Path = dbPath
	}
	if dbType := os.Getenv("NANOLINK_DATABASE_TYPE"); dbType != "" {
		cfg.Database.Type = dbType
	}
	if dbHost := os.Getenv("NANOLINK_DATABASE_HOST"); dbHost != "" {
		cfg.Database.Host = dbHost
	}
	if raw := os.Getenv("NANOLINK_DATABASE_PORT"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 && n <= 65535 {
			cfg.Database.Port = n
		}
	}
	if dbName := os.Getenv("NANOLINK_DATABASE_NAME"); dbName != "" {
		cfg.Database.Database = dbName
	}
	if dbUsername := os.Getenv("NANOLINK_DATABASE_USERNAME"); dbUsername != "" {
		cfg.Database.Username = dbUsername
	}
	if dbPassword := os.Getenv("NANOLINK_DATABASE_PASSWORD"); dbPassword != "" {
		cfg.Database.Password = dbPassword
	}
	if dbSSLMode := os.Getenv("NANOLINK_DATABASE_SSLMODE"); dbSSLMode != "" {
		cfg.Database.SSLMode = dbSSLMode
	}
	if raw := os.Getenv("NANOLINK_SERVER_HTTP_PORT"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 && n <= 65535 {
			cfg.Server.HTTPPort = n
		}
	}
	if raw := os.Getenv("NANOLINK_SERVER_WS_PORT"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 && n <= 65535 {
			cfg.Server.WSPort = n
		}
	}
	if raw := os.Getenv("NANOLINK_SERVER_GRPC_PORT"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 && n <= 65535 {
			cfg.Server.GRPCPort = n
		}
	}
	if externalURL := os.Getenv("NANOLINK_EXTERNAL_URL"); externalURL != "" {
		cfg.Server.ExternalURL = externalURL
	}
	if tlsCert := os.Getenv("NANOLINK_TLS_CERT"); tlsCert != "" {
		cfg.Server.TLSCert = tlsCert
	}
	if tlsKey := os.Getenv("NANOLINK_TLS_KEY"); tlsKey != "" {
		cfg.Server.TLSKey = tlsKey
	}
	if clientCA := os.Getenv("NANOLINK_GRPC_CLIENT_CA"); clientCA != "" {
		cfg.Server.GRPCClientCA = clientCA
	}
	if proxies := os.Getenv("NANOLINK_TRUSTED_PROXIES"); proxies != "" {
		cfg.Server.TrustedProxies = splitAndTrim(proxies)
	}
	if raw := os.Getenv("NANOLINK_MAX_REQUEST_BODY_BYTES"); raw != "" {
		if n, err := strconv.ParseInt(raw, 10, 64); err == nil {
			cfg.Server.MaxRequestBodyBytes = n
		}
	}
	if v := os.Getenv("NANOLINK_ALLOW_PUBLIC_REGISTRATION"); v != "" {
		switch strings.ToLower(strings.TrimSpace(v)) {
		case "1", "true", "yes", "on":
			cfg.Auth.AllowPublicRegistration = true
		default:
			cfg.Auth.AllowPublicRegistration = false
		}
	}
	if v := os.Getenv("NANOLINK_LLM_ENABLED"); v != "" {
		cfg.LLM.Enabled = isTruthy(v)
	}
	if v := os.Getenv("NANOLINK_LLM_PROVIDER"); v != "" {
		cfg.LLM.Provider = v
	}
	if v := os.Getenv("NANOLINK_LLM_MODEL"); v != "" {
		cfg.LLM.Model = v
	}
	if v := os.Getenv("NANOLINK_LLM_BASE_URL"); v != "" {
		cfg.LLM.BaseURL = v
	}
	if v := os.Getenv("NANOLINK_LLM_API_KEY"); v != "" {
		cfg.LLM.APIKey = v
	}
	if raw := os.Getenv("NANOLINK_LLM_MAX_TOKENS"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil {
			cfg.LLM.MaxTokens = n
		}
	}
	if storagePath := os.Getenv("NANOLINK_DEPLOYMENT_STORAGE_PATH"); storagePath != "" {
		cfg.Deployment.StoragePath = storagePath
	}
	if raw := os.Getenv("NANOLINK_DEPLOYMENT_MAX_ARTIFACT_BYTES"); raw != "" {
		if n, err := strconv.ParseInt(raw, 10, 64); err == nil {
			cfg.Deployment.MaxArtifactBytes = n
		}
	}
	if raw := os.Getenv("NANOLINK_DEPLOYMENT_DOWNLOAD_TTL_MINUTES"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil {
			cfg.Deployment.DownloadTTLMin = n
		}
	}
	if v := os.Getenv("NANOLINK_BUILD_STORAGE_PATH"); v != "" {
		cfg.Build.StoragePath = v
	}
	if v := os.Getenv("NANOLINK_BUILD_ALLOWED_SOURCE_HOSTS"); v != "" {
		cfg.Build.AllowedSourceHosts = splitAndTrim(v)
	}
	if raw := os.Getenv("NANOLINK_BUILD_MAX_SOURCE_BYTES"); raw != "" {
		if n, err := strconv.ParseInt(raw, 10, 64); err == nil {
			cfg.Build.MaxSourceBytes = n
		}
	}
	if raw := os.Getenv("NANOLINK_BUILD_MAX_ARTIFACT_BYTES"); raw != "" {
		if n, err := strconv.ParseInt(raw, 10, 64); err == nil {
			cfg.Build.MaxArtifactBytes = n
		}
	}
	if raw := os.Getenv("NANOLINK_BUILD_DOWNLOAD_TTL_MINUTES"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil {
			cfg.Build.DownloadTTLMin = n
		}
	}
	if raw := os.Getenv("NANOLINK_BUILD_FETCH_TIMEOUT_SECONDS"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil {
			cfg.Build.FetchTimeoutSec = n
		}
	}
	if raw := os.Getenv("NANOLINK_BUILD_MAX_LOG_BYTES"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil {
			cfg.Build.MaxLogBytes = n
		}
	}
	if v := os.Getenv("NANOLINK_UPDATE_SOURCE"); v != "" {
		cfg.Update.Source = v
	}
	if v := os.Getenv("NANOLINK_UPDATE_REPO"); v != "" {
		cfg.Update.Repo = v
	}
	if v := os.Getenv("NANOLINK_UPDATE_CUSTOM_URL"); v != "" {
		cfg.Update.CustomURL = v
	}
	if v := os.Getenv("NANOLINK_UPDATE_PUBLIC_KEY"); v != "" {
		cfg.Update.PublicKey = v
	}
	if v := os.Getenv("NANOLINK_UPDATE_RESTART_COMMAND"); v != "" {
		cfg.Update.RestartCommand = v
	}
	if raw := os.Getenv("NANOLINK_UPDATE_CHECK_INTERVAL_HOURS"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil {
			cfg.Update.CheckIntervalHour = n
		}
	}
	if v := os.Getenv("NANOLINK_UPDATE_AUTO_CHECK"); v != "" {
		cfg.Update.AutoCheck = isTruthy(v)
	}
	if v := os.Getenv("NANOLINK_UPDATE_ALLOW_PRERELEASE"); v != "" {
		cfg.Update.AllowPrerelease = isTruthy(v)
	}
	if v := os.Getenv("NANOLINK_UPDATE_REQUIRE_SIGNATURE"); v != "" {
		cfg.Update.RequireSignature = isTruthy(v)
	}

	return &cfg, configErr
}

// ValidateAndSecure performs security validations and auto-generates missing secrets.
//
// In release mode (server.mode == "release") an unset JWT secret is fatal: a per-process
// auto-generated secret invalidates every issued token on restart and breaks signature
// verification across replicas. We require operators to set NANOLINK_JWT_SECRET (or the
// jwt.secret config key) explicitly for production. Only the development mode (debug/test)
// gets the convenience of auto-generation.
func (c *Config) ValidateAndSecure() {
	if c.JWT.Secret == "" {
		if isReleaseMode(c.Server.Mode) {
			log.Fatalf("[FATAL] JWT secret is not configured. Set NANOLINK_JWT_SECRET or jwt.secret in config (server.mode=release requires an explicit secret to keep sessions valid across restarts and replicas).")
		}
		secret := make([]byte, 32)
		if _, err := rand.Read(secret); err != nil {
			log.Fatalf("Failed to generate JWT secret: %v", err)
		}
		c.JWT.Secret = hex.EncodeToString(secret)
		log.Printf("[SECURITY WARNING] JWT secret auto-generated for development (server.mode=%q). Set NANOLINK_JWT_SECRET before deploying to production.", c.Server.Mode)
	}

	if c.Server.MaxRequestBodyBytes <= 0 {
		c.Server.MaxRequestBodyBytes = 1024 * 1024
	}
	if strings.TrimSpace(c.Deployment.StoragePath) == "" {
		c.Deployment.StoragePath = "./data/artifacts"
	}
	if c.Deployment.MaxArtifactBytes <= 0 {
		c.Deployment.MaxArtifactBytes = 512 * 1024 * 1024
	}
	if c.Deployment.DownloadTTLMin <= 0 {
		c.Deployment.DownloadTTLMin = 30
	}
	if strings.TrimSpace(c.Build.StoragePath) == "" {
		c.Build.StoragePath = "./data/builds"
	}
	if c.Build.MaxSourceBytes <= 0 {
		c.Build.MaxSourceBytes = 512 * 1024 * 1024
	}
	if c.Build.MaxArtifactBytes <= 0 {
		c.Build.MaxArtifactBytes = 512 * 1024 * 1024
	}
	if c.Build.DownloadTTLMin <= 0 {
		c.Build.DownloadTTLMin = 60
	}
	if c.Build.FetchTimeoutSec <= 0 {
		c.Build.FetchTimeoutSec = 300
	}
	if c.Build.MaxLogBytes <= 0 {
		c.Build.MaxLogBytes = 2 * 1024 * 1024
	}
	c.validateUpdate()

	if (c.Server.TLSCert == "") != (c.Server.TLSKey == "") {
		log.Fatalf("[FATAL] server.tls_cert and server.tls_key must be configured together")
	}
	if c.Server.GRPCClientCA != "" && (c.Server.TLSCert == "" || c.Server.TLSKey == "") {
		log.Fatalf("[FATAL] server.grpc_client_ca requires server.tls_cert and server.tls_key")
	}

	if (c.SuperAdmin.Username == "") != (c.SuperAdmin.Password == "") {
		log.Fatalf("[FATAL] NANOLINK_ADMIN_USERNAME and NANOLINK_ADMIN_PASSWORD must be configured together")
	}
	if c.SuperAdmin.Password != "" && !isStrongBootstrapPassword(c.SuperAdmin.Password) {
		log.Fatalf("[FATAL] bootstrap admin password must be at least 8 characters and contain both letters and numbers; placeholder passwords are rejected")
	}

	if isReleaseMode(c.Server.Mode) {
		if isWeakSecret(c.JWT.Secret) {
			log.Fatalf("[FATAL] JWT secret must be at least 32 bytes and must not be a known placeholder in release mode")
		}
		if c.Metrics.PrometheusEnabled && isWeakSecret(c.Metrics.PrometheusToken) {
			log.Fatalf("[FATAL] Prometheus is enabled in release mode but NANOLINK_PROMETHEUS_TOKEN is missing or weaker than 32 bytes")
		}
		if c.MCP.Enabled && strings.EqualFold(c.MCP.Transport, "sse") && isWeakSecret(c.MCP.SSEAuthToken) {
			log.Fatalf("[FATAL] MCP SSE is enabled in release mode but NANOLINK_MCP_SSE_AUTH_TOKEN is missing or weaker than 32 bytes")
		}
	}

	// Warn if auth is disabled
	if !c.Auth.Enabled {
		log.Println("[SECURITY WARNING] Static config agent-token auth is DISABLED. DB-backed agent tokens are still accepted; unauthenticated agents are rejected.")
		log.Println("[SECURITY WARNING] Set 'auth.enabled: true' only if you intentionally use legacy static tokens.")
	}

	// Reject the credentialed-wildcard CORS footgun: the dashboard's CORS layer
	// hardcodes Access-Control-Allow-Credentials: true (cookie auth needs it),
	// which the spec says must never be combined with an unbounded origin set.
	// We log loudly here and the runtime CORS check ignores "*" entries so the
	// wildcard cannot widen the exposure.
	for _, o := range c.Server.AllowedOrigins {
		if strings.TrimSpace(o) == "*" {
			log.Println("[SECURITY WARNING] server.allowed_origins contains '*'. This entry is ignored at runtime to avoid credentialed-wildcard CORS (CSRF amplification). List the exact origins (https://example.com, ...) you want to allow.")
			break
		}
	}
}

// validateUpdate normalises the update settings and refuses combinations that
// would silently disable the integrity gate on a self-update.
func (c *Config) validateUpdate() {
	u := &c.Update
	u.Source = strings.ToLower(strings.TrimSpace(u.Source))
	if u.Source == "" {
		u.Source = "github"
	}
	switch u.Source {
	case "github", "custom", "disabled":
	default:
		log.Printf("[WARNING] update.source=%q is not one of github|custom|disabled; version checking disabled.", u.Source)
		u.Source = "disabled"
	}
	if u.Source == "custom" && strings.TrimSpace(u.CustomURL) == "" {
		log.Println("[WARNING] update.source=custom requires update.custom_url; version checking disabled.")
		u.Source = "disabled"
	}
	if u.Source == "custom" && !strings.HasPrefix(strings.ToLower(u.CustomURL), "https://") {
		// Plain HTTP would let a network attacker choose which binary the server
		// is told to install. The signature check still gates the swap, but we
		// refuse to fetch the manifest over an unauthenticated channel.
		log.Printf("[WARNING] update.custom_url must use https:// (got %q); version checking disabled.", u.CustomURL)
		u.Source = "disabled"
	}
	if strings.TrimSpace(u.Repo) == "" {
		u.Repo = "chenqi92/NanoLink"
	}
	if u.CheckIntervalHour <= 0 {
		u.CheckIntervalHour = 24
	}
	u.PublicKey = strings.TrimSpace(u.PublicKey)
	if u.RequireSignature && u.PublicKey == "" {
		log.Println("[SECURITY] update.require_signature is on but update.public_key is unset: " +
			"version checking still works, but applying an update is refused until a verify key is configured.")
	}
	if !u.RequireSignature {
		log.Println("[SECURITY WARNING] update.require_signature=false: a downloaded server binary would be " +
			"applied without cryptographic verification. Configure update.public_key and sign releases instead.")
	}
}

func isTruthy(value string) bool {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "1", "true", "yes", "on":
		return true
	default:
		return false
	}
}

func splitAndTrim(value string) []string {
	parts := strings.Split(value, ",")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		if trimmed := strings.TrimSpace(part); trimmed != "" {
			out = append(out, trimmed)
		}
	}
	return out
}

func isReleaseMode(mode string) bool {
	return strings.EqualFold(strings.TrimSpace(mode), "release")
}

func isWeakSecret(secret string) bool {
	secret = strings.TrimSpace(secret)
	if len([]byte(secret)) < 32 {
		return true
	}
	lower := strings.ToLower(secret)
	for _, placeholder := range []string{
		"your-secret-key-change-me",
		"change-me",
		"changeme",
		"default-secret",
		"nanolink-secret",
	} {
		if lower == placeholder || strings.Contains(lower, placeholder) {
			return true
		}
	}
	return false
}

func isStrongBootstrapPassword(password string) bool {
	if len([]byte(password)) < 8 || strings.EqualFold(strings.TrimSpace(password), "changeme") {
		return false
	}
	var letter, number bool
	for _, r := range password {
		letter = letter || unicode.IsLetter(r)
		number = number || unicode.IsDigit(r)
	}
	return letter && number
}

// ValidateToken validates a token and returns permission level
// Uses timing-safe comparison to prevent timing attacks
func (c *Config) ValidateToken(token string) (bool, int) {
	token = strings.TrimSpace(token)
	if token == "" {
		return false, 0
	}

	if !c.Auth.Enabled {
		return false, 0
	}

	tokenBytes := []byte(token)
	for _, t := range c.Auth.Tokens {
		// Use constant-time comparison to prevent timing attacks
		if subtle.ConstantTimeCompare([]byte(t.Token), tokenBytes) == 1 {
			return true, t.Permission
		}
	}

	return false, 0
}
