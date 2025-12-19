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

fn default_management_enabled() -> bool { true }
fn default_management_port() -> u16 { 9101 }

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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    /// Server URL
    /// - WebSocket: ws:// or wss://
    /// - gRPC: grpc:// or grpcs://
    pub url: String,

    /// Authentication token
    pub token: String,

    /// Permission level for this connection
    /// 0 = READ_ONLY, 1 = BASIC_WRITE, 2 = SERVICE_CONTROL, 3 = SYSTEM_ADMIN
    #[serde(default)]
    pub permission: u8,

    /// Enable TLS certificate verification
    #[serde(default = "default_true")]
    pub tls_verify: bool,

    /// Protocol type (auto-detected from URL if not specified)
    /// "websocket" or "grpc"
    #[serde(default)]
    pub protocol: Option<String>,
}

impl ServerConfig {
    /// Get the protocol type for this server
    pub fn get_protocol(&self) -> Protocol {
        if let Some(ref proto) = self.protocol {
            match proto.to_lowercase().as_str() {
                "grpc" => return Protocol::Grpc,
                "websocket" | "ws" => return Protocol::WebSocket,
                _ => {}
            }
        }

        // Auto-detect from URL
        if self.url.starts_with("grpc://") || self.url.starts_with("grpcs://") {
            Protocol::Grpc
        } else {
            Protocol::WebSocket
        }
    }
}

/// Protocol type for server connection
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Protocol {
    WebSocket,
    Grpc,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CollectorConfig {
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

    /// Enable disk I/O metrics
    #[serde(default = "default_true")]
    pub enable_disk_io: bool,

    /// Enable network metrics
    #[serde(default = "default_true")]
    pub enable_network: bool,

    /// Enable per-core CPU metrics
    #[serde(default = "default_true")]
    pub enable_per_core_cpu: bool,
}

impl Default for CollectorConfig {
    fn default() -> Self {
        Self {
            cpu_interval_ms: default_cpu_interval(),
            disk_interval_ms: default_disk_interval(),
            network_interval_ms: default_network_interval(),
            process_interval_ms: default_process_interval(),
            disk_space_interval_ms: default_disk_space_interval(),
            enable_disk_io: true,
            enable_network: true,
            enable_per_core_cpu: true,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BufferConfig {
    /// Ring buffer capacity (number of metrics to cache)
    /// Default: 600 (10 minutes at 1 second interval)
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

// Default value functions
fn default_heartbeat_interval() -> u64 { 30 }
fn default_reconnect_delay() -> u64 { 5 }
fn default_max_reconnect_delay() -> u64 { 300 }
fn default_cpu_interval() -> u64 { 1000 }
fn default_disk_interval() -> u64 { 3000 }
fn default_network_interval() -> u64 { 1000 }
fn default_process_interval() -> u64 { 5000 }
fn default_disk_space_interval() -> u64 { 30000 }
fn default_buffer_capacity() -> usize { 600 }
fn default_shell_timeout() -> u64 { 30 }
fn default_true() -> bool { true }
fn default_log_level() -> String { "info".to_string() }
fn default_audit_file() -> String { "nanolink-audit.log".to_string() }

fn default_blacklist() -> Vec<String> {
    vec![
        "rm -rf".to_string(),
        "mkfs".to_string(),
        "> /dev".to_string(),
        "dd if=".to_string(),
        ":(){:|:&};:".to_string(),  // fork bomb
    ]
}

impl Config {
    /// Load configuration from file
    pub fn load(path: &Path) -> Result<Self> {
        let content = std::fs::read_to_string(path)
            .with_context(|| format!("Failed to read config file: {:?}", path))?;

        let config: Config = if path.extension().map_or(false, |e| e == "toml") {
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
            servers: vec![
                ServerConfig {
                    url: "wss://monitor.example.com:9100".to_string(),
                    token: "your_token_here".to_string(),
                    permission: 0,
                    tls_verify: true,
                },
            ],
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
        }
    }

    /// Validate configuration
    fn validate(&self) -> Result<()> {
        if self.servers.is_empty() {
            anyhow::bail!("At least one server must be configured");
        }

        for (i, server) in self.servers.iter().enumerate() {
            if server.url.is_empty() {
                anyhow::bail!("Server {} URL cannot be empty", i);
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
