use std::sync::Arc;

use lazy_static::lazy_static;
use regex::Regex;
use subtle::ConstantTimeEq;
use tracing::warn;

use crate::config::Config;
use crate::proto::CommandType;

/// 常量时间字符串比较，防止时序攻击
fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    a.ct_eq(b).into()
}

/// Permission checker for commands
pub struct PermissionChecker {
    config: Arc<Config>,
}

impl PermissionChecker {
    /// Create a new permission checker
    pub fn new(config: Arc<Config>) -> Self {
        Self { config }
    }

    /// Check if a command type is allowed at the given permission level
    pub fn check_permission(&self, command_type: CommandType, permission_level: u8) -> bool {
        let required = self.required_level(command_type);
        permission_level >= required
    }

    /// Get the required permission level for a command type
    pub fn required_level(&self, command_type: CommandType) -> u8 {
        match command_type {
            // Read-only operations (level 0)
            CommandType::ProcessList => 0,
            CommandType::ServiceStatus => 0,
            CommandType::DockerList => 0,
            CommandType::FileTail => 0,

            // Basic write operations (level 1)
            CommandType::FileDownload => 1,
            CommandType::FileTruncate => 1,
            CommandType::DockerLogs => 1,

            // Service control operations (level 2)
            CommandType::ProcessKill => 2,
            CommandType::ServiceStart => 2,
            CommandType::ServiceStop => 2,
            CommandType::ServiceRestart => 2,
            CommandType::DockerStart => 2,
            CommandType::DockerStop => 2,
            CommandType::DockerRestart => 2,
            CommandType::FileUpload => 2,

            // System admin operations (level 3)
            CommandType::SystemReboot => 3,
            CommandType::ShellExecute => 3,

            // Unknown commands require highest level
            _ => 3,
        }
    }

    /// Check if a shell command is allowed (P0-2 增强版本)
    pub fn check_shell_command(&self, command: &str, super_token: &str) -> Result<(), String> {
        // Check if shell is enabled
        if !self.config.shell.enabled {
            return Err("Shell commands are disabled".to_string());
        }

        // Validate super token using constant-time comparison
        let valid_token = self
            .config
            .shell
            .super_token
            .as_ref()
            .map(|t| constant_time_eq(t.as_bytes(), super_token.as_bytes()))
            .unwrap_or(false);

        if !valid_token {
            return Err("Invalid super token".to_string());
        }

        // P0-2: 规范化命令字符串
        let normalized = Self::normalize_command(command);

        // P0-2: 检测危险模式 (正则表达式)
        if let Some(pattern) = Self::contains_dangerous_pattern(&normalized) {
            warn!(
                "[SECURITY] Dangerous pattern detected in command: {}",
                command
            );
            return Err(format!(
                "Command blocked: dangerous pattern detected ({})",
                pattern
            ));
        }

        // P0-2: 检测命令注入
        if Self::detect_command_injection(command) {
            warn!("[SECURITY] Command injection attempt: {}", command);
            return Err("Command blocked: potential command injection detected".to_string());
        }

        // Check blacklist (both original and normalized)
        for pattern in &self.config.shell.blacklist {
            if command.contains(pattern) || normalized.contains(pattern) {
                return Err(format!("Command contains blacklisted pattern: {}", pattern));
            }
        }

        // Check whitelist (if not empty, command must match at least one pattern)
        if !self.config.shell.whitelist.is_empty() {
            let matched = self
                .config
                .shell
                .whitelist
                .iter()
                .any(|p| Self::matches_pattern(&p.pattern, command));

            if !matched {
                return Err("Command not in whitelist".to_string());
            }
        }

        Ok(())
    }

    /// 规范化命令字符串，移除可能用于绕过检测的字符
    fn normalize_command(command: &str) -> String {
        command
            .replace(['\\', '\'', '"'], "") // 移除反斜杠、单引号、双引号
            .split_whitespace() // 规范化空格
            .collect::<Vec<_>>()
            .join(" ")
    }

