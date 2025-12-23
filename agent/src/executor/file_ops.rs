use std::fs::{self, File, OpenOptions};
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use glob::Pattern;
use tracing::{info, warn};

use crate::config::Config;
use crate::proto::CommandResult;

/// File operations executor with security checks
pub struct FileExecutor {
    config: Arc<Config>,
}

impl FileExecutor {
    /// Create a new file executor with config
    pub fn new(config: Arc<Config>) -> Self {
        Self { config }
    }

    /// Validate and sanitize a file path according to security config
    /// Returns the canonicalized path if valid, or an error message
    fn validate_path(&self, path_str: &str) -> Result<PathBuf, String> {
        let path = Path::new(path_str);

        // Check for path traversal attempts if protection is enabled
        if self.config.security.path_traversal_protection {
            let path_str_normalized = path_str.replace('\\', "/");
            if path_str_normalized.contains("..") {
                warn!("[AUDIT] Path traversal attempt blocked: {}", path_str);
                return Err("Path traversal detected: '..' is not allowed".to_string());
            }
        }

        // Try to canonicalize the path (resolves symlinks and ..)
        // For non-existent files, we canonicalize the parent directory
        let canonical = if path.exists() {
            path.canonicalize()
                .map_err(|e| format!("Failed to resolve path: {e}"))?
        } else {
            // For new files, check the parent directory
            if let Some(parent) = path.parent() {
                if parent.as_os_str().is_empty() {
                    // Relative path in current directory
                    std::env::current_dir()
                        .map_err(|e| format!("Failed to get current directory: {e}"))?
                        .join(path.file_name().ok_or("Invalid filename")?)
                } else if parent.exists() {
                    parent
                        .canonicalize()
                        .map_err(|e| format!("Failed to resolve parent path: {e}"))?
                        .join(path.file_name().ok_or("Invalid filename")?)
                } else {
                    return Err(format!(
                        "Parent directory does not exist: {}",
                        parent.display()
                    ));
                }
            } else {
                return Err("Invalid path".to_string());
            }
        };

        let canonical_str = canonical.to_string_lossy().to_string();

        // Check denied paths first (always blocked)
        for denied in &self.config.security.denied_paths {
            // Support glob patterns
            if let Ok(pattern) = Pattern::new(denied) {
                if pattern.matches(&canonical_str) {
                    warn!(
                        "[AUDIT] Access to denied path blocked: {} (matched pattern: {})",
                        canonical_str, denied
                    );
                    return Err(format!(
                        "Access denied: path matches blocked pattern '{denied}'"
                    ));
                }
            }
            // Also check prefix match for directory paths
            if canonical_str.starts_with(denied) {
                warn!(
                    "[AUDIT] Access to denied path blocked: {} (prefix: {})",
                    canonical_str, denied
                );
                return Err(format!(
                    "Access denied: path is within restricted directory '{denied}'"
                ));
            }
        }

        // Check allowed paths (if list is not empty)
        if !self.config.security.allowed_paths.is_empty() {
            let is_allowed = self.config.security.allowed_paths.iter().any(|allowed| {
                // Check prefix match
                if canonical_str.starts_with(allowed) {
                    return true;
                }
                // Check glob pattern
                if let Ok(pattern) = Pattern::new(allowed) {
                    if pattern.matches(&canonical_str) {
                        return true;
                    }
                }
                false
            });

            if !is_allowed {
                warn!("[AUDIT] Path not in allowed list: {}", canonical_str);
                return Err("Path not in allowed list".to_string());
            }
        }

        info!("[AUDIT] Path validated: {}", canonical_str);
        Ok(canonical)
    }

    /// Helper to create an error CommandResult
    fn error_result(error: String) -> CommandResult {
        CommandResult {
            command_id: String::new(),
            success: false,
            output: String::new(),
            error,
            file_content: vec![],
            processes: vec![],
            containers: vec![],
        }
    }

    /// Read the tail of a file
    pub async fn tail_file(&self, path: &str, lines: usize) -> CommandResult {
        // Validate path first
        let validated_path = match self.validate_path(path) {
            Ok(p) => p,
            Err(e) => return Self::error_result(e),
        };

        if !validated_path.exists() {
            return Self::error_result(format!("File not found: {}", validated_path.display()));
        }

        info!(
            "[AUDIT] FileTail: {} (last {} lines)",
            validated_path.display(),
            lines
        );

        match File::open(&validated_path) {
            Ok(file) => {
                let reader = BufReader::new(file);
                let all_lines: Vec<String> = reader.lines().filter_map(|l| l.ok()).collect();

                let start = if all_lines.len() > lines {
                    all_lines.len() - lines
                } else {
                    0
                };

                let output = all_lines[start..].join("\n");

                CommandResult {
                    command_id: String::new(),
                    success: true,
                    output,
                    error: String::new(),
                    file_content: vec![],
                    processes: vec![],
                    containers: vec![],
                }
            }
            Err(e) => Self::error_result(format!("Failed to read file: {e}")),
        }
    }

