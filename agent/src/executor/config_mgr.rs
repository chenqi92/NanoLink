use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tracing::{info, warn};

use crate::config::Config;
use crate::proto::CommandResult;

/// Config file manager with backup and rollback support
pub struct ConfigManager {
    config: Arc<Config>,
}

/// Sensitive patterns to sanitize in config output
const SENSITIVE_PATTERNS: &[(&str, &str)] = &[
    // Passwords
    (r"password\s*[=:]\s*\S+", "password=***REDACTED***"),
    (r"passwd\s*[=:]\s*\S+", "passwd=***REDACTED***"),
    // API Keys and Tokens
    (r"secret\s*[=:]\s*\S+", "secret=***REDACTED***"),
    (r"api[_-]?key\s*[=:]\s*\S+", "api_key=***REDACTED***"),
    (r"token\s*[=:]\s*\S+", "token=***REDACTED***"),
    (r"auth\s*[=:]\s*\S+", "auth=***REDACTED***"),
    (r"credentials\s*[=:]\s*\S+", "credentials=***REDACTED***"),
    // AWS credentials
    (r"AKIA[A-Z0-9]{16}", "***AWS_KEY_REDACTED***"),
    (
        r"aws_access_key_id\s*[=:]\s*\S+",
        "aws_access_key_id=***REDACTED***",
    ),
    (
        r"aws_secret_access_key\s*[=:]\s*\S+",
        "aws_secret_access_key=***REDACTED***",
    ),
    // Database connection strings
    (r"mysql://[^@\s]+@", "mysql://***REDACTED***@"),
    (r"postgres://[^@\s]+@", "postgres://***REDACTED***@"),
    (r"mongodb://[^@\s]+@", "mongodb://***REDACTED***@"),
    (r"redis://:[^@\s]+@", "redis://***REDACTED***@"),
    // Private keys
    (
        r"-----BEGIN\s+(?:RSA\s+)?PRIVATE\s+KEY-----",
        "***PRIVATE_KEY_REDACTED***",
    ),
    // GitHub/GitLab tokens
    (r"ghp_[A-Za-z0-9]{36,}", "***GITHUB_TOKEN_REDACTED***"),
    (r"glpat-[A-Za-z0-9\-]{20,}", "***GITLAB_TOKEN_REDACTED***"),
];

/// Forbidden paths that should never be read or written. Beyond credential
/// stores, this also blocks the common root-persistence / privilege-escalation
/// locations so they cannot be reached even if allowed_configs is configured
/// broadly.
const FORBIDDEN_PATHS: &[&str] = &[
    "/etc/shadow",
    "/etc/gshadow",
    "/etc/sudoers",
    "/etc/sudoers.d",
    "/root/.ssh",
    "/home/*/.ssh",
    "/etc/ssh/ssh_host_*_key",
    "/etc/ssl/private",
    // Scheduled-task persistence
    "/etc/cron.d",
    "/etc/cron.daily",
    "/etc/cron.hourly",
    "/etc/cron.weekly",
    "/etc/cron.monthly",
    "/etc/crontab",
    "/var/spool/cron",
    // Service / init persistence
    "/etc/systemd",
    "/usr/lib/systemd",
    "/lib/systemd",
    "/etc/init.d",
    "/etc/rc.local",
    // Dynamic-linker and PAM hijacks
    "/etc/ld.so.preload",
    "/etc/ld.so.conf",
    "/etc/ld.so.conf.d",
    "/etc/pam.d",
    // Shell-profile persistence
    "/etc/profile",
    "/etc/profile.d",
    "/etc/bash.bashrc",
    "/etc/environment",
    "C:\\Windows\\System32\\config\\SAM",
    "C:\\Windows\\System32\\config\\SECURITY",
];

impl ConfigManager {
    /// Create a new config manager
    pub fn new(config: Arc<Config>) -> Self {
        Self { config }
    }

    /// Read a config file (with optional sanitization)
    pub async fn read_config(&self, params: &HashMap<String, String>) -> CommandResult {
        if !self.config.config_management.enabled {
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: "Config management is disabled".to_string(),
                ..Default::default()
            };
        }

