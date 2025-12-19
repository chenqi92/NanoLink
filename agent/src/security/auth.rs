use std::sync::Arc;

use crate::config::Config;

/// Permission levels
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum PermissionLevel {
    /// Read-only access - can only view metrics
    ReadOnly = 0,
    /// Basic write - can download logs, clear temp files
    BasicWrite = 1,
    /// Service control - can restart services, containers, kill processes
    ServiceControl = 2,
    /// System admin - full access including reboot and shell commands
    SystemAdmin = 3,
}

impl From<u8> for PermissionLevel {
    fn from(level: u8) -> Self {
        match level {
            0 => PermissionLevel::ReadOnly,
            1 => PermissionLevel::BasicWrite,
            2 => PermissionLevel::ServiceControl,
            3 => PermissionLevel::SystemAdmin,
            _ => PermissionLevel::ReadOnly,
        }
    }
}

impl From<i32> for PermissionLevel {
    fn from(level: i32) -> Self {
        Self::from(level.max(0).min(3) as u8)
    }
}

/// Authenticator for validating tokens
pub struct Authenticator {
    config: Arc<Config>,
}

impl Authenticator {
    /// Create a new authenticator
    pub fn new(config: Arc<Config>) -> Self {
        Self { config }
    }

    /// Validate a token and return the permission level
    pub fn validate_token(&self, token: &str) -> Option<PermissionLevel> {
        // Find matching server config
        for server in &self.config.servers {
            if server.token == token {
                return Some(PermissionLevel::from(server.permission));
            }
        }
        None
    }

    /// Validate super token for shell commands
    pub fn validate_super_token(&self, super_token: &str) -> bool {
        if !self.config.shell.enabled {
            return false;
        }

        self.config
            .shell
            .super_token
            .as_ref()
            .map(|t| t == super_token)
            .unwrap_or(false)
    }
}
