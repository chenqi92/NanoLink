use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

/// Current config version for migration support
pub const CONFIG_VERSION: u32 = 2;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// Config file version for migration support
    #[serde(default = "default_config_version")]
    pub config_version: u32,

    /// Agent settings
    #[serde(default)]
    pub agent: AgentConfig,

    /// Server connections
    pub servers: Vec<ServerConfig>,

    /// Metrics collection settings
    #[serde(default)]
    pub collector: CollectorConfig,

    /// Ring buffer settings
    #[serde(default)]
    pub buffer: BufferConfig,

    /// Shell command settings
    #[serde(default)]
    pub shell: ShellConfig,

    /// Logging settings
    #[serde(default)]
    pub logging: LoggingConfig,

    /// Management API settings
    #[serde(default)]
    pub management: ManagementConfig,

    /// Security settings
    #[serde(default)]
    pub security: SecurityConfig,

    /// Update settings
    #[serde(default)]
    pub update: UpdateConfig,

    /// Scripts configuration
    #[serde(default)]
    pub scripts: ScriptsConfig,

    /// Config management settings
    #[serde(default)]
    pub config_management: ConfigManagementConfig,

    /// Package management settings
    #[serde(default)]
    pub package_management: PackageManagementConfig,

    /// Application deployment settings
    #[serde(default)]
    pub deployments: DeploymentsConfig,

    /// Automated build runner settings
    #[serde(default)]
    pub builds: BuildsConfig,
}

fn default_config_version() -> u32 {
    1 // Default to version 1 for old configs without version field
}

/// Update source for downloading updates
#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum UpdateSource {
    /// GitHub releases (default)
    #[default]
    Github,
    /// Cloudflare R2 mirror
    Cloudflare,
    /// Custom URL
    Custom,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateConfig {
    /// Enable automatic update check
    #[serde(default)]
    pub auto_check: bool,

    /// Update check interval in hours (default: 24)
    #[serde(default = "default_update_check_interval")]
    pub check_interval_hours: u64,

    /// GitHub repository for updates (default: chenqi92/NanoLink)
    #[serde(default = "default_update_repo")]
    pub repo: String,

    /// Allow automatic download of updates
    #[serde(default)]
    pub auto_download: bool,

    /// Allow automatic application of updates (requires auto_download)
    #[serde(default)]
    pub auto_apply: bool,

    /// Pre-release updates allowed
    #[serde(default)]
    pub allow_prerelease: bool,

    /// Update source: github, cloudflare, or custom
    #[serde(default)]
    pub source: UpdateSource,

    /// Custom update URL (used when source = "custom")
    #[serde(default)]
    pub custom_url: Option<String>,

    /// Ed25519 public key (hex, 32 bytes) used to verify the signature
    /// of a downloaded binary before it replaces the running agent. When set,
    /// applying an update REQUIRES a valid detached signature over the binary;
    /// this is the only integrity root a malicious/compromised server cannot
    /// forge (a server-supplied checksum is not, since the server supplies both
    /// the binary and the checksum).
    #[serde(default)]
    pub public_key: Option<String>,

    /// Reject updates that are not cryptographically signed. Has effect only
    /// when no public_key is configured (with a key, signatures are always
    /// required); set this to fail closed instead of falling back to a
    /// checksum-only, unverified update.
    #[serde(default = "default_true")]
    pub require_signature: bool,
}

impl Default for UpdateConfig {
    fn default() -> Self {
        Self {
            auto_check: false,
            check_interval_hours: default_update_check_interval(),
            repo: default_update_repo(),
            auto_download: false,
            auto_apply: false,
            allow_prerelease: false,
            source: UpdateSource::default(),
            custom_url: None,
            public_key: None,
            require_signature: true,
        }
    }
}

fn default_update_check_interval() -> u64 {
    24
}

fn default_update_repo() -> String {
    "chenqi92/NanoLink".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScriptsConfig {
    /// Enable script execution
    #[serde(default)]
    pub enabled: bool,

    /// Scripts directory path
    #[serde(default = "default_scripts_dir")]
    pub scripts_dir: String,

    /// Require signature verification for scripts
    #[serde(default)]
    pub require_signature: bool,

    /// Allowed script categories (empty = all allowed)
    #[serde(default)]
    pub allowed_categories: Vec<String>,

    /// Script execution timeout in seconds
    #[serde(default = "default_script_timeout")]
    pub timeout_seconds: u64,

    /// Maximum script output size in bytes
    #[serde(default = "default_max_output_size")]
    pub max_output_size: usize,
}

impl Default for ScriptsConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            scripts_dir: default_scripts_dir(),
            require_signature: false,
            allowed_categories: Vec::new(),
            timeout_seconds: default_script_timeout(),
            max_output_size: default_max_output_size(),
        }
    }
}

fn default_scripts_dir() -> String {
    #[cfg(unix)]
    return "/opt/nanolink/scripts".to_string();
    #[cfg(windows)]
    return "C:\\ProgramData\\nanolink\\scripts".to_string();
}

fn default_script_timeout() -> u64 {
    60
}

