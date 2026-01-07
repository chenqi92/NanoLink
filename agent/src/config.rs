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

    /// API token for authentication (启用时必须设置)
    pub api_token: Option<String>,
}

impl Default for ManagementConfig {
    fn default() -> Self {
        Self {
            enabled: false, // 默认禁用
            port: default_management_port(),
            bind_address: default_bind_address(),
            api_token: None,
        }
    }
}

fn default_management_port() -> u16 {
    9101
}

fn default_bind_address() -> String {
    "127.0.0.1".to_string() // 仅绑定本地回环地址
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

    /// Preferred language (en/zh). If not set, auto-detect from system locale.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub language: Option<String>,
}

impl Default for AgentConfig {
    fn default() -> Self {
        Self {
            hostname: None,
            heartbeat_interval: default_heartbeat_interval(),
            reconnect_delay: default_reconnect_delay(),
            max_reconnect_delay: default_max_reconnect_delay(),
            language: None,
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

        // Auto-disable Management API if enabled but api_token is not set
        // This ensures backward compatibility with old configs
        if config.management.enabled && config.management.api_token.is_none() {
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
            scripts: ScriptsConfig::default(),
            config_management: ConfigManagementConfig::default(),
            package_management: PackageManagementConfig::default(),
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
        }

        if self.shell.enabled && self.shell.super_token.is_none() {
            anyhow::bail!("Shell is enabled but super_token is not set");
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
