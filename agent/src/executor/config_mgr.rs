use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Arc;
use tracing::{info, warn};
use uuid::Uuid;

use crate::config::Config;
use crate::proto::{CommandResult, ConfigBackup, ConfigResult};

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
                let sanitized = output != content;

                info!("Read config file: {}", path);
                CommandResult {
                    command_id: String::new(),
                    success: true,
                    output: output.clone(),
                    error: String::new(),
                    config_result: Some(ConfigResult {
                        path: path.to_string(),
                        content: output,
                        sanitized,
                        valid: true,
                        ..Default::default()
                    }),
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

        let existed = Path::new(path).exists();
        let backup_path = if self.config.config_management.backup_on_change && existed {
            match self.create_backup(path) {
                Ok(backup) => Some(backup),
                Err(error) => {
                    return CommandResult {
                        command_id: String::new(),
                        success: false,
                        output: String::new(),
                        error: format!("Failed to create config backup: {error}"),
                        ..Default::default()
                    };
                }
            }
        } else {
            None
        };

        if let Err(error) = self.write_atomically(path, content) {
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error,
                ..Default::default()
            };
        }

        let should_validate = params
            .get("validate")
            .map(|value| value.eq_ignore_ascii_case("true"))
            .unwrap_or(false);
        if should_validate {
            if let Err(error) = self.validate_written_config(path) {
                let restore_error =
                    self.restore_failed_write(path, backup_path.as_deref(), existed);
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: match restore_error {
                        Ok(()) => {
                            format!("Config validation failed; previous content restored: {error}")
                        }
                        Err(restore) => format!(
                            "Config validation failed and automatic restore also failed: {error}; {restore}"
                        ),
                    },
                    ..Default::default()
                };
            }
        }

        let should_reload = params
            .get("reload")
            .map(|value| value.eq_ignore_ascii_case("true"))
            .unwrap_or(false);
        if should_reload {
            if let Err(error) = self.reload_managed_service(path) {
                let restore_error =
                    self.restore_failed_write(path, backup_path.as_deref(), existed);
                if restore_error.is_ok() {
                    let _ = self.reload_managed_service(path);
                }
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: match restore_error {
                        Ok(()) => {
                            format!("Service reload failed; previous content restored: {error}")
                        }
                        Err(restore) => format!(
                            "Service reload failed and automatic restore also failed: {error}; {restore}"
                        ),
                    },
                    ..Default::default()
                };
            }
        }

        info!("Wrote config file: {}", path);
        CommandResult {
            command_id: String::new(),
            success: true,
            output: format!("Config written successfully: {path}"),
            error: String::new(),
            config_result: Some(ConfigResult {
                path: path.to_string(),
                backup_path: backup_path
                    .as_ref()
                    .map(|backup| backup.display().to_string())
                    .unwrap_or_default(),
                valid: true,
                ..Default::default()
            }),
            ..Default::default()
        }
    }

    /// Validate config syntax (basic validation)
    pub async fn validate_config(&self, params: &HashMap<String, String>) -> CommandResult {
        if !self.config.config_management.enabled {
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: "Config management is disabled".to_string(),
                ..Default::default()
            };
        }
        let path = params.get("path").cloned().unwrap_or_default();
        let supplied_content = params.contains_key("content");
        if !path.is_empty() {
            if let Err(error) = self.validate_config_path(&path, false) {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error,
                    ..Default::default()
                };
            }
        }
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

        let format = params
            .get("format")
            .map(|s| s.as_str())
            .filter(|format| *format != "auto")
            .or_else(|| Self::format_for_path(&path))
            .unwrap_or("text");

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
            "nginx" if !supplied_content => self.validate_written_config(&path),
            "nginx" => self.validate_nginx_content(&content),
            // Plain-text configs such as /etc/hosts have no parser here. They
            // are still valid managed files; service-specific validation runs
            // after an atomic write when requested.
            _ => Ok(()),
        };

        match result {
            Ok(_) => CommandResult {
                command_id: String::new(),
                success: true,
                output: "Config syntax is valid".to_string(),
                error: String::new(),
                config_result: Some(ConfigResult {
                    path,
                    valid: true,
                    ..Default::default()
                }),
                ..Default::default()
            },
            Err(e) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: e.clone(),
                config_result: Some(ConfigResult {
                    path,
                    valid: false,
                    validation_error: e,
                    ..Default::default()
                }),
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

        // Use the explicitly selected backup when supplied, otherwise the
        // latest one. The selected path must belong to this config's backup set.
        let available_backups = self.find_all_backups(path);
        let selected_backup = params.get("backup").map(PathBuf::from);
        let backup_path = match selected_backup {
            Some(selected) if available_backups.contains(&selected) => Some(selected),
            Some(_) => None,
            None => available_backups.last().cloned(),
        };
        let backup_path = match backup_path {
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

        let guard_backup = if Path::new(path).exists() {
            self.create_backup(path).ok()
        } else {
            None
        };
        if let Err(error) = self.write_atomically(path, &backup_content) {
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error,
                ..Default::default()
            };
        }
        let should_reload = params
            .get("reload")
            .map(|value| value.eq_ignore_ascii_case("true"))
            .unwrap_or(false);
        if should_reload {
            let post_action = self
                .validate_written_config(path)
                .and_then(|_| self.reload_managed_service(path));
            if let Err(error) = post_action {
                let restore = self.restore_failed_write(path, guard_backup.as_deref(), true);
                if restore.is_ok() {
                    let _ = self.reload_managed_service(path);
                }
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: match restore {
                        Ok(()) => format!(
                            "Rollback validation failed; original content restored: {error}"
                        ),
                        Err(restore_error) => format!(
                            "Rollback validation failed and original content could not be restored: {error}; {restore_error}"
                        ),
                    },
                    ..Default::default()
                };
            }
        }

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
            config_result: Some(ConfigResult {
                path: path.to_string(),
                backup_path: backup_path.display().to_string(),
                valid: true,
                ..Default::default()
            }),
            ..Default::default()
        }
    }

    /// List available backups for a config
    pub async fn list_backups(&self, params: &HashMap<String, String>) -> CommandResult {
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

        let backup_paths = self.find_all_backups(path);

        let output = if backup_paths.is_empty() {
            "No backups found".to_string()
        } else {
            backup_paths
                .iter()
                .map(|p| p.display().to_string())
                .collect::<Vec<_>>()
                .join("\n")
        };
        let backups = backup_paths
            .iter()
            .map(|backup| {
                let metadata = fs::metadata(backup).ok();
                ConfigBackup {
                    path: backup.display().to_string(),
                    created_at: metadata
                        .as_ref()
                        .and_then(|value| value.modified().ok())
                        .and_then(|value| value.duration_since(std::time::UNIX_EPOCH).ok())
                        .and_then(|value| {
                            chrono::DateTime::from_timestamp(value.as_secs() as i64, 0)
                        })
                        .map(|value| value.to_rfc3339())
                        .unwrap_or_default(),
                    size: metadata.map(|value| value.len() as i64).unwrap_or_default(),
                    checksum: String::new(),
                }
            })
            .collect();

        CommandResult {
            command_id: String::new(),
            success: true,
            output,
            error: String::new(),
            config_result: Some(ConfigResult {
                path: path.to_string(),
                backups,
                valid: true,
                ..Default::default()
            }),
            ..Default::default()
        }
    }

    fn format_for_path(path: &str) -> Option<&'static str> {
        let normalized = path.replace('\\', "/").to_ascii_lowercase();
        if normalized.contains("/nginx/") || normalized.ends_with("/nginx.conf") {
            return Some("nginx");
        }
        match Path::new(&normalized)
            .extension()
            .and_then(|extension| extension.to_str())
        {
            Some("yaml" | "yml") => Some("yaml"),
            Some("json") => Some("json"),
            Some("toml") => Some("toml"),
            _ => None,
        }
    }

    fn validate_nginx_content(&self, content: &str) -> Result<(), String> {
        if content.contains('\0') {
            return Err("Nginx config contains a NUL byte".to_string());
        }
        let mut depth = 0i32;
        for line in content.lines() {
            let code = line.split('#').next().unwrap_or_default();
            for character in code.chars() {
                match character {
                    '{' => depth += 1,
                    '}' => {
                        depth -= 1;
                        if depth < 0 {
                            return Err("Nginx config has an unmatched closing brace".to_string());
                        }
                    }
                    _ => {}
                }
            }
        }
        if depth == 0 {
            Ok(())
        } else {
            Err("Nginx config has unbalanced braces".to_string())
        }
    }

    fn write_atomically(&self, path: &str, content: &str) -> Result<(), String> {
        let target = Path::new(path);
        let parent = target
            .parent()
            .ok_or_else(|| "Config path has no parent directory".to_string())?;
        if !parent.is_dir() {
            return Err("Config parent directory does not exist".to_string());
        }
        let name = target
            .file_name()
            .and_then(|value| value.to_str())
            .ok_or_else(|| "Config file name is invalid".to_string())?;
        let temporary = parent.join(format!(".{name}.nanolink-{}.tmp", Uuid::new_v4()));
        let previous_permissions = fs::metadata(target).ok().map(|value| value.permissions());
        let write_result = (|| {
            fs::write(&temporary, content)
                .map_err(|error| format!("Failed to write temporary config: {error}"))?;
            if let Some(permissions) = previous_permissions {
                fs::set_permissions(&temporary, permissions)
                    .map_err(|error| format!("Failed to preserve config permissions: {error}"))?;
            }
            #[cfg(windows)]
            if target.exists() {
                fs::remove_file(target)
                    .map_err(|error| format!("Failed to replace config: {error}"))?;
            }
            fs::rename(&temporary, target)
                .map_err(|error| format!("Failed to activate config atomically: {error}"))
        })();
        if write_result.is_err() {
            let _ = fs::remove_file(&temporary);
        }
        write_result
    }

    fn validate_written_config(&self, path: &str) -> Result<(), String> {
        match Self::format_for_path(path) {
            Some("nginx") => {
                let output = Command::new("nginx")
                    .arg("-t")
                    .output()
                    .map_err(|error| format!("Failed to run nginx -t: {error}"))?;
                if output.status.success() {
                    Ok(())
                } else {
                    let stderr = String::from_utf8_lossy(&output.stderr);
                    Err(stderr.trim().to_string())
                }
            }
            Some("yaml") => serde_yaml::from_str::<serde_yaml::Value>(
                &fs::read_to_string(path).map_err(|error| error.to_string())?,
            )
            .map(|_| ())
            .map_err(|error| format!("Invalid YAML: {error}")),
            Some("json") => serde_json::from_str::<serde_json::Value>(
                &fs::read_to_string(path).map_err(|error| error.to_string())?,
            )
            .map(|_| ())
            .map_err(|error| format!("Invalid JSON: {error}")),
            Some("toml") => toml::from_str::<toml::Value>(
                &fs::read_to_string(path).map_err(|error| error.to_string())?,
            )
            .map(|_| ())
            .map_err(|error| format!("Invalid TOML: {error}")),
            _ => Ok(()),
        }
    }

    fn reload_managed_service(&self, path: &str) -> Result<(), String> {
        if Self::format_for_path(path) != Some("nginx") {
            return Err("Automatic reload is only supported for Nginx configs".to_string());
        }
        let output = Command::new("systemctl")
            .args(["reload", "nginx"])
            .output()
            .map_err(|error| format!("Failed to reload nginx: {error}"))?;
        if output.status.success() {
            Ok(())
        } else {
            let stderr = String::from_utf8_lossy(&output.stderr);
            Err(stderr.trim().to_string())
        }
    }

    fn restore_failed_write(
        &self,
        path: &str,
        backup: Option<&Path>,
        existed: bool,
    ) -> Result<(), String> {
        match (backup, existed) {
            (Some(backup), true) => fs::copy(backup, path)
                .map(|_| ())
                .map_err(|error| format!("Failed to restore backup: {error}")),
            (_, false) => {
                if Path::new(path).exists() {
                    fs::remove_file(path)
                        .map_err(|error| format!("Failed to remove invalid new config: {error}"))?;
                }
                Ok(())
            }
            (None, true) => Err("No backup is available for restore".to_string()),
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

        // Check forbidden paths against canonical path.
        // Match the path AND all its ancestors so that a rule like "/home/*/.ssh"
        // also blocks "/home/alice/.ssh/id_rsa" (a plain glob won't, since '*'
        // doesn't cross '/').
        for forbidden in FORBIDDEN_PATHS {
            if let Ok(pattern) = glob::Pattern::new(forbidden) {
                let hit = pattern.matches(&canonical_str)
                    || pattern.matches(path)
                    || canonical_path
                        .ancestors()
                        .skip(1)
                        .any(|a| pattern.matches(&a.to_string_lossy()));
                if hit {
                    return Err("Access to this path is forbidden".to_string());
                }
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
        let timestamp = chrono::Utc::now().format("%Y%m%d_%H%M%S_%3f");
        let backup_filename = format!("{filename}_{timestamp}.bak");
        let backup_path = backup_dir.join(&backup_filename);

        // Copy file
        fs::copy(path, &backup_path).map_err(|e| format!("Failed to copy to backup: {e}"))?;

        // Clean old backups
        self.cleanup_old_backups(path);

        info!("Created backup: {}", backup_path.display());
        Ok(backup_path)
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

        // Match only this file's backups exactly. Milliseconds avoid collisions
        // when validation/rollback creates more than one backup in a second.
        // A plain starts_with(filename) would mismatch configs that share a
        // prefix (querying "app" would match "app.conf_*.bak"), which on
        // rollback could restore the wrong file's contents.
        let re = regex::Regex::new(&format!(
            r"^{}_\d{{8}}_\d{{6}}(?:_\d{{3}})?\.bak$",
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

#[cfg(test)]
mod tests {
    use super::*;

    fn manager() -> ConfigManager {
        ConfigManager::new(Arc::new(Config::sample()))
    }

    #[test]
    fn config_format_uses_path_context() {
        assert_eq!(
            ConfigManager::format_for_path("/etc/nginx/nginx.conf"),
            Some("nginx")
        );
        assert_eq!(
            ConfigManager::format_for_path("/etc/nginx/conf.d/app.conf"),
            Some("nginx")
        );
        assert_eq!(
            ConfigManager::format_for_path("/opt/app/application.yaml"),
            Some("yaml")
        );
        assert_eq!(ConfigManager::format_for_path("/etc/hosts"), None);
    }

    #[test]
    fn nginx_preflight_rejects_unbalanced_braces() {
        let manager = manager();
        assert!(
            manager
                .validate_nginx_content("server { listen 80; }")
                .is_ok()
        );
        assert!(
            manager
                .validate_nginx_content("server { listen 80;")
                .is_err()
        );
        assert!(
            manager
                .validate_nginx_content("server } listen 80;")
                .is_err()
        );
    }

    #[tokio::test]
    async fn validation_honors_the_config_allowlist() {
        let mut config = Config::sample();
        config.config_management.enabled = true;
        config.config_management.allowed_configs = vec!["/etc/nginx/*.conf".to_string()];
        let manager = ConfigManager::new(Arc::new(config));
        let params = HashMap::from([("path".to_string(), "/etc/hosts".to_string())]);

        let result = manager.validate_config(&params).await;

        assert!(!result.success);
        assert_eq!(result.error, "Path not in allowed list");
    }
}