fn default_max_output_size() -> usize {
    1024 * 1024 // 1MB
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeploymentsConfig {
    /// Deployment is opt-in because it combines filesystem writes and service control.
    #[serde(default)]
    pub enabled: bool,

    /// Absolute application roots accepted from the server.
    #[serde(default = "default_deployment_roots")]
    pub allowed_roots: Vec<String>,

    /// Maximum downloaded artifact size in bytes.
    #[serde(default = "default_deployment_max_artifact_size")]
    pub max_artifact_size: u64,

    /// Maximum time allowed for the artifact download.
    #[serde(default = "default_deployment_timeout")]
    pub timeout_seconds: u64,
}

impl Default for DeploymentsConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            allowed_roots: default_deployment_roots(),
            max_artifact_size: default_deployment_max_artifact_size(),
            timeout_seconds: default_deployment_timeout(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BuildsConfig {
    /// Build execution is opt-in because pipeline stages execute project code.
    #[serde(default)]
    pub enabled: bool,

    /// Private root used for disposable workspaces and temporary downloads.
    #[serde(default = "default_build_workspace_root")]
    pub workspace_root: String,

    /// Permit commands to run directly on the host. Container execution is the
    /// safer default and remains available when this is false.
    #[serde(default)]
    pub allow_host_runner: bool,

    /// Optional allow-list for container images. Empty accepts any image name.
    #[serde(default)]
    pub allowed_images: Vec<String>,

    #[serde(default = "default_build_max_source_size")]
    pub max_source_size: u64,

    #[serde(default = "default_build_max_artifact_size")]
    pub max_artifact_size: u64,

    #[serde(default = "default_build_timeout")]
    pub timeout_seconds: u64,

    #[serde(default = "default_build_max_output_size")]
    pub max_output_size: usize,
}

impl Default for BuildsConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            workspace_root: default_build_workspace_root(),
            allow_host_runner: false,
            allowed_images: Vec::new(),
            max_source_size: default_build_max_source_size(),
            max_artifact_size: default_build_max_artifact_size(),
            timeout_seconds: default_build_timeout(),
            max_output_size: default_build_max_output_size(),
        }
    }
}

fn default_build_workspace_root() -> String {
    #[cfg(unix)]
    return "/var/lib/nanolink/builds".to_string();
    #[cfg(windows)]
    return "C:\\ProgramData\\NanoLink\\builds".to_string();
}

fn default_build_max_source_size() -> u64 {
    512 * 1024 * 1024
}

fn default_build_max_artifact_size() -> u64 {
    512 * 1024 * 1024
}

fn default_build_timeout() -> u64 {
    1800
}

fn default_build_max_output_size() -> usize {
    2 * 1024 * 1024
}

fn default_deployment_roots() -> Vec<String> {
    #[cfg(unix)]
    return vec![
        "/opt/nanolink/apps".to_string(),
        "/var/www/nanolink".to_string(),
    ];
    #[cfg(windows)]
    return vec!["C:\\ProgramData\\NanoLink\\apps".to_string()];
}

fn default_deployment_max_artifact_size() -> u64 {
    512 * 1024 * 1024
}

fn default_deployment_timeout() -> u64 {
    600
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConfigManagementConfig {
    /// Enable config management
    #[serde(default)]
    pub enabled: bool,

    /// Allowed config file paths (whitelist)
    #[serde(default)]
    pub allowed_configs: Vec<String>,

    /// Automatically backup before changes
    #[serde(default = "default_true")]
    pub backup_on_change: bool,

    /// Maximum number of backups to keep
    #[serde(default = "default_max_backups")]
    pub max_backups: u32,

    /// Backup directory
    #[serde(default = "default_backup_dir")]
    pub backup_dir: String,
}

impl Default for ConfigManagementConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            allowed_configs: Vec::new(),
            backup_on_change: true,
            max_backups: default_max_backups(),
            backup_dir: default_backup_dir(),
        }
    }
}

fn default_max_backups() -> u32 {
    10
}

fn default_backup_dir() -> String {
    #[cfg(unix)]
    return "/var/lib/nanolink/backups".to_string();
    #[cfg(windows)]
    return "C:\\ProgramData\\nanolink\\backups".to_string();
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct PackageManagementConfig {
    /// Enable package management
    #[serde(default)]
    pub enabled: bool,

    /// Allow package updates (dangerous)
    #[serde(default)]
    pub allow_update: bool,

    /// Allow system updates (very dangerous)
    #[serde(default)]
    pub allow_system_update: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ManagementConfig {
    /// Enable management API (默认禁用以提高安全性)
    #[serde(default)]
    pub enabled: bool,

    /// Port to listen on
    #[serde(default = "default_management_port")]
    pub port: u16,

    /// Bind address (默认仅localhost以限制访问)
    #[serde(default = "default_bind_address")]
    pub bind_address: String,

    /// API token for authentication (已废弃，改用 ServerConfig.management_token)
    #[serde(default)]
    pub api_token: Option<String>,

    /// Enable TLS encryption
    #[serde(default)]
    pub tls_enabled: bool,

    /// TLS certificate path
    #[serde(default)]
    pub tls_cert: Option<String>,

    /// TLS private key path
    #[serde(default)]
    pub tls_key: Option<String>,

    /// Rate limiting configuration
    #[serde(default)]
    pub rate_limit: RateLimitConfig,

    /// Audit logging configuration
    #[serde(default)]
    pub audit: AuditConfig,
}

/// Rate limiting configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RateLimitConfig {
    /// Enable rate limiting
    #[serde(default = "default_true")]
    pub enabled: bool,

    /// Default requests per minute
    #[serde(default = "default_requests_per_minute")]
    pub requests_per_minute: u32,

    /// Default burst size
    #[serde(default = "default_burst")]
    pub burst: u32,

    /// Per-endpoint rate limits (endpoint path -> config)
    #[serde(default)]
    pub endpoints: std::collections::HashMap<String, EndpointRateLimit>,
}

impl Default for RateLimitConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            requests_per_minute: default_requests_per_minute(),
            burst: default_burst(),
            endpoints: std::collections::HashMap::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EndpointRateLimit {
    pub requests_per_minute: u32,
    pub burst: u32,
}

fn default_requests_per_minute() -> u32 {
    60
}

fn default_burst() -> u32 {
    10
}

/// Audit logging configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditConfig {
    /// Enable audit logging
    #[serde(default)]
    pub enabled: bool,

    /// Maximum log file size in MB
    #[serde(default = "default_max_size_mb")]
    pub max_size_mb: u32,

    /// Maximum age of log files in days
    #[serde(default = "default_max_age_days")]
    pub max_age_days: u32,

    /// Maximum number of log files to keep
    #[serde(default = "default_max_files")]
    pub max_files: u32,
}

