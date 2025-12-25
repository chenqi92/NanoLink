//! User session collector
//!
//! Collects information about currently logged-in users across platforms.

use std::process::Command;
use std::time::Duration;

use crate::utils::safe_command::exec_with_timeout;

/// Session command timeout - 3 seconds (fast commands)
const SESSION_COMMAND_TIMEOUT: Duration = Duration::from_secs(3);

/// User session information
#[derive(Debug, Clone, Default)]
pub struct UserSession {
    pub username: String,
    pub tty: String,
    pub login_time: u64,
    pub remote_host: String,
    pub idle_seconds: u64,
    pub session_type: String,
}

/// Session collector
pub struct SessionCollector {
    last_collected: Vec<UserSession>,
}

impl SessionCollector {
    pub fn new() -> Self {
        Self {
            last_collected: Vec::new(),
        }
    }

    pub fn collect(&mut self) -> Vec<UserSession> {
        let sessions = self.collect_sessions();
        self.last_collected = sessions.clone();
        sessions
    }

    #[cfg(unix)]
    fn collect_sessions(&self) -> Vec<UserSession> {
        let mut sessions = Vec::new();

        // Use 'who' command to get login information
        let mut cmd = Command::new("who");
        cmd.arg("-u");

        if let Some(output) = exec_with_timeout(cmd, SESSION_COMMAND_TIMEOUT) {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                for line in stdout.lines() {
                    if let Some(session) = self.parse_who_line(line) {
                        sessions.push(session);
                    }
                }
            }
        }

        // Fallback to basic 'who' if -u flag not supported (macOS)
        if sessions.is_empty() {
            let mut cmd = Command::new("who");
            if let Some(output) = exec_with_timeout(cmd, SESSION_COMMAND_TIMEOUT) {
                if output.status.success() {
                    let stdout = String::from_utf8_lossy(&output.stdout);
                    for line in stdout.lines() {
                        if let Some(session) = self.parse_who_line_basic(line) {
                            sessions.push(session);
                        }
                    }
                }
            }
        }

