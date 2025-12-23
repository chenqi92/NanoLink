use std::sync::Arc;

use subtle::ConstantTimeEq;

use crate::config::Config;

/// 常量时间字符串比较，防止时序攻击
#[allow(dead_code)]
fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    a.ct_eq(b).into()
}

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
        Self::from(level.clamp(0, 3) as u8)
    }
}

/// Authenticator for validating tokens
#[allow(dead_code)]
pub struct Authenticator {
    config: Arc<Config>,
}

#[allow(dead_code)]
impl Authenticator {
    /// Create a new authenticator
    pub fn new(config: Arc<Config>) -> Self {
        Self { config }
    }

    /// Validate a token and return the permission level
    /// Uses constant-time comparison to prevent timing attacks
    pub fn validate_token(&self, token: &str) -> Option<PermissionLevel> {
        // Find matching server config using constant-time comparison
        for server in &self.config.servers {
            if constant_time_eq(server.token.as_bytes(), token.as_bytes()) {
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

        // Use constant-time comparison to prevent timing attacks
        self.config
            .shell
            .super_token
            .as_ref()
            .map(|t| constant_time_eq(t.as_bytes(), super_token.as_bytes()))
            .unwrap_or(false)
    }
}