impl Default for AuditConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            max_size_mb: default_max_size_mb(),
            max_age_days: default_max_age_days(),
            max_files: default_max_files(),
        }
    }
}

fn default_max_size_mb() -> u32 {
    100
}

fn default_max_age_days() -> u32 {
    30
}

fn default_max_files() -> u32 {
    10
}

impl Default for ManagementConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            port: default_management_port(),
            bind_address: default_bind_address(),
            api_token: None,
            tls_enabled: false,
            tls_cert: None,
            tls_key: None,
            rate_limit: RateLimitConfig::default(),
            audit: AuditConfig::default(),
        }
    }
}

fn default_management_port() -> u16 {
    9101
}

fn default_bind_address() -> String {
    "127.0.0.1".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentConfig {
    /// Persistent agent ID (auto-generated on first run, used for data continuity)
    /// This ID is sent to the server to associate metrics with the same agent across restarts
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent_id: Option<String>,

    /// Hostname override (defaults to system hostname)
    pub hostname: Option<String>,

    /// Heartbeat interval in seconds
    #[serde(default = "default_heartbeat_interval")]
    pub heartbeat_interval: u64,

    /// Reconnect delay in seconds
    #[serde(default = "default_reconnect_delay")]
    pub reconnect_delay: u64,

    /// Maximum reconnect delay in seconds
    #[serde(default = "default_max_reconnect_delay")]
    pub max_reconnect_delay: u64,

    /// Preferred language (en/zh). If not set, auto-detect from system locale.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub language: Option<String>,

    /// Enforce a local read-only ceiling for all remote operations. Autonomous
    /// telemetry, on-demand metrics, and a small inventory-query allowlist remain
    /// available; remote writes, shell access, file/log reads, and config pushes
    /// are rejected regardless of the server token's permission level.
    #[serde(default)]
    pub remote_read_only: bool,
}

impl Default for AgentConfig {
    fn default() -> Self {
        Self {
            agent_id: None,
            hostname: None,
            heartbeat_interval: default_heartbeat_interval(),
            reconnect_delay: default_reconnect_delay(),
            max_reconnect_delay: default_max_reconnect_delay(),
            language: None,
            remote_read_only: false,
        }
    }
}

/// Default gRPC port for NanoLink
pub const DEFAULT_GRPC_PORT: u16 = 39100;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    /// Server hostname or IP address
    /// Examples: "localhost", "192.168.1.100", "monitor.example.com"
    pub host: String,

    /// gRPC port (default: 39100)
    #[serde(default = "default_grpc_port")]
    pub port: u16,

    /// Authentication token. Supports multiple formats:
    /// 1. Direct value: "my_token"
    /// 2. Environment variable reference: "${ENV_VAR_NAME}"
    /// 3. File reference: "file:///path/to/token"
    pub token: String,

    /// Management API token for this server to call Agent remotely
    /// Only valid when permission >= 1, bound to server's IP address
    #[serde(default)]
    pub management_token: Option<String>,

    /// Permission level for this connection
    /// 0 = READ_ONLY, 1 = BASIC_WRITE, 2 = SERVICE_CONTROL, 3 = SYSTEM_ADMIN
    #[serde(default)]
    pub permission: u8,

    /// Enable TLS (grpcs://)
    #[serde(default)]
    pub tls_enabled: bool,

    /// Enable TLS certificate verification
    #[serde(default = "default_true")]
    pub tls_verify: bool,

    /// Optional PEM trust bundle added to the system/web PKI roots.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tls_ca_cert: Option<String>,

    /// Optional certificate name used for SNI and hostname verification. This
    /// is useful when connecting through 127.0.0.1 or a private tunnel.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tls_server_name: Option<String>,

    /// Optional PEM client certificate chain for mutual TLS.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tls_client_cert: Option<String>,

    /// Optional PEM private key paired with tls_client_cert.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tls_client_key: Option<String>,
}

impl ServerConfig {
    /// Get the gRPC connection URL
    pub fn get_grpc_url(&self) -> String {
        if self.tls_enabled {
            format!("https://{}:{}", self.host, self.port)
        } else {
            format!("http://{}:{}", self.host, self.port)
        }
    }

    /// Validate fail-closed TLS semantics before attempting a connection.
    pub fn validate_tls_security(&self) -> Result<(), String> {
        let has_ca = self
            .tls_ca_cert
            .as_deref()
            .is_some_and(|v| !v.trim().is_empty());
        let has_name = self
            .tls_server_name
            .as_deref()
            .is_some_and(|v| !v.trim().is_empty());
        let has_client_cert = self
            .tls_client_cert
            .as_deref()
            .is_some_and(|v| !v.trim().is_empty());
        let has_client_key = self
            .tls_client_key
            .as_deref()
            .is_some_and(|v| !v.trim().is_empty());

        if !self.tls_enabled {
            if has_ca || has_name || has_client_cert || has_client_key {
                return Err("TLS certificate settings require tls_enabled=true".to_string());
            }
            return Ok(());
        }
        if !self.tls_verify {
            return Err(
                "tls_verify=false is not permitted for TLS connections; configure tls_ca_cert for a private CA"
                    .to_string(),
            );
        }
        if has_client_cert != has_client_key {
            return Err(
                "tls_client_cert and tls_client_key must be configured together".to_string(),
            );
        }
        Ok(())
    }