        sessions
    }

    #[cfg(unix)]
    fn parse_who_line(&self, line: &str) -> Option<UserSession> {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 4 {
            return None;
        }

        let username = parts[0].to_string();
        let tty = parts[1].to_string();

        let login_time = if parts.len() >= 4 {
            self.parse_datetime(parts[2], parts[3])
        } else {
            0
        };

        let idle_seconds = if parts.len() >= 5 {
            self.parse_idle_time(parts[4])
        } else {
            0
        };

        let remote_host = self.extract_remote_host(line);
        let session_type = self.determine_session_type(&tty, &remote_host);

        Some(UserSession {
            username,
            tty,
            login_time,
            remote_host,
            idle_seconds,
            session_type,
        })
    }

    #[cfg(unix)]
    fn parse_who_line_basic(&self, line: &str) -> Option<UserSession> {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 4 {
            return None;
        }

        let username = parts[0].to_string();
        let tty = parts[1].to_string();

        let login_time = if parts.len() >= 5 {
            self.parse_datetime_basic(parts[2], parts[3], parts[4])
        } else {
            0
        };

        let remote_host = self.extract_remote_host(line);
        let session_type = self.determine_session_type(&tty, &remote_host);

        Some(UserSession {
            username,
            tty,
            login_time,
            remote_host,
            idle_seconds: 0,
            session_type,
        })
    }

    #[cfg(windows)]
    fn collect_sessions(&self) -> Vec<UserSession> {
        let mut sessions = Vec::new();

        let mut cmd = Command::new("query");
        cmd.arg("user");

        if let Some(output) = exec_with_timeout(cmd, SESSION_COMMAND_TIMEOUT) {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                for line in stdout.lines().skip(1) {
                    if let Some(session) = self.parse_query_user_line(line) {
                        sessions.push(session);
                    }
                }
            }
        }

        sessions
    }

    #[cfg(windows)]
    #[allow(clippy::unused_self)]
    fn parse_query_user_line(&self, line: &str) -> Option<UserSession> {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 6 {
            return None;
        }

        let username = parts[0].trim_start_matches('>').to_string();
        let tty = parts[1].to_string();
        let state = parts[3].to_lowercase();

        if state != "active" {
            return None;
        }

        let idle_seconds = if parts[4] == "none" || parts[4] == "." {
            0
        } else {
            self.parse_windows_idle_time(parts[4])
        };

        let session_type = if tty.to_lowercase().contains("rdp") {
            "rdp".to_string()
        } else if tty.to_lowercase() == "console" {
            "console".to_string()
        } else {
            "local".to_string()
        };

        Some(UserSession {
            username,
            tty,
            login_time: 0,
            remote_host: String::new(),
            idle_seconds,
            session_type,
        })
    }

    #[cfg(unix)]
    fn parse_datetime(&self, date_str: &str, time_str: &str) -> u64 {
        use std::time::{SystemTime, UNIX_EPOCH};

        let datetime_str = format!("{} {}", date_str, time_str);

        if datetime_str.contains('-') {
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0)
        } else {
            0
        }
    }

    #[cfg(unix)]
    #[allow(clippy::unused_self)]
    fn parse_datetime_basic(&self, _month: &str, _day: &str, _time: &str) -> u64 {
        use std::time::{SystemTime, UNIX_EPOCH};

        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0)
    }

    #[cfg(unix)]
    #[allow(clippy::unused_self)]
    fn parse_idle_time(&self, idle_str: &str) -> u64 {
        if idle_str == "." || idle_str == "old" {
            return 0;
        }

        let parts: Vec<&str> = idle_str.split(':').collect();
        if parts.len() == 2 {
            let hours: u64 = parts[0].parse().unwrap_or(0);
            let minutes: u64 = parts[1].parse().unwrap_or(0);
            return hours * 3600 + minutes * 60;
        }

        0
    }

    #[cfg(windows)]
    #[allow(clippy::unused_self)]
    fn parse_windows_idle_time(&self, idle_str: &str) -> u64 {
        if idle_str == "none" || idle_str == "." {
            return 0;
        }

        if idle_str.contains(':') {
            let parts: Vec<&str> = idle_str.split(':').collect();
            if parts.len() == 2 {
                let hours: u64 = parts[0].parse().unwrap_or(0);
                let minutes: u64 = parts[1].parse().unwrap_or(0);
                return hours * 3600 + minutes * 60;
            }
        } else {
            let minutes: u64 = idle_str.parse().unwrap_or(0);
            return minutes * 60;
        }

        0
    }

    #[cfg(unix)]
    fn extract_remote_host(&self, line: &str) -> String {
        if let Some(start) = line.rfind('(') {
            if let Some(end) = line.rfind(')') {
                if start < end {
                    return line[start + 1..end].to_string();
                }
            }
        }
        String::new()
    }

    #[cfg(unix)]
    #[allow(clippy::unused_self)]
    fn determine_session_type(&self, tty: &str, remote_host: &str) -> String {
        if !remote_host.is_empty() {
            "ssh".to_string()
        } else if tty.starts_with("pts") || tty.starts_with("tty") {
            if tty.contains("pts") {
                "pty".to_string()
            } else {
                "console".to_string()
            }
        } else if tty == "console" {
            "console".to_string()
        } else {
            "local".to_string()
        }
    }
}

impl Default for SessionCollector {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_session_collector_new() {
        let collector = SessionCollector::new();
        assert!(collector.last_collected.is_empty());
    }

    #[test]
    fn test_collect_sessions() {
        let mut collector = SessionCollector::new();
        let sessions = collector.collect();
        println!("Found {} sessions", sessions.len());
        for session in &sessions {
            println!(
                "  User: {}, TTY: {}, Type: {}",
                session.username, session.tty, session.session_type
            );
        }
    }
}
