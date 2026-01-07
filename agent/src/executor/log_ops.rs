//! Log operations executor for querying system logs
//!
//! Supports:
//! - journald/systemd service logs (Linux)
//! - System logs from /var/log
//! - Audit logs from auditd (Linux)
//! - Windows Event Log (Windows)
//!
//! All log output is sanitized to redact sensitive information.

use std::collections::HashMap;
use std::process::Command;
use tracing::{info, warn};

use crate::proto::{CommandResult, LogEntry, LogQueryResult};
use crate::security::validation::validate_service_name;

/// Sensitive patterns that should be redacted from logs
const SENSITIVE_PATTERNS: &[(&str, &str)] = &[
    // Passwords
    (r"password\s*[=:]\s*\S+", "password=***REDACTED***"),
    (r"passwd\s*[=:]\s*\S+", "passwd=***REDACTED***"),
    (r"pwd\s*[=:]\s*\S+", "pwd=***REDACTED***"),
    // API Keys and Tokens
    (r"api[_-]?key\s*[=:]\s*\S+", "api_key=***REDACTED***"),
    (r"apikey\s*[=:]\s*\S+", "apikey=***REDACTED***"),
    (r"secret[_-]?key\s*[=:]\s*\S+", "secret_key=***REDACTED***"),
    (
        r"access[_-]?token\s*[=:]\s*\S+",
        "access_token=***REDACTED***",
    ),
    (r"auth[_-]?token\s*[=:]\s*\S+", "auth_token=***REDACTED***"),
    // Bearer tokens (JWT format)
    (
        r"Bearer\s+[A-Za-z0-9\-_=]+\.[A-Za-z0-9\-_=]+\.[A-Za-z0-9\-_=]+",
        "Bearer ***REDACTED***",
    ),
    (r"Bearer\s+\S{20,}", "Bearer ***REDACTED***"),
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
    // GitHub tokens (ghp_, gho_, ghu_, ghs_, ghr_)
    (r"ghp_[A-Za-z0-9]{36,}", "***GITHUB_TOKEN_REDACTED***"),
    (r"gho_[A-Za-z0-9]{36,}", "***GITHUB_TOKEN_REDACTED***"),
    (r"ghu_[A-Za-z0-9]{36,}", "***GITHUB_TOKEN_REDACTED***"),
    (r"ghs_[A-Za-z0-9]{36,}", "***GITHUB_TOKEN_REDACTED***"),
    (r"ghr_[A-Za-z0-9]{36,}", "***GITHUB_TOKEN_REDACTED***"),
    // GitLab tokens
    (r"glpat-[A-Za-z0-9\-]{20,}", "***GITLAB_TOKEN_REDACTED***"),
    // Slack tokens
    (r"xoxb-[A-Za-z0-9\-]+", "***SLACK_TOKEN_REDACTED***"),
    (r"xoxp-[A-Za-z0-9\-]+", "***SLACK_TOKEN_REDACTED***"),
    (r"xoxa-[A-Za-z0-9\-]+", "***SLACK_TOKEN_REDACTED***"),
    (r"xoxr-[A-Za-z0-9\-]+", "***SLACK_TOKEN_REDACTED***"),
    // Database connection strings
    (r"mysql://[^@\s]+@", "mysql://***REDACTED***@"),
    (r"postgres://[^@\s]+@", "postgres://***REDACTED***@"),
    (r"postgresql://[^@\s]+@", "postgresql://***REDACTED***@"),
    (r"mongodb://[^@\s]+@", "mongodb://***REDACTED***@"),
    (r"mongodb\+srv://[^@\s]+@", "mongodb+srv://***REDACTED***@"),
    (r"redis://:[^@\s]+@", "redis://***REDACTED***@"),
    // Private keys (various formats)
    (
        r"-----BEGIN\s+(?:RSA\s+)?PRIVATE\s+KEY-----",
        "***PRIVATE_KEY_REDACTED***",
    ),
    (
        r"-----BEGIN\s+EC\s+PRIVATE\s+KEY-----",
        "***PRIVATE_KEY_REDACTED***",
    ),
    (
        r"-----BEGIN\s+OPENSSH\s+PRIVATE\s+KEY-----",
        "***PRIVATE_KEY_REDACTED***",
    ),
    (
        r"-----BEGIN\s+PGP\s+PRIVATE\s+KEY\s+BLOCK-----",
        "***PRIVATE_KEY_REDACTED***",
    ),
    // Environment variable exports
    (
        r"export\s+\w*(?:PASSWORD|SECRET|TOKEN|KEY|CREDENTIAL)\w*\s*=\s*\S+",
        "export ***REDACTED***",
    ),
    // Google API keys
    (r"AIza[A-Za-z0-9\-_]{35}", "***GOOGLE_API_KEY_REDACTED***"),
    // Stripe keys
    (r"sk_live_[A-Za-z0-9]{24,}", "***STRIPE_KEY_REDACTED***"),
    (r"sk_test_[A-Za-z0-9]{24,}", "***STRIPE_KEY_REDACTED***"),
    (r"pk_live_[A-Za-z0-9]{24,}", "***STRIPE_KEY_REDACTED***"),
    (r"pk_test_[A-Za-z0-9]{24,}", "***STRIPE_KEY_REDACTED***"),
    // Generic secrets
    (r"secret\s*[=:]\s*\S+", "secret=***REDACTED***"),
    (r"token\s*[=:]\s*\S+", "token=***REDACTED***"),
    (r"credential\s*[=:]\s*\S+", "credential=***REDACTED***"),
    // Authorization headers
    (r"Authorization\s*:\s*\S+", "Authorization: ***REDACTED***"),
    (r"X-Api-Key\s*:\s*\S+", "X-Api-Key: ***REDACTED***"),
];