    /// Resolve token value, supporting environment variables and file references
    /// Returns the actual token value, or an error if resolution fails
    pub fn resolve_token(&self) -> Result<String, String> {
        let token = &self.token;

        // Environment variable format: ${VAR_NAME}
        if token.starts_with("${") && token.ends_with("}") {
            let var_name = &token[2..token.len() - 1];
            return std::env::var(var_name).map_err(|_| {
                format!(
                    "Environment variable '{var_name}' not found. \
                    Make sure it is set before starting the agent."
                )
            });
        }

        // File reference format: file:///path/to/token
        if let Some(path) = token.strip_prefix("file://") {
            return std::fs::read_to_string(path)
                .map(|s| s.trim().to_string())
                .map_err(|e| format!("Failed to read token file '{path}': {e}"));
        }

        // Direct value
        Ok(token.clone())
    }
}

fn default_grpc_port() -> u16 {
    DEFAULT_GRPC_PORT
}

// Protocol enum removed - gRPC only
// WebSocket support has been removed from Agent
// Server-side WebSocket is still available for Dashboard communication

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CollectorConfig {
    // ========== Realtime data (sent every interval) ==========
    /// Realtime metrics collection interval in milliseconds (CPU/memory/IO)
    #[serde(default = "default_realtime_interval")]
    pub realtime_interval_ms: u64,

    // ========== Periodic data (sent less frequently) ==========
    /// Disk usage collection interval in milliseconds
    #[serde(default = "default_disk_usage_interval")]
    pub disk_usage_interval_ms: u64,

    /// User sessions collection interval in milliseconds
    #[serde(default = "default_session_interval")]
    pub session_interval_ms: u64,

    /// IP address check interval in milliseconds
    #[serde(default = "default_ip_check_interval")]
    pub ip_check_interval_ms: u64,

    /// Per-core CPU usage collection interval in milliseconds
    /// Sent via periodic channel at lower frequency than realtime aggregate CPU
    #[serde(default = "default_per_core_interval")]
    pub per_core_interval_ms: u64,

    /// Disk health (S.M.A.R.T) check interval in milliseconds
    #[serde(default = "default_health_check_interval")]
    pub health_check_interval_ms: u64,

    // ========== Legacy intervals (for backwards compatibility) ==========
    /// CPU/Memory collection interval in milliseconds
    #[serde(default = "default_cpu_interval")]
    pub cpu_interval_ms: u64,

    /// Disk I/O collection interval in milliseconds
    #[serde(default = "default_disk_interval")]
    pub disk_interval_ms: u64,

    /// Network collection interval in milliseconds
    #[serde(default = "default_network_interval")]
    pub network_interval_ms: u64,

    /// Process list collection interval in milliseconds
    #[serde(default = "default_process_interval")]
    pub process_interval_ms: u64,

    /// Disk space collection interval in milliseconds
    #[serde(default = "default_disk_space_interval")]
    pub disk_space_interval_ms: u64,

    // ========== Feature flags ==========
    /// Enable disk I/O metrics
    #[serde(default = "default_true")]
    pub enable_disk_io: bool,

    /// Enable network metrics
    #[serde(default = "default_true")]
    pub enable_network: bool,

    /// Enable per-core CPU metrics
    #[serde(default = "default_true")]
    pub enable_per_core_cpu: bool,

    /// Enable layered metrics (realtime/periodic/static separation)
    #[serde(default = "default_true")]
    pub enable_layered_metrics: bool,

    /// Send full metrics on initial connection
    #[serde(default = "default_true")]
    pub send_initial_full: bool,

    // ========== Idle mode (when not connected to any server) ==========
    /// Metrics collection interval when not connected to any server (milliseconds)
    /// This reduces CPU usage when idle. Default: 30 seconds
    #[serde(default = "default_idle_interval")]
    pub idle_interval_ms: u64,
}

