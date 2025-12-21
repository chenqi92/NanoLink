use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
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
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ManagementConfig {
    /// Enable management API
    #[serde(default = "default_management_enabled")]
    pub enabled: bool,

    /// Port to listen on (localhost only)
    #[serde(default = "default_management_port")]
    pub port: u16,

    /// API token for authentication (optional)
    pub api_token: Option<String>,
}

impl Default for ManagementConfig {
    fn default() -> Self {
        Self {
            enabled: default_management_enabled(),
            port: default_management_port(),
            api_token: None,
        }
    }
}

fn default_management_enabled() -> bool {
    true
}
fn default_management_port() -> u16 {
    9101
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentConfig {
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
}

impl Default for AgentConfig {
    fn default() -> Self {
        Self {
            hostname: None,
            heartbeat_interval: default_heartbeat_interval(),
            reconnect_delay: default_reconnect_delay(),
            max_reconnect_delay: default_max_reconnect_delay(),
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

    /// Authentication token
    pub token: String,

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
}

impl Default for CollectorConfig {
    fn default() -> Self {
        Self {
            realtime_interval_ms: default_realtime_interval(),
            disk_usage_interval_ms: default_disk_usage_interval(),
            session_interval_ms: default_session_interval(),
            ip_check_interval_ms: default_ip_check_interval(),
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
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BufferConfig {
    /// Ring buffer capacity (number of metrics to cache)
    /// Default: 720 (1 hour at 5-second interval)
    #[serde(default = "default_buffer_capacity")]
    pub capacity: usize,
}

impl Default for BufferConfig {
    fn default() -> Self {
        Self {
            capacity: default_buffer_capacity(),
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
fn default_session_interval() -> u64 {
    60000 // 1 minute for user sessions
}
fn default_ip_check_interval() -> u64 {
    60000 // 1 minute for IP address changes
}
fn default_health_check_interval() -> u64 {
    300000 // 5 minutes for S.M.A.R.T health
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
        "rm -rf".to_string(),
        "mkfs".to_string(),
        "> /dev".to_string(),
        "dd if=".to_string(),
        ":(){:|:&};:".to_string(), // fork bomb
    ]
}

impl Config {
    /// Load configuration from file
    pub fn load(path: &Path) -> Result<Self> {
        let content = std::fs::read_to_string(path)
            .with_context(|| format!("Failed to read config file: {:?}", path))?;

        let config: Config = if path.extension().is_some_and(|e| e == "toml") {
            toml::from_str(&content)?
        } else {
            serde_yaml::from_str(&content)?
        };

        config.validate()?;
        Ok(config)
    }

    /// Generate a sample configuration
    pub fn sample() -> Self {
        Self {
            agent: AgentConfig::default(),
            servers: vec![ServerConfig {
                host: "localhost".to_string(),
                port: DEFAULT_GRPC_PORT,
                token: "your_token_here".to_string(),
                permission: 0,
                tls_enabled: false,
                tls_verify: true,
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
        }
    }

    /// Validate configuration
    fn validate(&self) -> Result<()> {
        if self.servers.is_empty() {
            anyhow::bail!("At least one server must be configured");
        }

        for (i, server) in self.servers.iter().enumerate() {
            if server.host.is_empty() {
                anyhow::bail!("Server {} host cannot be empty", i);
            }
            if server.token.is_empty() {
                anyhow::bail!("Server {} token cannot be empty", i);
            }
            if server.permission > 3 {
                anyhow::bail!("Server {} permission must be 0-3", i);
            }
        }

        if self.shell.enabled && self.shell.super_token.is_none() {
            anyhow::bail!("Shell is enabled but super_token is not set");
        }

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
