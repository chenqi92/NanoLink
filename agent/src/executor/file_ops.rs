use std::fs::{self, File, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::Path;

use crate::proto::CommandResult;

/// File operations executor
pub struct FileExecutor;

impl FileExecutor {
    /// Create a new file executor
    pub fn new() -> Self {
        Self
    }

    /// Read the tail of a file
    pub async fn tail_file(&self, path: &str, lines: usize) -> CommandResult {
        let path = Path::new(path);

        if !path.exists() {
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: format!("File not found: {}", path.display()),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
            };
        }

        match File::open(path) {
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
            Err(e) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: format!("Failed to read file: {}", e),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
            },
        }
    }

    /// Download a file (read full content)
    pub async fn download_file(&self, path: &str) -> CommandResult {
        let path = Path::new(path);

        if !path.exists() {
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: format!("File not found: {}", path.display()),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
            };
        }

        // Check file size (limit to 50MB)
        let metadata = match fs::metadata(path) {
            Ok(m) => m,
            Err(e) => {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: format!("Failed to read file metadata: {}", e),
                    file_content: vec![],
                    processes: vec![],
                    containers: vec![],
                }
            }
        };

        const MAX_SIZE: u64 = 50 * 1024 * 1024; // 50MB
        if metadata.len() > MAX_SIZE {
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: format!(
                    "File too large ({}MB). Maximum allowed: {}MB",
                    metadata.len() / 1024 / 1024,
                    MAX_SIZE / 1024 / 1024
                ),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
            };
        }

        match fs::read(path) {
            Ok(content) => CommandResult {
                command_id: String::new(),
                success: true,
                output: format!("Downloaded {} bytes", content.len()),
                error: String::new(),
                file_content: content,
                processes: vec![],
                containers: vec![],
            },
            Err(e) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: format!("Failed to read file: {}", e),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
            },
        }
    }

    /// Upload a file (write content)
    pub async fn upload_file(&self, path: &str, content: Option<Vec<u8>>) -> CommandResult {
        let content = match content {
            Some(c) => c,
            None => {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: "No content provided".to_string(),
                    file_content: vec![],
                    processes: vec![],
                    containers: vec![],
                }
            }
        };

        let path = Path::new(path);

        // Create parent directories if they don't exist
        if let Some(parent) = path.parent() {
            if !parent.exists() {
                if let Err(e) = fs::create_dir_all(parent) {
                    return CommandResult {
                        command_id: String::new(),
                        success: false,
                        output: String::new(),
                        error: format!("Failed to create parent directories: {}", e),
                        file_content: vec![],
                        processes: vec![],
                        containers: vec![],
                    };
                }
            }
        }

        match fs::write(path, &content) {
            Ok(_) => CommandResult {
                command_id: String::new(),
                success: true,
                output: format!("Written {} bytes to {}", content.len(), path.display()),
                error: String::new(),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
            },
            Err(e) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: format!("Failed to write file: {}", e),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
            },
        }
    }

    /// Truncate a file (clear its content)
    pub async fn truncate_file(&self, path: &str) -> CommandResult {
        let path = Path::new(path);

        if !path.exists() {
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: format!("File not found: {}", path.display()),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
            };
        }

        match OpenOptions::new().write(true).truncate(true).open(path) {
            Ok(_) => CommandResult {
                command_id: String::new(),
                success: true,
                output: format!("Truncated file: {}", path.display()),
                error: String::new(),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
            },
            Err(e) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: format!("Failed to truncate file: {}", e),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
            },
        }
    }
}

impl Default for FileExecutor {
    fn default() -> Self {
        Self::new()
    }
}