        let path = match params.get("path") {
            Some(p) => p,
            None => {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: "Config path is required".to_string(),
                    ..Default::default()
                };
            }
        };

        // Security checks (read path: denylist-only when no allowlist set)
        if let Err(e) = self.validate_config_path(path, false) {
            warn!("Config path validation failed: {} - {}", path, e);
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: e,
                ..Default::default()
            };
        }

        // Read file
        match fs::read_to_string(path) {
            Ok(content) => {
                // Always sanitize: a client-supplied sanitize=false must not be
                // able to exfiltrate secrets (passwords, keys, tokens) verbatim.
                let output = self.sanitize_content(&content);

                info!("Read config file: {}", path);
                CommandResult {
                    command_id: String::new(),
                    success: true,
                    output,
                    error: String::new(),
                    ..Default::default()
                }
            }
            Err(e) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: format!("Failed to read config: {e}"),
                ..Default::default()
            },
        }
    }

    /// Write a config file (with automatic backup)
    pub async fn write_config(&self, params: &HashMap<String, String>) -> CommandResult {
        if !self.config.config_management.enabled {
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: "Config management is disabled".to_string(),
                ..Default::default()
            };
        }

        let path = match params.get("path") {
            Some(p) => p,
            None => {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: "Config path is required".to_string(),
                    ..Default::default()
                };
            }
        };

        let content = match params.get("content") {
            Some(c) => c,
            None => {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: "Config content is required".to_string(),
                    ..Default::default()
                };
            }
        };

        // Security checks
        if let Err(e) = self.validate_config_path(path, true) {
            warn!("Config path validation failed: {} - {}", path, e);
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: e,
                ..Default::default()
            };
        }

        // Create backup if enabled and file exists
        if self.config.config_management.backup_on_change && Path::new(path).exists() {
            if let Err(e) = self.create_backup(path) {
                warn!("Failed to create backup for {}: {}", path, e);
                // Continue anyway - backup failure shouldn't block the write
            }
        }

        // Write file
        match fs::write(path, content) {
            Ok(()) => {
                info!("Wrote config file: {}", path);
                CommandResult {
                    command_id: String::new(),
                    success: true,
                    output: format!("Config written successfully: {path}"),
                    error: String::new(),
                    ..Default::default()
                }
            }
            Err(e) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: format!("Failed to write config: {e}"),
                ..Default::default()
            },
        }
    }

    /// Validate config syntax (basic validation)
    pub async fn validate_config(&self, params: &HashMap<String, String>) -> CommandResult {
        let content = match params.get("content") {
            Some(c) => c.clone(),
            None => {
                // Try to read from path if content not provided
                match params.get("path") {
                    Some(p) => match fs::read_to_string(p) {
                        Ok(c) => c,
                        Err(e) => {
                            return CommandResult {
                                command_id: String::new(),
                                success: false,
                                output: String::new(),
                                error: format!("Failed to read config: {e}"),
                                ..Default::default()
                            };
                        }
                    },
                    None => {
                        return CommandResult {
                            command_id: String::new(),
                            success: false,
                            output: String::new(),
                            error: "Either content or path is required".to_string(),
                            ..Default::default()
                        };
                    }
                }
            }
        };

        let format = params.get("format").map(|s| s.as_str()).unwrap_or("auto");

        // Try to parse based on format
        // Map all success values to () since we only care about parse success
        let result: Result<(), String> = match format {
            "yaml" | "yml" => serde_yaml::from_str::<serde_yaml::Value>(&content)
                .map(|_| ())
                .map_err(|e| format!("Invalid YAML: {e}")),
            "json" => serde_json::from_str::<serde_json::Value>(&content)
                .map(|_| ())
                .map_err(|e| format!("Invalid JSON: {e}")),
            "toml" => toml::from_str::<toml::Value>(&content)
                .map(|_| ())
                .map_err(|e| format!("Invalid TOML: {e}")),
            _ => {
                // Try each format (auto-detect)
                let is_yaml = serde_yaml::from_str::<serde_yaml::Value>(&content).is_ok();
                let is_json = serde_json::from_str::<serde_json::Value>(&content).is_ok();
                let is_toml = toml::from_str::<toml::Value>(&content).is_ok();

                if is_yaml || is_json || is_toml {
                    Ok(())
                } else {
                    Err("Content is not valid YAML, JSON, or TOML".to_string())
                }
            }
        };

        match result {
            Ok(_) => CommandResult {
                command_id: String::new(),
                success: true,
                output: "Config syntax is valid".to_string(),
                error: String::new(),
                ..Default::default()
            },
            Err(e) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: e,
                ..Default::default()
            },
        }
    }

    /// Rollback config to a previous backup
    pub async fn rollback_config(&self, params: &HashMap<String, String>) -> CommandResult {
        if !self.config.config_management.enabled {
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: "Config management is disabled".to_string(),
                ..Default::default()
            };
        }

        let path = match params.get("path") {
            Some(p) => p,
            None => {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: "Config path is required".to_string(),
                    ..Default::default()
                };
            }
        };

        // Security check
        if let Err(e) = self.validate_config_path(path, true) {
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: e,
                ..Default::default()
            };
        }

        // Find the latest backup
        let backup_path = match self.find_latest_backup(path) {
            Some(p) => p,
            None => {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: "No backup found for this config".to_string(),
                    ..Default::default()
                };
            }
        };

        // Read backup
        let backup_content = match fs::read_to_string(&backup_path) {
            Ok(c) => c,
            Err(e) => {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: format!("Failed to read backup: {e}"),
                    ..Default::default()
                };
            }
        };

        // Restore
        match fs::write(path, &backup_content) {
            Ok(()) => {
                info!(
                    "Rolled back config {} from backup {}",
                    path,
                    backup_path.display()
                );
                CommandResult {
                    command_id: String::new(),
                    success: true,
                    output: format!("Config rolled back from: {}", backup_path.display()),
                    error: String::new(),
                    ..Default::default()
                }
            }
            Err(e) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: format!("Failed to restore config: {e}"),
                ..Default::default()
            },
        }
    }

    /// List available backups for a config
    pub async fn list_backups(&self, params: &HashMap<String, String>) -> CommandResult {
        let path = match params.get("path") {
            Some(p) => p,
            None => {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: "Config path is required".to_string(),
                    ..Default::default()
                };
            }
        };

        let backups = self.find_all_backups(path);

        let output = if backups.is_empty() {
            "No backups found".to_string()
        } else {
            backups
                .iter()
                .map(|p| p.display().to_string())
                .collect::<Vec<_>>()
                .join("\n")
        };

        CommandResult {
            command_id: String::new(),
            success: true,
            output,
            error: String::new(),
            ..Default::default()
        }
    }

    /// Validate config path against whitelist and forbidden paths
    fn validate_config_path(&self, path: &str, for_write: bool) -> Result<(), String> {
        // Check for obvious path traversal patterns
        if path.contains("..") {
            return Err("Path traversal detected".to_string());
        }

        // Canonicalize path to resolve symlinks and get absolute path
        // This prevents symlink attacks and ensures we're checking the real path
        let canonical_path = match Path::new(path).canonicalize() {
            Ok(p) => p,
            Err(_) => {
                // If path doesn't exist yet, try to canonicalize parent directory
                if let Some(parent) = Path::new(path).parent() {
                    if let Ok(canonical_parent) = parent.canonicalize() {
                        let file_name = Path::new(path)
                            .file_name()
                            .ok_or_else(|| "Invalid file name".to_string())?;
                        canonical_parent.join(file_name)
                    } else {
                        // Parent doesn't exist either, use the original path but be strict
                        PathBuf::from(path)
                    }
                } else {
                    PathBuf::from(path)
                }
            }
        };

        let canonical_str = canonical_path.to_string_lossy();

        // Re-check for path traversal after canonicalization
        if canonical_str.contains("..") {
            return Err("Path traversal detected after canonicalization".to_string());
        }

        // Check forbidden paths against canonical path
        for forbidden in FORBIDDEN_PATHS {
            if glob::Pattern::new(forbidden)
                .map(|p| p.matches(&canonical_str) || p.matches(path))
                .unwrap_or(false)
            {
                return Err("Access to this path is forbidden".to_string());
            }
        }

        // Fail closed for writes when no whitelist is configured: an empty
        // allowed_configs previously meant "write any non-forbidden config",
        // which lets a service-control caller overwrite systemd units,
        // sudoers.d, the agent's own config, etc. Reads stay denylist-only.
        if self.config.config_management.allowed_configs.is_empty() {
            if for_write {
                return Err(
                    "Config write disabled: configure config_management.allowed_configs to enable writes"
                        .to_string(),
                );
            }
            return Ok(());
        }

        // Check whitelist - must match canonical path
        let allowed = self
            .config
            .config_management
            .allowed_configs
            .iter()
            .any(|allowed| {
                glob::Pattern::new(allowed)
                    .map(|p| p.matches(&canonical_str) || p.matches(path))
                    .unwrap_or(allowed == path || allowed == &*canonical_str)
            });

        if !allowed {
            return Err("Path not in allowed list".to_string());
        }

        Ok(())
    }

    /// Sanitize content by replacing sensitive values
    fn sanitize_content(&self, content: &str) -> String {
        use regex::Regex;

        let mut result = content.to_string();
        for (pattern, replacement) in SENSITIVE_PATTERNS {
            if let Ok(re) = Regex::new(pattern) {
                result = re.replace_all(&result, *replacement).to_string();
            }
        }
        result
    }

    /// Create a backup of the config file
    fn create_backup(&self, path: &str) -> Result<PathBuf, String> {
        let backup_dir = PathBuf::from(&self.config.config_management.backup_dir);

        // Ensure backup directory exists
        if let Err(e) = fs::create_dir_all(&backup_dir) {
            return Err(format!("Failed to create backup directory: {e}"));
        }

        // Generate backup filename
        let filename = Path::new(path)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("unknown");
        let timestamp = chrono::Utc::now().format("%Y%m%d_%H%M%S");
        let backup_filename = format!("{filename}_{timestamp}.bak");
        let backup_path = backup_dir.join(&backup_filename);

        // Copy file
        fs::copy(path, &backup_path).map_err(|e| format!("Failed to copy to backup: {e}"))?;

        // Clean old backups
        self.cleanup_old_backups(path);

        info!("Created backup: {}", backup_path.display());
        Ok(backup_path)
    }

    /// Find the latest backup for a config file
    fn find_latest_backup(&self, path: &str) -> Option<PathBuf> {
        let backups = self.find_all_backups(path);
        backups.into_iter().last()
    }

    /// Find all backups for a config file
    fn find_all_backups(&self, path: &str) -> Vec<PathBuf> {
        let backup_dir = PathBuf::from(&self.config.config_management.backup_dir);
        if !backup_dir.exists() {
            return Vec::new();
        }

        let filename = Path::new(path)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("");

        // Match only this file's backups exactly: "{filename}_YYYYMMDD_HHMMSS.bak".
        // A plain starts_with(filename) would mismatch configs that share a
        // prefix (querying "app" would match "app.conf_*.bak"), which on
        // rollback could restore the wrong file's contents.
        let re = regex::Regex::new(&format!(
            r"^{}_\d{{8}}_\d{{6}}\.bak$",
            regex::escape(filename)
        ))
        .ok();

        let mut backups: Vec<PathBuf> = fs::read_dir(&backup_dir)
            .ok()
            .map(|entries| {
                entries
                    .filter_map(|e| e.ok())
                    .map(|e| e.path())
                    .filter(|p| {
                        p.file_name()
                            .and_then(|n| n.to_str())
                            .map(|n| match &re {
                                Some(re) => re.is_match(n),
                                None => n.starts_with(filename) && n.ends_with(".bak"),
                            })
                            .unwrap_or(false)
                    })
                    .collect()
            })
            .unwrap_or_default();

        // Lexical sort == chronological here because the timestamp is
        // zero-padded YYYYMMDD_HHMMSS and the prefix is identical across matches.
        backups.sort();
        backups
    }

    /// Remove old backups exceeding max_backups limit
    fn cleanup_old_backups(&self, path: &str) {
        let max_backups = self.config.config_management.max_backups as usize;
        let backups = self.find_all_backups(path);

        if backups.len() > max_backups {
            let to_remove = backups.len() - max_backups;
            for backup in backups.into_iter().take(to_remove) {
                if let Err(e) = fs::remove_file(&backup) {
                    warn!("Failed to remove old backup {}: {}", backup.display(), e);
                } else {
                    info!("Removed old backup: {}", backup.display());
                }
            }
        }
    }
}