/// Allowed log file paths (whitelist)
const ALLOWED_LOG_PATHS: &[&str] = &[
    "/var/log/syslog",
    "/var/log/messages",
    "/var/log/auth.log",
    "/var/log/secure",
    "/var/log/kern.log",
    "/var/log/daemon.log",
    "/var/log/cron",
    "/var/log/maillog",
    "/var/log/boot.log",
    "/var/log/dmesg",
    "/var/log/nginx/access.log",
    "/var/log/nginx/error.log",
    "/var/log/apache2/access.log",
    "/var/log/apache2/error.log",
    "/var/log/httpd/access_log",
    "/var/log/httpd/error_log",
    "/var/log/mysql/error.log",
    "/var/log/postgresql/",
    "/var/log/redis/",
];

/// Log operations executor
pub struct LogExecutor {
    /// Maximum lines to return
    max_lines: u32,
    /// Whether to sanitize sensitive data
    sanitize: bool,
}

impl LogExecutor {
    /// Create a new log executor with default settings
    pub fn new() -> Self {
        Self {
            max_lines: 1000,
            sanitize: true,
        }
    }

    /// Create a new log executor with custom settings
    #[allow(dead_code)]
    pub fn with_config(max_lines: u32, sanitize: bool) -> Self {
        Self {
            max_lines,
            sanitize,
        }
    }

    /// Sanitize a log line to redact sensitive information
    fn sanitize_line(&self, line: &str) -> (String, bool) {
        if !self.sanitize {
            return (line.to_string(), false);
        }

        let mut result = line.to_string();
        let mut was_sanitized = false;

        for (pattern, replacement) in SENSITIVE_PATTERNS {
            if let Ok(re) = regex::Regex::new(&format!("(?i){pattern}")) {
                if re.is_match(&result) {
                    result = re.replace_all(&result, *replacement).to_string();
                    was_sanitized = true;
                }
            }
        }

        (result, was_sanitized)
    }

    /// Parse a log line into LogEntry
    fn parse_log_entry(&self, line: &str, source: &str) -> LogEntry {
        let (sanitized_message, _) = self.sanitize_line(line);

        // Try to extract timestamp and level from common log formats
        let (timestamp, level, message) = self.parse_log_format(&sanitized_message);

        LogEntry {
            timestamp,
            level,
            source: source.to_string(),
            message,
            metadata: HashMap::new(),
        }
    }

    /// Parse common log formats to extract timestamp and level
    fn parse_log_format(&self, line: &str) -> (String, String, String) {
        // journald format: "Mon DD HH:MM:SS hostname service[pid]: message"
        // or ISO format: "2024-01-01T00:00:00.000Z level message"

        // Try to extract timestamp from beginning
        let parts: Vec<&str> = line.splitn(4, ' ').collect();
        if parts.len() >= 4 {
            // Check if first 3 parts look like syslog timestamp
            if parts[0].len() == 3 && parts[1].parse::<u32>().is_ok() {
                let timestamp = format!("{} {} {}", parts[0], parts[1], parts[2]);
                return (timestamp, "info".to_string(), line.to_string());
            }
        }

        // Check for ISO timestamp
        if line.len() > 24 && line.chars().take(4).all(|c| c.is_ascii_digit()) {
            if let Some(space_pos) = line.find(' ') {
                let timestamp = line[..space_pos].to_string();
                return (timestamp, "info".to_string(), line.to_string());
            }
        }

        // Default: no timestamp detected
        (String::new(), "info".to_string(), line.to_string())
    }

