use std::sync::Arc;

use crate::config::Config;
use crate::proto::CommandType;

use super::auth::PermissionLevel;

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

    /// Check if a shell command is allowed
    pub fn check_shell_command(&self, command: &str, super_token: &str) -> Result<(), String> {
        // Check if shell is enabled
        if !self.config.shell.enabled {
            return Err("Shell commands are disabled".to_string());
        }

        // Validate super token
        let valid_token = self
            .config
            .shell
            .super_token
            .as_ref()
            .map(|t| t == super_token)
            .unwrap_or(false);

        if !valid_token {
            return Err("Invalid super token".to_string());
        }

        // Check blacklist first
        for pattern in &self.config.shell.blacklist {
            if command.contains(pattern) {
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
        assert!(PermissionChecker::matches_pattern("tail -n *", "tail -n 100"));
        assert!(PermissionChecker::matches_pattern("tail -n *", "tail -n 50"));

        // Wildcard in middle
        assert!(PermissionChecker::matches_pattern(
            "tail -n * /var/log/*.log",
            "tail -n 100 /var/log/app.log"
        ));

        // Wildcard everywhere
        assert!(PermissionChecker::matches_pattern("*", "anything"));
    }
}