impl Default for CollectorConfig {
    fn default() -> Self {
        Self {
            realtime_interval_ms: default_realtime_interval(),
            disk_usage_interval_ms: default_disk_usage_interval(),
            session_interval_ms: default_session_interval(),
            ip_check_interval_ms: default_ip_check_interval(),
            per_core_interval_ms: default_per_core_interval(),
            health_check_interval_ms: default_health_check_interval(),
            cpu_interval_ms: default_cpu_interval(),
            disk_interval_ms: default_disk_interval(),
            network_interval_ms: default_network_interval(),
            process_interval_ms: default_process_interval(),
            disk_space_interval_ms: default_disk_space_interval(),
            enable_disk_io: true,
            enable_network: true,
            enable_per_core_cpu: true,
            enable_layered_metrics: true,
            send_initial_full: true,
            idle_interval_ms: default_idle_interval(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BufferConfig {
    /// Ring buffer capacity (number of metrics to cache)
    /// Default: 720 (1 hour at 5-second interval)
    #[serde(default = "default_buffer_capacity")]
    pub capacity: usize,

    /// Enable data compensation (resend buffered data after reconnection)
    /// Default: false
    #[serde(default)]
    pub data_compensation: bool,

    /// Maximum number of metrics to send in one compensation batch
    /// Default: 100
    #[serde(default = "default_compensation_batch_size")]
    pub compensation_batch_size: usize,
}

fn default_compensation_batch_size() -> usize {
    100
}

impl Default for BufferConfig {
    fn default() -> Self {
        Self {
            capacity: default_buffer_capacity(),
            data_compensation: false,
            compensation_batch_size: default_compensation_batch_size(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShellConfig {
    /// Enable shell command execution
    #[serde(default)]
    pub enabled: bool,

    /// Super token for shell command authentication
    pub super_token: Option<String>,

    /// Command execution timeout in seconds
    #[serde(default = "default_shell_timeout")]
    pub timeout_seconds: u64,

    /// Whitelisted command patterns
    #[serde(default)]
    pub whitelist: Vec<CommandPattern>,

    /// Blacklisted command patterns (always blocked)
    #[serde(default)]
    pub blacklist: Vec<String>,

    /// Commands requiring confirmation
    #[serde(default)]
    pub require_confirmation: Vec<CommandPattern>,
}

impl Default for ShellConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            super_token: None,
            timeout_seconds: default_shell_timeout(),
            whitelist: Vec::new(),
            blacklist: default_blacklist(),
            require_confirmation: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommandPattern {
    /// Command pattern (supports * wildcard)
    pub pattern: String,

    /// Description of what this command does
    #[serde(default)]
    pub description: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoggingConfig {
    /// Log level
    #[serde(default = "default_log_level")]
    pub level: String,

    /// Log file path (if not set, logs to stdout)
    pub file: Option<String>,

    /// Enable audit logging for commands
    #[serde(default = "default_true")]
    pub audit_enabled: bool,

    /// Audit log file path
    #[serde(default = "default_audit_file")]
    pub audit_file: String,
}

impl Default for LoggingConfig {
    fn default() -> Self {
        Self {
            level: default_log_level(),
            file: None,
            audit_enabled: true,
            audit_file: default_audit_file(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecurityConfig {
    /// Allowed paths for file operations (empty = all paths allowed)
    /// Paths are checked after canonicalization
    #[serde(default)]
    pub allowed_paths: Vec<String>,

    /// Denied paths (always blocked, checked before allowed_paths)
    /// Default includes sensitive system directories
    #[serde(default = "default_denied_paths")]
    pub denied_paths: Vec<String>,

    /// Enable path traversal protection (detect and block '..' in paths)
    #[serde(default = "default_true")]
    pub path_traversal_protection: bool,

    /// Maximum file size for download/upload operations (in bytes)
    #[serde(default = "default_max_file_size")]
    pub max_file_size: u64,
}

impl Default for SecurityConfig {
    fn default() -> Self {
        Self {
            allowed_paths: Vec::new(),
            denied_paths: default_denied_paths(),
            path_traversal_protection: true,
            max_file_size: default_max_file_size(),
        }
    }
}

fn default_denied_paths() -> Vec<String> {
    vec![
        "/etc/shadow".to_string(),
        "/etc/passwd".to_string(),
        "/etc/sudoers".to_string(),
        "/root/.ssh".to_string(),
        "/home/*/.ssh".to_string(),
        "/etc/ssh".to_string(),
        // Root-persistence / privilege-escalation locations: blocking these for
        // the generic file API closes the most direct drop-a-file-as-root
        // vectors even when an allowlist is configured.
        "/etc/cron.d".to_string(),
        "/etc/cron.daily".to_string(),
        "/etc/cron.hourly".to_string(),
        "/etc/cron.weekly".to_string(),
        "/etc/cron.monthly".to_string(),
        "/etc/crontab".to_string(),
        "/var/spool/cron".to_string(),
        "/etc/systemd".to_string(),
        "/usr/lib/systemd".to_string(),
        "/lib/systemd".to_string(),
        "/etc/init.d".to_string(),
        "/etc/rc.local".to_string(),
        "/etc/ld.so.preload".to_string(),
        "/etc/ld.so.conf".to_string(),
        "/etc/ld.so.conf.d".to_string(),
        "/etc/pam.d".to_string(),
        "/etc/profile".to_string(),
        "/etc/profile.d".to_string(),
        "/etc/bash.bashrc".to_string(),
        "/etc/environment".to_string(),
        "C:\\Windows\\System32\\config".to_string(),
    ]
}

fn default_max_file_size() -> u64 {
    50 * 1024 * 1024 // 50MB
}

// Default value functions
fn default_heartbeat_interval() -> u64 {
    30
}
fn default_reconnect_delay() -> u64 {
    5
}
fn default_max_reconnect_delay() -> u64 {
    300
}
fn default_cpu_interval() -> u64 {
    1000
}
fn default_disk_interval() -> u64 {
    3000
}
fn default_network_interval() -> u64 {
    1000
}
fn default_process_interval() -> u64 {
    5000
}
fn default_disk_space_interval() -> u64 {
    30000
}
fn default_realtime_interval() -> u64 {
    5000 // 5 seconds for realtime metrics (balance between responsiveness and resource usage)
}
fn default_disk_usage_interval() -> u64 {
    30000 // 30 seconds for disk usage
}
fn default_per_core_interval() -> u64 {
    30000 // 30 seconds for per-core CPU (sufficient for per-core charts)
}
fn default_session_interval() -> u64 {
    60000 // 1 minute for user sessions
}
fn default_ip_check_interval() -> u64 {
    60000 // 1 minute for IP address changes
}
fn default_health_check_interval() -> u64 {
    300000 // 5 minutes for S.M.A.R.T health
}
fn default_idle_interval() -> u64 {
    30000 // 30 seconds when not connected to any server (reduces CPU usage)
}
fn default_buffer_capacity() -> usize {
    720 // 1 hour at 5-second interval
}
fn default_shell_timeout() -> u64 {
    30
}
fn default_true() -> bool {
    true
}
fn default_log_level() -> String {
    "info".to_string()
}
fn default_audit_file() -> String {
    "nanolink-audit.log".to_string()
}

fn default_blacklist() -> Vec<String> {
    vec![
        // 破坏性命令
        "rm -rf".to_string(),
        "mkfs".to_string(),
        "> /dev".to_string(),
        "dd if=".to_string(),
        ":(){:|:&};:".to_string(), // fork bomb
        "shred".to_string(),
        "wipefs".to_string(),
        // 敏感文件操作
        "> /etc/passwd".to_string(),
        "> /etc/shadow".to_string(),
        "chmod 777 /".to_string(),
        // 远程执行/后门
        "curl |".to_string(),
        "wget |".to_string(),
        "| sh".to_string(),
        "| bash".to_string(),
        "/dev/tcp/".to_string(),
        "nc -e".to_string(),
        "nc -l".to_string(),
        // 脚本执行
        "python -c".to_string(),
        "perl -e".to_string(),
        "ruby -e".to_string(),
        "base64 -d |".to_string(),
        // 权限提升
        "sudo ".to_string(),
        " su ".to_string(),
        " su\n".to_string(),
    ]
}

impl Config {
    /// Load configuration from file
    pub fn load(path: &Path) -> Result<Self> {
        let content = std::fs::read_to_string(path)
            .with_context(|| format!("Failed to read config file: {path:?}"))?;

        let mut config: Config = if path.extension().is_some_and(|e| e == "toml") {
            toml::from_str(&content)?
        } else {
            serde_yaml::from_str(&content)?
        };

        // Migrate config if needed
        if config.config_version < CONFIG_VERSION {
            config = config.migrate()?;
            // Optionally save migrated config
            if let Err(e) = config.save(path) {
                eprintln!("Warning: Failed to save migrated config: {e}");
            }
        }

        // Generate hardware-based agent_id
        // Always use hardware-derived ID for consistency across restarts
        // The ID is derived from machine-specific identifiers (machine-id, IOPlatformUUID, etc.)
        let hardware_id = crate::hardware_id::generate_hardware_agent_id();

        // Check if we need to update the stored agent_id
        let should_update = match &config.agent.agent_id {
            None => true,
            Some(existing) => {
                // If existing ID is a UUID (old format), migrate to hardware ID
                // UUID format: 8-4-4-4-12 = 36 chars with hyphens
                existing.len() == 36 && existing.chars().filter(|c| *c == '-').count() == 4
            }
        };

        if should_update {
            let old_id = config.agent.agent_id.take();
            config.agent.agent_id = Some(hardware_id.clone());
            if let Some(old) = old_id {
                eprintln!("Migrated agent_id from UUID ({old}) to hardware-based: {hardware_id}");
            } else {
                eprintln!("Generated hardware-based agent_id: {hardware_id}");
            }
            // Save config with the new agent_id
            if let Err(e) = config.save(path) {
                eprintln!("Warning: Failed to save config with new agent_id: {e}");
            }
        }

        // Auto-disable Management API if enabled but api_token is not set
        // This ensures backward compatibility with old configs
        if config.management.enabled
            && config.management.api_token.is_none()
            && !config.agent.remote_read_only
        {
            eprintln!(
                "Warning: Management API was enabled but api_token is not set. \
                 Disabling Management API for security. \
                 To enable, add 'api_token: <your-token>' to the management section."
            );
            config.management.enabled = false;
        }

        config.validate()?;
        Ok(config)
    }

    /// Migrate config from older versions
    fn migrate(mut self) -> Result<Self> {
        let original_version = self.config_version;

        // Migration from v1 to v2: Add update config section
        if self.config_version == 1 {
            eprintln!("Migrating config from v1 to v2...");
            self.update = UpdateConfig::default();
            self.config_version = 2;
        }

        // Add future migrations here:
        // if self.config_version == 2 {
        //     // migrate v2 -> v3
        //     self.config_version = 3;
        // }

        if original_version != self.config_version {
            eprintln!(
                "Config migrated from v{} to v{}",
                original_version, self.config_version
            );
        }

        Ok(self)
    }

    /// Save configuration to file
    pub fn save(&self, path: &Path) -> Result<()> {
        let content = if path.extension().is_some_and(|e| e == "toml") {
            toml::to_string_pretty(self)?
        } else {
            serde_yaml::to_string(self)?
        };

        std::fs::write(path, content)
            .with_context(|| format!("Failed to write config file: {path:?}"))?;

        Ok(())
    }

    /// Build a least-privilege configuration for NAS packages.
    pub fn nas_read_only(
        mut server: ServerConfig,
        hostname: Option<String>,
        status_port: Option<u16>,
        status_bind: String,
    ) -> Result<Self> {
        if server.port == 0 {
            anyhow::bail!("NAS server port must be greater than zero");
        }
        server.permission = 0;
        server.management_token = None;
        server.validate_tls_security().map_err(anyhow::Error::msg)?;

        let mut management = ManagementConfig::default();
        if let Some(port) = status_port {
            if port == 0 {
                anyhow::bail!("NAS status port must be greater than zero");
            }
            management.enabled = true;
            management.port = port;
            management.bind_address = status_bind;
        }

        let mut config = Self {
            config_version: CONFIG_VERSION,
            agent: AgentConfig {
                hostname,
                remote_read_only: true,
                ..AgentConfig::default()
            },
            servers: vec![server],
            collector: CollectorConfig::default(),
            buffer: BufferConfig::default(),
            shell: ShellConfig::default(),
            logging: LoggingConfig::default(),
            management,
            security: SecurityConfig::default(),
            update: UpdateConfig::default(),
            scripts: ScriptsConfig::default(),
            config_management: ConfigManagementConfig::default(),
            package_management: PackageManagementConfig {
                enabled: true,
                allow_update: false,
                allow_system_update: false,
            },
            deployments: DeploymentsConfig::default(),
            builds: BuildsConfig::default(),
        };
        config.enforce_remote_read_only();
        config.validate()?;
        Ok(config)
    }

    /// Apply the NAS safety ceiling at runtime so editing the persisted config
    /// cannot re-enable remote mutation through a package-managed service.
    pub fn enforce_remote_read_only(&mut self) {
        self.agent.remote_read_only = true;
        for server in &mut self.servers {
            server.permission = 0;
            server.management_token = None;
        }
        self.shell = ShellConfig::default();
        self.scripts = ScriptsConfig::default();
        self.config_management = ConfigManagementConfig::default();
        self.package_management = PackageManagementConfig {
            enabled: true,
            allow_update: false,
            allow_system_update: false,
        };
        self.deployments = DeploymentsConfig::default();
        self.builds = BuildsConfig::default();
        self.update.auto_check = false;
        self.update.auto_download = false;
        self.update.auto_apply = false;
    }

    /// Generate a sample configuration
    pub fn sample() -> Self {
        Self {
            config_version: CONFIG_VERSION,
            agent: AgentConfig::default(),
            update: UpdateConfig::default(),
            servers: vec![ServerConfig {
                host: "localhost".to_string(),
                port: DEFAULT_GRPC_PORT,
                token: "your_token_here".to_string(),
                management_token: None,
                permission: 0,
                tls_enabled: false,
                tls_verify: true,
                tls_ca_cert: None,
                tls_server_name: None,
                tls_client_cert: None,
                tls_client_key: None,
            }],
            collector: CollectorConfig::default(),
            buffer: BufferConfig::default(),
            shell: ShellConfig {
                enabled: true,
                super_token: Some("super_secret_token".to_string()),
                timeout_seconds: 30,
                whitelist: vec![
                    CommandPattern {
                        pattern: "df -h".to_string(),
                        description: "Show disk space".to_string(),
                    },
                    CommandPattern {
                        pattern: "free -m".to_string(),
                        description: "Show memory usage".to_string(),
                    },
                    CommandPattern {
                        pattern: "tail -n * /var/log/*.log".to_string(),
                        description: "View log tail".to_string(),
                    },
                ],
                blacklist: default_blacklist(),
                require_confirmation: vec![
                    CommandPattern {
                        pattern: "reboot".to_string(),
                        description: "Reboot system".to_string(),
                    },
                    CommandPattern {
                        pattern: "shutdown".to_string(),
                        description: "Shutdown system".to_string(),
                    },
                ],
            },
            logging: LoggingConfig::default(),
            management: ManagementConfig::default(),
            security: SecurityConfig::default(),
            scripts: ScriptsConfig::default(),
            config_management: ConfigManagementConfig::default(),
            package_management: PackageManagementConfig::default(),
            deployments: DeploymentsConfig::default(),
            builds: BuildsConfig::default(),
        }
    }

    /// Validate configuration
    fn validate(&self) -> Result<()> {
        if self.servers.is_empty() {
            anyhow::bail!("At least one server must be configured");
        }

        for (i, server) in self.servers.iter().enumerate() {
            if server.host.is_empty() {
                anyhow::bail!("Server {i} host cannot be empty");
            }
            if server.token.is_empty() {
                anyhow::bail!("Server {i} token cannot be empty");
            }
            if server.permission > 3 {
                anyhow::bail!("Server {i} permission must be 0-3");
            }
            if let Err(error) = server.validate_tls_security() {
                anyhow::bail!("Server {i} TLS configuration is invalid: {error}");
            }
        }

        if self.shell.enabled {
            if self
                .shell
                .super_token
                .as_deref()
                .is_none_or(|token| token.trim().is_empty())
            {
                anyhow::bail!("Shell is enabled but super_token is not set");
            }
            if !(1..=3600).contains(&self.shell.timeout_seconds) {
                anyhow::bail!("Shell timeout_seconds must be between 1 and 3600");
            }
            if self.shell.whitelist.is_empty() {
                anyhow::bail!(
                    "Shell is enabled but whitelist is empty; configure explicit L3 command patterns"
                );
            }
        }

        if self.deployments.enabled {
            if self.deployments.allowed_roots.is_empty() {
                anyhow::bail!("Deployment is enabled but allowed_roots is empty");
            }
            for root in &self.deployments.allowed_roots {
                if !std::path::Path::new(root).is_absolute() {
                    anyhow::bail!("Deployment allowed root must be absolute: {root}");
                }
            }
            if self.deployments.max_artifact_size == 0 {
                anyhow::bail!("Deployment max_artifact_size must be greater than zero");
            }
            if self.deployments.timeout_seconds == 0 {
                anyhow::bail!("Deployment timeout_seconds must be greater than zero");
            }
        }

        if self.builds.enabled {
            if !std::path::Path::new(&self.builds.workspace_root).is_absolute() {
                anyhow::bail!("Build workspace_root must be absolute");
            }
            if self.builds.max_source_size == 0 || self.builds.max_artifact_size == 0 {
                anyhow::bail!("Build source and artifact limits must be greater than zero");
            }
            if self.builds.timeout_seconds == 0 || self.builds.max_output_size == 0 {
                anyhow::bail!("Build timeout and output limit must be greater than zero");
            }
        }

        // P1-2: 检查危险的通配符配置
        for pattern in &self.shell.whitelist {
            if pattern.pattern == "*" {
                tracing::warn!(
                    "[SECURITY WARNING] Shell whitelist contains '*' pattern - this allows ALL commands!"
                );
                // 除非显式允许，否则拒绝通配符
                if std::env::var("NANOLINK_ALLOW_WILDCARD").is_err() {
                    anyhow::bail!(
                        "Wildcard '*' in whitelist is not allowed for security reasons. \
                        Set NANOLINK_ALLOW_WILDCARD=1 environment variable to override."
                    );
                }
            }
        }

        // P1-3: 管理API启用时如果未设置token，则自动禁用并警告（向后兼容）
        // 不再报错退出，以支持旧版本配置文件升级
        // Note: We can't mutate self here, so we just warn. The actual disable happens in load()

        Ok(())
    }

    /// Get effective hostname
    pub fn get_hostname(&self) -> String {
        self.agent.hostname.clone().unwrap_or_else(|| {
            hostname::get()
                .ok()
                .and_then(|h| h.into_string().ok())
                .unwrap_or_else(|| "unknown".to_string())
        })
    }
}

#[cfg(test)]
mod tls_config_tests {
    use super::*;

    fn server() -> ServerConfig {
        ServerConfig {
            host: "server.example.com".to_string(),
            port: DEFAULT_GRPC_PORT,
            token: "test-token".to_string(),
            management_token: None,
            permission: 0,
            tls_enabled: true,
            tls_verify: true,
            tls_ca_cert: None,
            tls_server_name: None,
            tls_client_cert: None,
            tls_client_key: None,
        }
    }

    #[test]
    fn tls_verification_cannot_be_disabled() {
        let mut cfg = server();
        cfg.tls_verify = false;
        assert!(cfg.validate_tls_security().is_err());
    }

    #[test]
    fn mtls_identity_requires_cert_and_key() {
        let mut cfg = server();
        cfg.tls_client_cert = Some("/etc/nanolink/tls/agent.crt".to_string());
        assert!(cfg.validate_tls_security().is_err());
        cfg.tls_client_key = Some("/etc/nanolink/tls/agent.key".to_string());
        assert!(cfg.validate_tls_security().is_ok());
    }

    #[test]
    fn tls_material_is_rejected_on_plaintext_connection() {
        let mut cfg = server();
        cfg.tls_enabled = false;
        cfg.tls_ca_cert = Some("/etc/nanolink/tls/ca.crt".to_string());
        assert!(cfg.validate_tls_security().is_err());
    }

    #[test]
    fn nas_read_only_config_disables_remote_control_surfaces() {
        let mut remote_server = server();
        remote_server.permission = 3;
        remote_server.management_token = Some("management-token".to_string());

        let config = Config::nas_read_only(
            remote_server,
            Some("storage-room".to_string()),
            Some(29091),
            "0.0.0.0".to_string(),
        )
        .unwrap();

        assert!(config.agent.remote_read_only);
        assert_eq!(config.servers[0].permission, 0);
        assert!(config.servers[0].management_token.is_none());
        assert!(!config.shell.enabled);
        assert!(!config.scripts.enabled);
        assert!(!config.config_management.enabled);
        assert!(config.package_management.enabled);
        assert!(!config.package_management.allow_update);
        assert!(!config.package_management.allow_system_update);
        assert!(!config.deployments.enabled);
        assert!(!config.builds.enabled);
        assert!(!config.update.auto_check);
        assert!(!config.update.auto_download);
        assert!(!config.update.auto_apply);
        assert!(config.management.enabled);
        assert_eq!(config.management.port, 29091);
        assert_eq!(config.management.bind_address, "0.0.0.0");
    }

    #[test]
    fn nas_read_only_config_rejects_zero_server_port() {
        let mut remote_server = server();
        remote_server.port = 0;
        assert!(Config::nas_read_only(remote_server, None, None, "127.0.0.1".to_string()).is_err());
    }

    #[test]
    fn runtime_read_only_ceiling_overrides_persisted_privileges() {
        let mut config = Config::sample();
        config.agent.remote_read_only = false;
        config.servers[0].permission = 3;
        config.servers[0].management_token = Some("management-token".to_string());
        config.shell.enabled = true;
        config.scripts.enabled = true;
        config.config_management.enabled = true;
        config.package_management.allow_update = true;
        config.package_management.allow_system_update = true;
        config.deployments.enabled = true;
        config.builds.enabled = true;
        config.update.auto_check = true;
        config.update.auto_download = true;
        config.update.auto_apply = true;

        config.enforce_remote_read_only();

        assert!(config.agent.remote_read_only);
        assert_eq!(config.servers[0].permission, 0);
        assert!(config.servers[0].management_token.is_none());
        assert!(!config.shell.enabled);
        assert!(!config.scripts.enabled);
        assert!(!config.config_management.enabled);
        assert!(config.package_management.enabled);
        assert!(!config.package_management.allow_update);
        assert!(!config.package_management.allow_system_update);
        assert!(!config.deployments.enabled);
        assert!(!config.builds.enabled);
        assert!(!config.update.auto_check);
        assert!(!config.update.auto_download);
        assert!(!config.update.auto_apply);
    }
}