    /// Helper to create an error CommandResult
    fn error_result(error: String) -> CommandResult {
        CommandResult {
            command_id: String::new(),
            success: false,
            output: String::new(),
            error,
            ..Default::default()
        }
    }

    /// Helper to create a success CommandResult with log data
    fn success_result(log_result: LogQueryResult) -> CommandResult {
        let output = format!("Retrieved {} log entries", log_result.lines.len());
        CommandResult {
            command_id: String::new(),
            success: true,
            output,
            error: String::new(),
            log_result: Some(log_result),
            ..Default::default()
        }
    }

    /// Query service logs from journald (Linux) or Event Log (Windows)
    pub async fn get_service_logs(&self, params: &HashMap<String, String>) -> CommandResult {
        let service = params.get("service").map(|s| s.as_str()).unwrap_or("");
        let lines = params
            .get("lines")
            .and_then(|s| s.parse().ok())
            .unwrap_or(100)
            .min(self.max_lines);
        #[allow(unused_variables)] // Used on Linux
        let since = params.get("since").map(|s| s.as_str());
        #[allow(unused_variables)] // Used on Linux
        let until = params.get("until").map(|s| s.as_str());
        #[allow(unused_variables)] // Used on all platforms except in certain cfg blocks
        let filter = params.get("filter").map(|s| s.as_str());

        // Validate service name
        if !service.is_empty() {
            if let Err(e) = validate_service_name(service) {
                return Self::error_result(format!("Invalid service name: {e}"));
            }
        }

        info!(
            "[AUDIT] ServiceLogs query: service={}, lines={}",
            service, lines
        );

        #[cfg(target_os = "linux")]
        {
            self.query_journald(service, lines, since, until, filter)
                .await
        }

        #[cfg(target_os = "windows")]
        {
            self.query_windows_event_log(service, lines, filter).await
        }

        #[cfg(target_os = "macos")]
        {
            self.query_macos_log(service, lines, filter).await
        }
    }

    /// Query journald logs on Linux
    #[cfg(target_os = "linux")]
    async fn query_journald(
        &self,
        service: &str,
        lines: u32,
        since: Option<&str>,
        until: Option<&str>,
        filter: Option<&str>,
    ) -> CommandResult {
        let mut args = vec![
            "--no-pager".to_string(),
            "-o".to_string(),
            "short-iso".to_string(),
            "-n".to_string(),
            lines.to_string(),
        ];

        if !service.is_empty() {
            args.push("-u".to_string());
            args.push(service.to_string());
        }

        if let Some(s) = since {
            args.push("--since".to_string());
            args.push(s.to_string());
        }

        if let Some(u) = until {
            args.push("--until".to_string());
            args.push(u.to_string());
        }

        match Command::new("journalctl").args(&args).output() {
            Ok(output) => {
                if !output.status.success() {
                    return Self::error_result(format!(
                        "journalctl failed: {}",
                        String::from_utf8_lossy(&output.stderr)
                    ));
                }

                let stdout = String::from_utf8_lossy(&output.stdout);
                let mut entries = Vec::new();
                let mut sanitized_count = 0;

                for line in stdout.lines() {
                    if line.trim().is_empty() {
                        continue;
                    }

                    // Apply filter if provided
                    if let Some(f) = filter {
                        if !line.to_lowercase().contains(&f.to_lowercase()) {
                            continue;
                        }
                    }

                    let (sanitized, was_sanitized) = self.sanitize_line(line);
                    if was_sanitized {
                        sanitized_count += 1;
                    }

                    entries.push(self.parse_log_entry(&sanitized, service));
                }

                Self::success_result(LogQueryResult {
                    lines: entries,
                    total_lines: stdout.lines().count() as i64,
                    log_source: "journald".to_string(),
                    sanitized: sanitized_count > 0,
                    sanitized_count,
                    start_time: since.unwrap_or("").to_string(),
                    end_time: until.unwrap_or("").to_string(),
                })
            }
            Err(e) => Self::error_result(format!("Failed to execute journalctl: {e}")),
        }
    }