    /// 使用正则表达式检测危险模式，返回匹配的模式名称
    fn contains_dangerous_pattern(command: &str) -> Option<&'static str> {
        lazy_static! {
            static ref DANGEROUS_PATTERNS: Vec<(Regex, &'static str)> = vec![
                // 破坏性命令
                (Regex::new(r"\brm\s+(-[rfv]+\s+)*[/\*]").unwrap(), "rm with root/wildcard"),
                (Regex::new(r"\bmkfs\b").unwrap(), "mkfs"),
                (Regex::new(r"\bdd\s+if=").unwrap(), "dd"),
                (Regex::new(r">\s*/dev/(sd|hd|nvme|vd)").unwrap(), "write to device"),

                // 权限提升
                (Regex::new(r"\bchmod\s+[0-7]*777").unwrap(), "chmod 777"),
                (Regex::new(r"\bchown\s+root").unwrap(), "chown root"),

                // 网络后门/反向shell
                (Regex::new(r"\bnc\s+-[el]").unwrap(), "netcat listener/exec"),
                (Regex::new(r"\bbash\s+-i\s+>&").unwrap(), "bash reverse shell"),
                (Regex::new(r"/dev/tcp/").unwrap(), "bash network redirection"),
                (Regex::new(r"python.*-c.*socket").unwrap(), "python socket"),
                (Regex::new(r"perl.*-e.*socket").unwrap(), "perl socket"),

                // 敏感文件访问
                (Regex::new(r"\bcat\s+.*/(etc/(shadow|sudoers)|\.ssh/)").unwrap(), "sensitive file read"),

                // Fork炸弹和相关
                (Regex::new(r":\s*\(\s*\)\s*\{").unwrap(), "fork bomb pattern"),
                (Regex::new(r"\bwhile\s+true\s*;?\s*do").unwrap(), "infinite loop"),
                (Regex::new(r"\bfor\s*\(\s*;\s*;\s*\)").unwrap(), "infinite for loop"),
            ];
        }

        for (regex, name) in DANGEROUS_PATTERNS.iter() {
            if regex.is_match(command) {
                return Some(name);
            }
        }
        None
    }

    /// 检测命令注入尝试
    fn detect_command_injection(command: &str) -> bool {
        // 命令替换 $(...) 或 `...`
        if command.contains("$(") || command.contains('`') {
            return true;
        }

        // 管道到危险解释器
        if command.contains('|') {
            let parts: Vec<&str> = command.split('|').collect();
            for part in parts.iter().skip(1) {
                let trimmed = part.trim();
                if trimmed.starts_with("sh")
                    || trimmed.starts_with("bash")
                    || trimmed.starts_with("python")
                    || trimmed.starts_with("perl")
                    || trimmed.starts_with("ruby")
                    || trimmed.starts_with("node")
                    || trimmed.starts_with("php")
                {
                    return true;
                }
            }
        }

        // base64编码执行
        if command.contains("base64") && (command.contains("-d") || command.contains("--decode")) {
            if command.contains('|') {
                return true;
            }
        }

        // eval执行
        if command.contains("eval ") || command.contains("eval\t") {
            return true;
        }

        false
    }

    /// Check if a command matches a pattern (supports * wildcard)
    fn matches_pattern(pattern: &str, command: &str) -> bool {
        // Simple wildcard matching
        if pattern == "*" {
            return true;
        }

        let parts: Vec<&str> = pattern.split('*').collect();

        if parts.len() == 1 {
            // No wildcard
            return pattern == command;
        }

        let mut pos = 0;
        for (i, part) in parts.iter().enumerate() {
            if part.is_empty() {
                continue;
            }

            if i == 0 {
                // Must start with first part
                if !command.starts_with(part) {
                    return false;
                }
                pos = part.len();
            } else if i == parts.len() - 1 {
                // Must end with last part
                if !command.ends_with(part) {
                    return false;
                }
            } else {
                // Must contain middle parts
                if let Some(found_pos) = command[pos..].find(part) {
                    pos += found_pos + part.len();
                } else {
                    return false;
                }
            }
        }

        true
    }

    /// Check if a command requires confirmation
    pub fn requires_confirmation(&self, command: &str) -> bool {
        self.config
            .shell
            .require_confirmation
            .iter()
            .any(|p| Self::matches_pattern(&p.pattern, command))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pattern_matching() {
        // Exact match
        assert!(PermissionChecker::matches_pattern("df -h", "df -h"));
        assert!(!PermissionChecker::matches_pattern("df -h", "df -m"));

        // Wildcard at end
        assert!(PermissionChecker::matches_pattern(
            "tail -n *",
            "tail -n 100"
        ));
        assert!(PermissionChecker::matches_pattern(
            "tail -n *",
            "tail -n 50"
        ));

        // Wildcard in middle
        assert!(PermissionChecker::matches_pattern(
            "tail -n * /var/log/*.log",
            "tail -n 100 /var/log/app.log"
        ));

        // Wildcard everywhere
        assert!(PermissionChecker::matches_pattern("*", "anything"));
    }
}
