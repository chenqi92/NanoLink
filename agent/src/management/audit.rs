//! Audit logging for Management API
//!
//! Records all API calls in JSON Lines format with automatic log rotation.

use std::fs::{File, OpenOptions};
use std::io::{BufWriter, Write};
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};

use axum::{
    body::Body,
    extract::{ConnectInfo, State},
    http::Request,
    middleware::Next,
    response::Response,
};
use chrono::Utc;
use serde::Serialize;
use tokio::sync::RwLock;
use tracing::{error, info};

use crate::config::AuditConfig;

/// Audit log entry in JSON format
#[derive(Debug, Serialize)]
pub struct AuditLogEntry {
    /// Timestamp in RFC3339 format
    pub ts: String,
    /// Source IP address
    pub ip: String,
    /// API endpoint path
    pub endpoint: String,
    /// HTTP method
    pub method: String,
    /// Token (masked, first 3 + last 3 chars)
    pub token: String,
    /// Permission level (if authenticated)
    pub permission: Option<u8>,
    /// HTTP status code
    pub status: u16,
    /// Request duration in milliseconds
    pub duration_ms: u64,
}

/// State for audit logging
pub struct AuditState {
    config: AuditConfig,
    log_path: PathBuf,
    writer: RwLock<Option<BufWriter<File>>>,
    current_size: RwLock<u64>,
}

impl AuditState {
    pub fn new(config: AuditConfig) -> Self {
        let log_path = Self::get_log_path();

        let writer = if config.enabled {
            Self::open_log_file(&log_path).ok().map(BufWriter::new)
        } else {
            None
        };

        let current_size = writer
            .as_ref()
            .and_then(|_| std::fs::metadata(&log_path).ok())
            .map(|m| m.len())
            .unwrap_or(0);

        Self {
            config,
            log_path,
            writer: RwLock::new(writer),
            current_size: RwLock::new(current_size),
        }
    }

    fn get_log_path() -> PathBuf {
        #[cfg(windows)]
        {
            let base =
                std::env::var("ProgramData").unwrap_or_else(|_| "C:\\ProgramData".to_string());
            PathBuf::from(base)
                .join("nanolink")
                .join("logs")
                .join("audit.log")
        }
        #[cfg(unix)]
        {
            PathBuf::from("/var/log/nanolink/audit.log")
        }
    }

    fn open_log_file(path: &PathBuf) -> std::io::Result<File> {
        // Ensure directory exists
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        OpenOptions::new().create(true).append(true).open(path)
    }

    pub async fn write_entry(&self, entry: &AuditLogEntry) {
        if !self.config.enabled {
            return;
        }

        let json = match serde_json::to_string(entry) {
            Ok(j) => j,
            Err(e) => {
                error!("Failed to serialize audit log entry: {}", e);
                return;
            }
        };

        let line = format!("{json}\n");
        let line_len = line.len() as u64;

        let mut writer_guard = self.writer.write().await;
        let mut size_guard = self.current_size.write().await;

        // Check if we need to rotate
        if *size_guard + line_len > self.config.max_size_mb as u64 * 1024 * 1024 {
            if let Some(ref mut w) = *writer_guard {
                let _ = w.flush();
            }
            *writer_guard = None;

            // Rotate the log file
            self.rotate_logs().await;

            // Open new log file
            if let Ok(file) = Self::open_log_file(&self.log_path) {
                *writer_guard = Some(BufWriter::new(file));
                *size_guard = 0;
            }
        }

        // Write the entry
        if let Some(ref mut w) = *writer_guard {
            if let Err(e) = w.write_all(line.as_bytes()) {
                error!("Failed to write audit log: {}", e);
            } else {
                *size_guard += line_len;
                // SECURITY: Flush immediately to ensure audit entries are persisted
                // This prevents data loss if the process crashes
                if let Err(e) = w.flush() {
                    error!("Failed to flush audit log: {}", e);
                }
            }
        }
    }

    async fn rotate_logs(&self) {
        let log_path = self.log_path.clone();
        let max_files = self.config.max_files;

        // Use spawn_blocking to avoid blocking the async runtime
        let _ = tokio::task::spawn_blocking(move || {
            // Shift existing log files
            for i in (1..max_files).rev() {
                let old_path = log_path.with_extension(format!("log.{i}"));
                let new_path = log_path.with_extension(format!("log.{}", i + 1));
                let _ = std::fs::rename(&old_path, &new_path);
            }

            // Rename current log to .1
            let rotated_path = log_path.with_extension("log.1");
            let _ = std::fs::rename(&log_path, &rotated_path);

            // Delete old files beyond max_files
            let oldest = log_path.with_extension(format!("log.{max_files}"));
            let _ = std::fs::remove_file(&oldest);
        })
        .await;

        info!("Audit log rotated");
    }

    #[allow(dead_code)]
    pub async fn flush(&self) {
        let mut writer_guard = self.writer.write().await;
        if let Some(ref mut w) = *writer_guard {
            let _ = w.flush();
        }
    }
}

/// Mask a token for logging (show first 3 and last 3 chars)
fn mask_token(token: &str) -> String {
    if token.len() <= 8 {
        "***".to_string()
    } else {
        format!("{}***{}", &token[..3], &token[token.len() - 3..])
    }
}

/// Audit logging middleware
pub async fn audit_middleware(
    State(state): State<Arc<AuditState>>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    request: Request<Body>,
    next: Next,
) -> Response {
    if !state.config.enabled {
        return next.run(request).await;
    }

    let start = Instant::now();
    let method = request.method().to_string();
    let path = request.uri().path().to_string();
    let source_ip = addr.ip().to_string();

    // Extract token from Authorization header
    let token = request
        .headers()
        .get("Authorization")
        .and_then(|v| v.to_str().ok())
        .and_then(|h| h.strip_prefix("Bearer "))
        .map(mask_token)
        .unwrap_or_else(|| "-".to_string());

    // Run the actual request
    let response = next.run(request).await;

    let duration = start.elapsed();
    let status = response.status().as_u16();

    // Create audit log entry
    let entry = AuditLogEntry {
        ts: Utc::now().to_rfc3339(),
        ip: source_ip,
        endpoint: path,
        method,
        token,
        permission: None, // Would need to be passed from auth middleware
        status,
        duration_ms: duration.as_millis() as u64,
    };

    // Write asynchronously
    state.write_entry(&entry).await;

    response
}

/// Cleanup old audit logs based on max_age_days
#[allow(dead_code)]
pub async fn cleanup_old_logs(config: &AuditConfig) {
    if !config.enabled {
        return;
    }

    let log_dir = AuditState::get_log_path().parent().map(|p| p.to_path_buf());

    if let Some(dir) = log_dir {
        if let Ok(entries) = std::fs::read_dir(&dir) {
            let max_age = Duration::from_secs(config.max_age_days as u64 * 24 * 60 * 60);
            let now = std::time::SystemTime::now();

            for entry in entries.flatten() {
                // SECURITY: Only delete files matching audit log pattern
                let file_name = entry.file_name();
                let name_str = file_name.to_string_lossy();
                if !name_str.starts_with("audit.log") {
                    continue;
                }

                if let Ok(metadata) = entry.metadata() {
                    if let Ok(modified) = metadata.modified() {
                        if let Ok(age) = now.duration_since(modified) {
                            if age > max_age {
                                let _ = std::fs::remove_file(entry.path());
                                info!("Removed old audit log: {:?}", entry.path());
                            }
                        }
                    }
                }
            }
        }
    }
}