    /// Allowed Windows Event Log names (whitelist)
    #[cfg(target_os = "windows")]
    const ALLOWED_EVENT_LOGS: &'static [&'static str] = &[
        "System",
        "Application",
        "Security",
        "Setup",
        "ForwardedEvents",
        "Windows PowerShell",
        "Microsoft-Windows-Sysmon/Operational",
    ];

    /// Query Windows Event Log
    #[cfg(target_os = "windows")]
    async fn query_windows_event_log(
        &self,
        source: &str,
        lines: u32,
        filter: Option<&str>,
    ) -> CommandResult {
        let log_name = if source.is_empty() { "System" } else { source };

        // Validate log name against whitelist to prevent PowerShell injection
        if !Self::ALLOWED_EVENT_LOGS
            .iter()
            .any(|&allowed| allowed.eq_ignore_ascii_case(log_name))
        {
            return Self::error_result(format!(
                "Invalid log name: '{}'. Allowed logs: {:?}",
                log_name,
                Self::ALLOWED_EVENT_LOGS
            ));
        }

        // Use single quotes and escape any remaining quotes for PowerShell safety
        let safe_log_name = log_name.replace('\'', "''");
        let script = format!(
            "Get-EventLog -LogName '{safe_log_name}' -Newest {lines} | Format-List TimeGenerated,EntryType,Source,Message"
        );

        match Command::new("powershell")
            .args(["-Command", &script])
            .output()
        {
            Ok(output) => {
                if !output.status.success() {
                    return Self::error_result(format!(
                        "Get-EventLog failed: {}",
                        String::from_utf8_lossy(&output.stderr)
                    ));
                }

                let stdout = String::from_utf8_lossy(&output.stdout);
                let mut entries = Vec::new();
                let mut sanitized_count = 0;

                for line in stdout.lines() {
                    if line.trim().is_empty() {
                        continue;
                    }

                    if let Some(f) = filter {
                        if !line.to_lowercase().contains(&f.to_lowercase()) {
                            continue;
                        }
                    }

                    let (sanitized, was_sanitized) = self.sanitize_line(line);
                    if was_sanitized {
                        sanitized_count += 1;
                    }

                    entries.push(self.parse_log_entry(&sanitized, log_name));
                }

                let total_lines = entries.len() as i64;
                Self::success_result(LogQueryResult {
                    lines: entries,
                    total_lines,
                    log_source: "eventlog".to_string(),
                    sanitized: sanitized_count > 0,
                    sanitized_count,
                    start_time: String::new(),
                    end_time: String::new(),
                })
            }
            Err(e) => Self::error_result(format!("Failed to query Event Log: {e}")),
        }
    }

    /// Query macOS unified log
    #[cfg(target_os = "macos")]
    async fn query_macos_log(
        &self,
        subsystem: &str,
        lines: u32,
        filter: Option<&str>,
    ) -> CommandResult {
        let mut args = vec!["show".to_string(), "--last".to_string(), "1h".to_string()];

        if !subsystem.is_empty() {
            // Validate and sanitize subsystem to prevent predicate injection
            // Only allow alphanumeric, dots, underscores, and hyphens
            if !subsystem
                .chars()
                .all(|c| c.is_alphanumeric() || c == '.' || c == '_' || c == '-')
            {
                return Self::error_result("Invalid subsystem name: only alphanumeric, dots, underscores, and hyphens are allowed".to_string());
            }
            // Escape single quotes in subsystem name
            let safe_subsystem = subsystem.replace('\'', "");
            args.push("--predicate".to_string());
            args.push(format!("subsystem == '{}'", safe_subsystem));
        }

        match Command::new("log").args(&args).output() {
            Ok(output) => {
                if !output.status.success() {
                    return Self::error_result(format!(
                        "log show failed: {}",
                        String::from_utf8_lossy(&output.stderr)
                    ));
                }

                let stdout = String::from_utf8_lossy(&output.stdout);
                let mut entries = Vec::new();
                let mut sanitized_count = 0;
                let mut count = 0;

                for line in stdout.lines() {
                    if count >= lines {
                        break;
                    }

                    if line.trim().is_empty() {
                        continue;
                    }

                    if let Some(f) = filter {
                        if !line.to_lowercase().contains(&f.to_lowercase()) {
                            continue;
                        }
                    }

                    let (sanitized, was_sanitized) = self.sanitize_line(line);
                    if was_sanitized {
                        sanitized_count += 1;
                    }

                    entries.push(self.parse_log_entry(&sanitized, subsystem));
                    count += 1;
                }

                Self::success_result(LogQueryResult {
                    lines: entries,
                    total_lines: stdout.lines().count() as i64,
                    log_source: "unified_log".to_string(),
                    sanitized: sanitized_count > 0,
                    sanitized_count,
                    start_time: String::new(),
                    end_time: String::new(),
                })
            }
            Err(e) => Self::error_result(format!("Failed to query macOS log: {e}")),
        }
    }

    /// Query system logs from /var/log (Linux/macOS)
    pub async fn get_system_logs(&self, params: &HashMap<String, String>) -> CommandResult {
        let log_file = params
            .get("file")
            .map(|s| s.as_str())
            .unwrap_or("/var/log/syslog");
        let lines = params
            .get("lines")
            .and_then(|s| s.parse().ok())
            .unwrap_or(100)
            .min(self.max_lines);
        #[allow(unused_variables)] // Used on Unix
        let filter = params.get("filter").map(|s| s.as_str());

        // Validate log file path is in whitelist
        if !self.is_allowed_log_path(log_file) {
            warn!(
                "[SECURITY] Blocked access to non-whitelisted log file: {}",
                log_file
            );
            return Self::error_result(format!(
                "Access denied: '{log_file}' is not in the allowed log paths. Allowed paths: {ALLOWED_LOG_PATHS:?}"
            ));
        }

        info!(
            "[AUDIT] SystemLogs query: file={}, lines={}",
            log_file, lines
        );

        #[cfg(unix)]
        {
            self.read_log_file(log_file, lines, filter).await
        }

        #[cfg(windows)]
        {
            Self::error_result(
                "System log file reading not supported on Windows. Use service_logs for Event Log."
                    .to_string(),
            )
        }
    }

    /// Check if a log path is in the allowed whitelist
    fn is_allowed_log_path(&self, path: &str) -> bool {
        use std::path::Path;

        // First check for obvious path traversal
        if path.contains("..") {
            return false;
        }

        // Try to canonicalize the path to resolve symlinks
        let canonical_path = match Path::new(path).canonicalize() {
            Ok(p) => p.to_string_lossy().to_string(),
            Err(_) => {
                // If file doesn't exist, use original path but be strict
                path.to_string()
            }
        };

        // Re-check for path traversal after canonicalization
        if canonical_path.contains("..") {
            return false;
        }

        for allowed in ALLOWED_LOG_PATHS {
            // For directory entries (ending with /), check if canonical path starts with it
            if allowed.ends_with('/') {
                if canonical_path.starts_with(allowed) {
                    return true;
                }
            } else {
                // For exact file paths, require exact match or be a file within that directory
                if canonical_path == *allowed
                    || canonical_path.starts_with(&format!("{}/", allowed.trim_end_matches('/')))
                {
                    return true;
                }
            }
        }
        false
    }

    /// Read log file on Unix systems
    #[cfg(unix)]
    async fn read_log_file(
        &self,
        file_path: &str,
        lines: u32,
        filter: Option<&str>,
    ) -> CommandResult {
        // Use tail to read last N lines
        match Command::new("tail")
            .args(["-n", &lines.to_string(), file_path])
            .output()
        {
            Ok(output) => {
                if !output.status.success() {
                    return Self::error_result(format!(
                        "Failed to read log file: {}",
                        String::from_utf8_lossy(&output.stderr)
                    ));
                }

                let stdout = String::from_utf8_lossy(&output.stdout);
                let mut entries = Vec::new();
                let mut sanitized_count = 0;

                for line in stdout.lines() {
                    if line.trim().is_empty() {
                        continue;
                    }

                    if let Some(f) = filter {
                        if !line.to_lowercase().contains(&f.to_lowercase()) {
                            continue;
                        }
                    }

                    let (sanitized, was_sanitized) = self.sanitize_line(line);
                    if was_sanitized {
                        sanitized_count += 1;
                    }

                    entries.push(self.parse_log_entry(&sanitized, file_path));
                }

                Self::success_result(LogQueryResult {
                    lines: entries,
                    total_lines: stdout.lines().count() as i64,
                    log_source: file_path.to_string(),
                    sanitized: sanitized_count > 0,
                    sanitized_count,
                    start_time: String::new(),
                    end_time: String::new(),
                })
            }
            Err(e) => Self::error_result(format!("Failed to read log file: {e}")),
        }
    }

    /// Query audit logs (Linux auditd)
    pub async fn get_audit_logs(&self, params: &HashMap<String, String>) -> CommandResult {
        let lines = params
            .get("lines")
            .and_then(|s| s.parse().ok())
            .unwrap_or(100)
            .min(self.max_lines);
        #[allow(unused_variables)]
        let since = params.get("since").map(|s| s.as_str());
        #[allow(unused_variables)]
        let filter = params.get("filter").map(|s| s.as_str());

        info!("[AUDIT] AuditLogs query: lines={}", lines);

        #[cfg(target_os = "linux")]
        {
            self.query_auditd(lines, since, filter).await
        }

        #[cfg(not(target_os = "linux"))]
        {
            Self::error_result("Audit logs are only available on Linux".to_string())
        }
    }

    /// Query auditd logs on Linux
    #[cfg(target_os = "linux")]
    async fn query_auditd(
        &self,
        lines: u32,
        since: Option<&str>,
        filter: Option<&str>,
    ) -> CommandResult {
        // First try ausearch, then fall back to reading /var/log/audit/audit.log
        let mut args = vec!["--input-logs".to_string()];

        if let Some(s) = since {
            args.push("--start".to_string());
            args.push(s.to_string());
        }

        match Command::new("ausearch").args(&args).output() {
            Ok(output) => {
                let stdout = if output.status.success() {
                    String::from_utf8_lossy(&output.stdout).to_string()
                } else {
                    // Fall back to reading audit.log directly
                    match Command::new("tail")
                        .args(["-n", &lines.to_string(), "/var/log/audit/audit.log"])
                        .output()
                    {
                        Ok(output) => String::from_utf8_lossy(&output.stdout).to_string(),
                        Err(e) => {
                            return Self::error_result(format!("Failed to read audit logs: {e}"));
                        }
                    }
                };

                let mut entries = Vec::new();
                let mut sanitized_count = 0;
                let mut count = 0;

                for line in stdout.lines() {
                    if count >= lines {
                        break;
                    }

                    if line.trim().is_empty() {
                        continue;
                    }

                    if let Some(f) = filter {
                        if !line.to_lowercase().contains(&f.to_lowercase()) {
                            continue;
                        }
                    }

                    let (sanitized, was_sanitized) = self.sanitize_line(line);
                    if was_sanitized {
                        sanitized_count += 1;
                    }

                    entries.push(self.parse_log_entry(&sanitized, "audit"));
                    count += 1;
                }

                Self::success_result(LogQueryResult {
                    lines: entries,
                    total_lines: stdout.lines().count() as i64,
                    log_source: "auditd".to_string(),
                    sanitized: sanitized_count > 0,
                    sanitized_count,
                    start_time: since.unwrap_or("").to_string(),
                    end_time: String::new(),
                })
            }
            Err(e) => Self::error_result(format!("Failed to query audit logs: {e}")),
        }
    }
}

impl Default for LogExecutor {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sanitize_password() {
        let executor = LogExecutor::new();
        let (result, was_sanitized) = executor.sanitize_line("password=secret123");
        assert!(was_sanitized);
        assert!(result.contains("REDACTED"));
        assert!(!result.contains("secret123"));
    }

    #[test]
    fn test_sanitize_bearer_token() {
        let executor = LogExecutor::new();
        let (result, was_sanitized) = executor.sanitize_line("Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U");
        assert!(was_sanitized);
        assert!(result.contains("REDACTED"));
    }

    #[test]
    fn test_sanitize_aws_key() {
        let executor = LogExecutor::new();
        let (result, was_sanitized) = executor.sanitize_line("Found key: AKIAIOSFODNN7EXAMPLE");
        assert!(was_sanitized);
        assert!(result.contains("REDACTED"));
    }

    #[test]
    fn test_allowed_log_paths() {
        let executor = LogExecutor::new();
        assert!(executor.is_allowed_log_path("/var/log/syslog"));
        assert!(executor.is_allowed_log_path("/var/log/nginx/access.log"));
        assert!(!executor.is_allowed_log_path("/etc/passwd"));
        assert!(!executor.is_allowed_log_path("/root/.ssh/id_rsa"));
    }
}