    /// Download a file (read full content)
    pub async fn download_file(&self, path: &str) -> CommandResult {
        // Validate path first
        let validated_path = match self.validate_path(path) {
            Ok(p) => p,
            Err(e) => return Self::error_result(e),
        };

        if !validated_path.exists() {
            return Self::error_result(format!("File not found: {}", validated_path.display()));
        }

        // Check file size using config limit
        let metadata = match fs::metadata(&validated_path) {
            Ok(m) => m,
            Err(e) => return Self::error_result(format!("Failed to read file metadata: {e}")),
        };

        let max_size = self.config.security.max_file_size;
        if metadata.len() > max_size {
            warn!(
                "[AUDIT] FileDownload blocked - file too large: {} ({} bytes > {} bytes limit)",
                validated_path.display(),
                metadata.len(),
                max_size
            );
            return Self::error_result(format!(
                "File too large ({}MB). Maximum allowed: {}MB",
                metadata.len() / 1024 / 1024,
                max_size / 1024 / 1024
            ));
        }

        info!(
            "[AUDIT] FileDownload: {} ({} bytes)",
            validated_path.display(),
            metadata.len()
        );

        match fs::read(&validated_path) {
            Ok(content) => CommandResult {
                command_id: String::new(),
                success: true,
                output: format!("Downloaded {} bytes", content.len()),
                error: String::new(),
                file_content: content,
                processes: vec![],
                containers: vec![],
            },
            Err(e) => Self::error_result(format!("Failed to read file: {e}")),
        }
    }

    /// Upload a file (write content)
    pub async fn upload_file(&self, path: &str, content: Option<Vec<u8>>) -> CommandResult {
        let content = match content {
            Some(c) => c,
            None => return Self::error_result("No content provided".to_string()),
        };

        // Check content size
        let max_size = self.config.security.max_file_size;
        if content.len() as u64 > max_size {
            warn!(
                "[AUDIT] FileUpload blocked - content too large: {} bytes > {} bytes limit",
                content.len(),
                max_size
            );
            return Self::error_result(format!(
                "Content too large ({}MB). Maximum allowed: {}MB",
                content.len() / 1024 / 1024,
                max_size / 1024 / 1024
            ));
        }

        // Validate path
        let validated_path = match self.validate_path(path) {
            Ok(p) => p,
            Err(e) => return Self::error_result(e),
        };

        // Create parent directories if they don't exist
        if let Some(parent) = validated_path.parent() {
            if !parent.exists() {
                if let Err(e) = fs::create_dir_all(parent) {
                    return Self::error_result(format!(
                        "Failed to create parent directories: {e}"
                    ));
                }
            }
        }

        info!(
            "[AUDIT] FileUpload: {} ({} bytes)",
            validated_path.display(),
            content.len()
        );

        match fs::write(&validated_path, &content) {
            Ok(_) => CommandResult {
                command_id: String::new(),
                success: true,
                output: format!(
                    "Written {} bytes to {}",
                    content.len(),
                    validated_path.display()
                ),
                error: String::new(),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
            },
            Err(e) => Self::error_result(format!("Failed to write file: {e}")),
        }
    }

    /// Truncate a file (clear its content)
    pub async fn truncate_file(&self, path: &str) -> CommandResult {
        // Validate path first
        let validated_path = match self.validate_path(path) {
            Ok(p) => p,
            Err(e) => return Self::error_result(e),
        };

        if !validated_path.exists() {
            return Self::error_result(format!("File not found: {}", validated_path.display()));
        }

        info!("[AUDIT] FileTruncate: {}", validated_path.display());

        match OpenOptions::new()
            .write(true)
            .truncate(true)
            .open(&validated_path)
        {
            Ok(_) => CommandResult {
                command_id: String::new(),
                success: true,
                output: format!("Truncated file: {}", validated_path.display()),
                error: String::new(),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
            },
            Err(e) => Self::error_result(format!("Failed to truncate file: {e}")),
        }
    }
}
