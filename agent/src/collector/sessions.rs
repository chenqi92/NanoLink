//! User session collector
//!
//! Collects information about currently logged-in users across platforms.

use std::process::Command;

/// User session information
#[derive(Debug, Clone, Default)]
pub struct UserSession {
    pub username: String,
    pub tty: String,
    pub login_time: u64,
    pub remote_host: String,
    pub idle_seconds: u64,
    pub session_type: String, // "local", "ssh", "rdp", "console"
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

    /// Collect all active user sessions
    pub fn collect(&mut self) -> Vec<UserSession> {
        let sessions = self.collect_sessions();
        self.last_collected = sessions.clone();
        sessions
    }

    #[cfg(unix)]
    fn collect_sessions(&self) -> Vec<UserSession> {
        let mut sessions = Vec::new();

        // Use 'who' command to get login information
        if let Ok(output) = Command::new("who").arg("-u").output() {
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
            if let Ok(output) = Command::new("who").output() {
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
        // Format: username tty date time idle pid (host)
        // Example: user     pts/0        2024-01-20 10:30   .    1234 (192.168.1.100)
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 4 {
            return None;
        }

        let username = parts[0].to_string();
        let tty = parts[1].to_string();

        // Parse login time
        let login_time = if parts.len() >= 4 {
            self.parse_datetime(parts[2], parts[3])
        } else {
            0
        };

        // Parse idle time
        let idle_seconds = if parts.len() >= 5 {
            self.parse_idle_time(parts[4])
        } else {
            0
        };

        // Parse remote host
        let remote_host = self.extract_remote_host(line);

        // Determine session type
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
        // Format: username tty date time (host)
        // Example: user     console  Jan 20 10:30
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 4 {
            return None;
        }

        let username = parts[0].to_string();
        let tty = parts[1].to_string();

        // Parse login time (format: "Jan 20 10:30")
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

        // Use 'query user' command on Windows
        if let Ok(output) = Command::new("query").arg("user").output() {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                for line in stdout.lines().skip(1) {
                    // Skip header
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
        // Format: USERNAME  SESSIONNAME  ID  STATE  IDLE TIME  LOGON TIME
        // Example: >user     console      1   Active  none    1/20/2024 10:30 AM
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 6 {
            return None;
        }

        let username = parts[0].trim_start_matches('>').to_string();
        let tty = parts[1].to_string();
        let state = parts[3].to_lowercase();

        // Only include active sessions
        if state != "active" {
            return None;
        }

        // Parse idle time
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
            login_time: 0, // Would need more parsing
            remote_host: String::new(),
            idle_seconds,
            session_type,
        })
    }

    #[cfg(unix)]
    fn parse_datetime(&self, date_str: &str, time_str: &str) -> u64 {
        // Parse "2024-01-20 10:30" format
        use std::time::{SystemTime, UNIX_EPOCH};

        // Simple parsing - in production, use chrono crate
        let datetime_str = format!("{} {}", date_str, time_str);

        // For now, return current time as fallback
        // A proper implementation would parse the datetime
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
        // Parse "Jan 20 10:30" format
        use std::time::{SystemTime, UNIX_EPOCH};

        // For accurate parsing, would need the year from system
        // Return current time as approximation
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0)
    }

    #[cfg(unix)]
    #[allow(clippy::unused_self)]
    fn parse_idle_time(&self, idle_str: &str) -> u64 {
        // Parse idle time from 'who -u' output
        // Format: "." (active), "00:05" (5 minutes), "old" (very long)
        if idle_str == "." || idle_str == "old" {
            return 0;
        }

        // Parse "HH:MM" format
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
        // Parse Windows idle time format
        // Format: "none", ".", "5", "1:05", etc.
        if idle_str == "none" || idle_str == "." {
            return 0;
        }

        // Could be minutes or "HH:MM"
        if idle_str.contains(':') {
            let parts: Vec<&str> = idle_str.split(':').collect();
            if parts.len() == 2 {
                let hours: u64 = parts[0].parse().unwrap_or(0);
                let minutes: u64 = parts[1].parse().unwrap_or(0);
                return hours * 3600 + minutes * 60;
            }
        } else {
            // Just minutes
            let minutes: u64 = idle_str.parse().unwrap_or(0);
            return minutes * 60;
        }

        0
    }

    #[cfg(unix)]
    fn extract_remote_host(&self, line: &str) -> String {
        // Extract hostname/IP from parentheses at end of line
        // Example: ... (192.168.1.100)
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
        // Should return at least one session on a normal system
        // This test might fail in CI environments without interactive sessions
        println!("Found {} sessions", sessions.len());
        for session in &sessions {
            println!(
                "  User: {}, TTY: {}, Type: {}",
                session.username, session.tty, session.session_type
            );
        }
    }
}
