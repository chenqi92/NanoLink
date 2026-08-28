use std::collections::{HashMap, VecDeque};
use std::fs::{self, File, OpenOptions};
use std::io::{BufRead, BufReader, Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use glob::Pattern;
use sha2::{Digest, Sha256};
use tracing::{info, warn};

use crate::config::Config;
use crate::proto::{CommandResult, FileEntry};

const MAX_TAIL_LINES: usize = 1_000;
const MAX_TAIL_OUTPUT_BYTES: usize = 1024 * 1024;
const MAX_TRANSFER_CHUNK_BYTES: usize = 512 * 1024;

fn has_glob_chars(rule: &str) -> bool {
    rule.chars().any(|c| matches!(c, '*' | '?' | '[' | ']'))
}

fn path_matches_rule(canonical: &Path, canonical_str: &str, rule: &str) -> bool {
    let rule = rule.trim();
    if rule.is_empty() {
        return false;
    }

    if has_glob_chars(rule) {
        return Pattern::new(rule)
            .map(|pattern| pattern.matches(canonical_str))
            .unwrap_or(false);
    }

    let rule_path = Path::new(rule);
    let normalized_rule = if rule_path.exists() {
        rule_path
            .canonicalize()
            .unwrap_or_else(|_| rule_path.to_path_buf())
    } else {
        rule_path.to_path_buf()
    };

    canonical.starts_with(&normalized_rule)
}

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
    /// Returns the canonicalized path if valid, or an error message.
    ///
    /// `for_write` enables fail-closed behavior: a write to a path is rejected
    /// when no `allowed_paths` allowlist is configured, so the default (empty)
    /// config cannot be used to drop files anywhere the denylist doesn't
    /// explicitly cover (cron jobs, systemd units, shell profiles, ...). Reads
    /// remain governed by the denylist only, to keep monitoring working
    /// out of the box.
    fn validate_path(&self, path_str: &str, for_write: bool) -> Result<PathBuf, String> {
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
            if path_matches_rule(&canonical, &canonical_str, denied) {
                warn!(
                    "[AUDIT] Access to denied path blocked: {} (rule: {})",
                    canonical_str, denied
                );
                return Err(format!(
                    "Access denied: path matches blocked rule '{denied}'"
                ));
            }
        }

        // Fail closed for writes when no allowlist is configured: without an
        // explicit allowed_paths, an empty list previously meant "write
        // anywhere not denied", a direct root-persistence/RCE primitive.
        if self.config.security.allowed_paths.is_empty() {
            if for_write {
                warn!(
                    "[AUDIT] Write blocked (fail-closed, no allowed_paths configured): {}",
                    canonical_str
                );
                return Err(
                    "File write disabled: configure security.allowed_paths to enable writes"
                        .to_string(),
                );
            }
            // Reads: denylist-only (checked above).
            info!("[AUDIT] Path validated: {}", canonical_str);
            return Ok(canonical);
        }

        // Check allowed paths (the list is non-empty here; the empty case
        // returned early above). Use the shared matcher for consistency with the
        // denied-paths check.
        {
            let is_allowed = self
                .config
                .security
                .allowed_paths
                .iter()
                .any(|allowed| path_matches_rule(&canonical, &canonical_str, allowed));

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
            ..Default::default()
        }
    }

    /// List directory entries as structured FileEntry items (FILE_LIST).
    pub async fn list_directory(&self, path: &str) -> CommandResult {
        use std::time::UNIX_EPOCH;
        let validated_path = match self.validate_path(path, false) {
            Ok(p) => p,
            Err(e) => return Self::error_result(e),
        };
        if !validated_path.is_dir() {
            return Self::error_result(format!("Not a directory: {}", validated_path.display()));
        }
        info!("[AUDIT] FileList: {}", validated_path.display());
        let read = match fs::read_dir(&validated_path) {
            Ok(rd) => rd,
            Err(e) => return Self::error_result(format!("Failed to read directory: {e}")),
        };
        let mut files: Vec<FileEntry> = Vec::new();
        for entry in read.flatten() {
            if files.len() >= 2000 {
                break;
            }
            let meta = entry.metadata().ok();
            let modified = meta
                .as_ref()
                .and_then(|m| m.modified().ok())
                .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
                .map(|d| d.as_millis() as i64)
                .unwrap_or(0);
            files.push(FileEntry {
                name: entry.file_name().to_string_lossy().to_string(),
                is_dir: meta.as_ref().map(|m| m.is_dir()).unwrap_or(false),
                size: meta.as_ref().map(|m| m.len()).unwrap_or(0),
                modified,
            });
        }
        files.sort_by(|a, b| b.is_dir.cmp(&a.is_dir).then_with(|| a.name.cmp(&b.name)));
        CommandResult {
            command_id: String::new(),
            success: true,
            output: format!("{} entries", files.len()),
            error: String::new(),
            files,
            ..Default::default()
        }
    }

    /// Read the tail of a file
    pub async fn tail_file(&self, path: &str, lines: usize) -> CommandResult {
        let requested_lines = lines.min(MAX_TAIL_LINES);
        if requested_lines == 0 {
            return CommandResult {
                command_id: String::new(),
                success: true,
                output: String::new(),
                error: String::new(),
                ..Default::default()
            };
        }

        // Validate path first
        let validated_path = match self.validate_path(path, false) {
            Ok(p) => p,
            Err(e) => return Self::error_result(e),
        };

        if !validated_path.exists() {
            return Self::error_result(format!("File not found: {}", validated_path.display()));
        }

        info!(
            "[AUDIT] FileTail: {} (last {} lines)",
            validated_path.display(),
            requested_lines
        );

        match File::open(&validated_path) {
            Ok(file) => {
                let reader = BufReader::new(file);
                let mut tail = VecDeque::with_capacity(requested_lines);
                for line in reader.lines().map_while(Result::ok) {
                    if tail.len() == requested_lines {
                        tail.pop_front();
                    }
                    tail.push_back(line);
                }

                let mut output = String::new();
                let mut truncated = false;
                for line in tail {
                    let separator_len = if output.is_empty() { 0 } else { 1 };
                    if output.len() + separator_len + line.len() > MAX_TAIL_OUTPUT_BYTES {
                        if separator_len == 1 && output.len() < MAX_TAIL_OUTPUT_BYTES {
                            output.push('\n');
                        }

                        let remaining = MAX_TAIL_OUTPUT_BYTES.saturating_sub(output.len());
                        let mut used = 0;
                        for ch in line.chars() {
                            let len = ch.len_utf8();
                            if used + len > remaining {
                                break;
                            }
                            output.push(ch);
                            used += len;
                        }
                        truncated = true;
                        break;
                    }

                    if separator_len == 1 {
                        output.push('\n');
                    }
                    output.push_str(&line);
                }

                if truncated {
                    output.push_str("\n... (output truncated)");
                }

                CommandResult {
                    command_id: String::new(),
                    success: true,
                    output,
                    error: String::new(),
                    ..Default::default()
                }
            }
            Err(e) => Self::error_result(format!("Failed to read file: {e}")),
        }
    }

    /// Download one bounded chunk. The caller repeats the request with the
    /// returned offset; this keeps command results below gRPC/message limits.
    pub async fn download_file(
        &self,
        path: &str,
        params: &HashMap<String, String>,
    ) -> CommandResult {
        // Validate path first
        let validated_path = match self.validate_path(path, false) {
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

        if !metadata.is_file() {
            return Self::error_result("Only regular files can be downloaded".to_string());
        }

        let offset = match params.get("offset").map(|s| s.parse::<u64>()) {
            Some(Ok(value)) => value,
            Some(Err(_)) => return Self::error_result("Invalid download offset".to_string()),
            None => 0,
        };
        if offset > metadata.len() {
            return Self::error_result("Download offset exceeds file size".to_string());
        }
        let requested = match params.get("length").map(|s| s.parse::<usize>()) {
            Some(Ok(value)) if value > 0 => value.min(MAX_TRANSFER_CHUNK_BYTES),
            Some(Ok(_)) | Some(Err(_)) => {
                return Self::error_result("Invalid download chunk length".to_string());
            }
            None => MAX_TRANSFER_CHUNK_BYTES,
        };

        info!(
            "[AUDIT] FileDownload: {} (offset {}, at most {} bytes, total {})",
            validated_path.display(),
            offset,
            requested,
            metadata.len()
        );

        let read_chunk = || -> Result<Vec<u8>, String> {
            let mut file =
                File::open(&validated_path).map_err(|e| format!("Failed to open file: {e}"))?;
            file.seek(SeekFrom::Start(offset))
                .map_err(|e| format!("Failed to seek file: {e}"))?;
            let remaining = metadata.len().saturating_sub(offset);
            let mut content = vec![0_u8; requested.min(remaining as usize)];
            let read = file
                .read(&mut content)
                .map_err(|e| format!("Failed to read file: {e}"))?;
            content.truncate(read);
            Ok(content)
        };

        match read_chunk() {
            Ok(content) => CommandResult {
                command_id: String::new(),
                success: true,
                output: format!(
                    "offset={};length={};total={};eof={}",
                    offset,
                    content.len(),
                    metadata.len(),
                    offset + content.len() as u64 >= metadata.len()
                ),
                error: String::new(),
                file_content: content,
                ..Default::default()
            },
            Err(e) => Self::error_result(e),
        }
    }

    /// Handle a resumable, bounded upload. Files are assembled into a sibling
    /// temporary file, verified, then atomically renamed on `finish`.
    pub async fn upload_file(&self, path: &str, params: &HashMap<String, String>) -> CommandResult {
        let validated_path = match self.validate_path(path, true) {
            Ok(p) => p,
            Err(e) => return Self::error_result(e),
        };
        let phase = params.get("phase").map(String::as_str).unwrap_or("");
        let upload_id = match params.get("upload_id") {
            Some(id)
                if !id.is_empty()
                    && id.len() <= 64
                    && id
                        .bytes()
                        .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_') =>
            {
                id
            }
            _ => return Self::error_result("Invalid upload id".to_string()),
        };
        let parent = match validated_path.parent() {
            Some(parent) if parent.is_dir() => parent,
            _ => return Self::error_result("Upload parent directory does not exist".to_string()),
        };
        let temp_path = parent.join(format!(".nanolink-upload-{upload_id}.part"));

        let total_size = || -> Result<u64, String> {
            let size = params
                .get("total_size")
                .ok_or("Missing total size")?
                .parse::<u64>()
                .map_err(|_| "Invalid total size".to_string())?;
            if size > self.config.security.max_file_size {
                return Err(format!(
                    "File too large ({}MB). Maximum allowed: {}MB",
                    size / 1024 / 1024,
                    self.config.security.max_file_size / 1024 / 1024
                ));
            }
            Ok(size)
        };

        match phase {
            "begin" => {
                let size = match total_size() {
                    Ok(value) => value,
                    Err(e) => return Self::error_result(e),
                };
                if validated_path.exists()
                    && params.get("overwrite").map(String::as_str) != Some("true")
                {
                    return Self::error_result(
                        "Target already exists; confirm overwrite".to_string(),
                    );
                }
                let _ = fs::remove_file(&temp_path);
                match OpenOptions::new()
                    .write(true)
                    .create_new(true)
                    .open(&temp_path)
                {
                    Ok(_) => {
                        info!(
                            "[AUDIT] FileUpload begin: {} ({} bytes)",
                            validated_path.display(),
                            size
                        );
                        CommandResult {
                            success: true,
                            output: "offset=0".to_string(),
                            ..Default::default()
                        }
                    }
                    Err(e) => Self::error_result(format!("Failed to start upload: {e}")),
                }
            }
            "chunk" => {
                let size = match total_size() {
                    Ok(value) => value,
                    Err(e) => return Self::error_result(e),
                };
                let offset = match params.get("offset").map(|s| s.parse::<u64>()) {
                    Some(Ok(value)) => value,
                    _ => return Self::error_result("Invalid upload offset".to_string()),
                };
                let content = match params
                    .get("content_base64")
                    .ok_or("Missing upload chunk")
                    .and_then(|content| {
                        BASE64
                            .decode(content)
                            .map_err(|_| "Invalid base64 upload chunk")
                    }) {
                    Ok(content) if content.len() <= MAX_TRANSFER_CHUNK_BYTES => content,
                    Ok(_) => return Self::error_result("Upload chunk is too large".to_string()),
                    Err(e) => return Self::error_result(e.to_string()),
                };
                if offset.saturating_add(content.len() as u64) > size {
                    return Self::error_result(
                        "Upload chunk exceeds declared file size".to_string(),
                    );
                }
                let mut file = match OpenOptions::new().append(true).open(&temp_path) {
                    Ok(file) => file,
                    Err(e) => return Self::error_result(format!("Upload session not found: {e}")),
                };
                let current = match file.metadata() {
                    Ok(meta) => meta.len(),
                    Err(e) => return Self::error_result(format!("Failed to inspect upload: {e}")),
                };
                if current != offset {
                    return Self::error_result(format!(
                        "Upload offset mismatch: expected {current}, received {offset}"
                    ));
                }
                if let Err(e) = file.write_all(&content).and_then(|_| file.flush()) {
                    return Self::error_result(format!("Failed to write upload chunk: {e}"));
                }
                CommandResult {
                    success: true,
                    output: format!("offset={}", offset + content.len() as u64),
                    ..Default::default()
                }
            }
            "finish" => {
                let size = match total_size() {
                    Ok(value) => value,
                    Err(e) => return Self::error_result(e),
                };
                let expected_hash = match params.get("sha256") {
                    Some(hash)
                        if hash.len() == 64 && hash.bytes().all(|b| b.is_ascii_hexdigit()) =>
                    {
                        hash.to_ascii_lowercase()
                    }
                    _ => return Self::error_result("Invalid SHA-256 checksum".to_string()),
                };
                let metadata = match fs::metadata(&temp_path) {
                    Ok(meta) if meta.len() == size => meta,
                    Ok(meta) => {
                        return Self::error_result(format!(
                            "Upload size mismatch: expected {size}, received {}",
                            meta.len()
                        ));
                    }
                    Err(e) => return Self::error_result(format!("Upload session not found: {e}")),
                };
                let _ = metadata;
                let mut file = match File::open(&temp_path) {
                    Ok(file) => file,
                    Err(e) => return Self::error_result(format!("Failed to verify upload: {e}")),
                };
                let mut hasher = Sha256::new();
                let mut buffer = [0_u8; 64 * 1024];
                loop {
                    let read = match file.read(&mut buffer) {
                        Ok(0) => break,
                        Ok(read) => read,
                        Err(e) => {
                            return Self::error_result(format!("Failed to verify upload: {e}"));
                        }
                    };
                    hasher.update(&buffer[..read]);
                }
                let actual_hash = hex::encode(hasher.finalize());
                if actual_hash != expected_hash {
                    let _ = fs::remove_file(&temp_path);
                    return Self::error_result("Upload checksum mismatch".to_string());
                }
                if validated_path.exists()
                    && params.get("overwrite").map(String::as_str) != Some("true")
                {
                    return Self::error_result(
                        "Target already exists; confirm overwrite".to_string(),
                    );
                }
                #[cfg(unix)]
                {
                    use std::os::unix::fs::PermissionsExt;
                    if let Err(e) =
                        fs::set_permissions(&temp_path, fs::Permissions::from_mode(0o640))
                    {
                        return Self::error_result(format!(
                            "Failed to set upload permissions: {e}"
                        ));
                    }
                }
                if let Err(e) = fs::rename(&temp_path, &validated_path) {
                    return Self::error_result(format!("Failed to finalize upload: {e}"));
                }
                info!(
                    "[AUDIT] FileUpload complete: {} ({} bytes, sha256 {})",
                    validated_path.display(),
                    size,
                    actual_hash
                );
                CommandResult {
                    success: true,
                    output: format!("Uploaded {size} bytes"),
                    ..Default::default()
                }
            }
            "abort" => match fs::remove_file(&temp_path) {
                Ok(_) => CommandResult {
                    success: true,
                    output: "Upload aborted".to_string(),
                    ..Default::default()
                },
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => CommandResult {
                    success: true,
                    output: "Upload session already absent".to_string(),
                    ..Default::default()
                },
                Err(e) => Self::error_result(format!("Failed to abort upload: {e}")),
            },
            _ => Self::error_result("Invalid upload phase".to_string()),
        }
    }

    /// Truncate a file (clear its content)
    pub async fn truncate_file(&self, path: &str) -> CommandResult {
        // Validate path first
        let validated_path = match self.validate_path(path, true) {
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
                ..Default::default()
            },
            Err(e) => Self::error_result(format!("Failed to truncate file: {e}")),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;
    use std::sync::Arc;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn unique_temp_dir(name: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock before unix epoch")
            .as_nanos();
        let dir = std::env::temp_dir().join(format!(
            "nanolink-file-{}-{}-{}",
            name,
            std::process::id(),
            nanos
        ));
        fs::create_dir_all(&dir).expect("create temp dir");
        dir
    }

    fn test_executor(allowed_paths: Vec<String>, denied_paths: Vec<String>) -> FileExecutor {
        let mut config = Config::sample();
        config.security.allowed_paths = allowed_paths;
        config.security.denied_paths = denied_paths;
        FileExecutor::new(Arc::new(config))
    }

    #[test]
    fn allowed_path_match_is_component_bounded() {
        let root = unique_temp_dir("allowed-prefix");
        let allowed = root.join("allowed");
        let sibling = root.join("allowed_evil");
        fs::create_dir_all(&allowed).expect("create allowed dir");
        fs::create_dir_all(&sibling).expect("create sibling dir");

        let allowed_file = allowed.join("ok.txt");
        let sibling_file = sibling.join("secret.txt");
        fs::write(&allowed_file, b"ok").expect("write allowed file");
        fs::write(&sibling_file, b"secret").expect("write sibling file");

        let executor = test_executor(vec![allowed.to_string_lossy().into_owned()], vec![]);
        assert!(
            executor
                .validate_path(&allowed_file.to_string_lossy(), false)
                .is_ok()
        );
        assert!(
            executor
                .validate_path(&sibling_file.to_string_lossy(), false)
                .is_err()
        );

        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn denied_path_match_is_component_bounded() {
        let root = unique_temp_dir("denied-prefix");
        let denied = root.join("blocked");
        let sibling = root.join("blocked_evil");
        fs::create_dir_all(&denied).expect("create denied dir");
        fs::create_dir_all(&sibling).expect("create sibling dir");

        let denied_file = denied.join("secret.txt");
        let sibling_file = sibling.join("ok.txt");
        fs::write(&denied_file, b"secret").expect("write denied file");
        fs::write(&sibling_file, b"ok").expect("write sibling file");

        let executor = test_executor(vec![], vec![denied.to_string_lossy().into_owned()]);
        assert!(
            executor
                .validate_path(&sibling_file.to_string_lossy(), false)
                .is_ok()
        );
        assert!(
            executor
                .validate_path(&denied_file.to_string_lossy(), false)
                .is_err()
        );

        let _ = fs::remove_dir_all(root);
    }

    #[tokio::test]
    async fn chunked_upload_is_verified_then_downloaded_in_chunks() {
        let root = unique_temp_dir("chunk-transfer");
        let target = root.join("artifact.jar");
        let executor = test_executor(vec![root.to_string_lossy().into_owned()], vec![]);
        let payload = b"production-safe-chunk";
        let checksum = hex::encode(Sha256::digest(payload));
        let common = HashMap::from([
            ("upload_id".to_string(), "test-upload-1".to_string()),
            ("total_size".to_string(), payload.len().to_string()),
            ("overwrite".to_string(), "false".to_string()),
        ]);

        let mut begin = common.clone();
        begin.insert("phase".to_string(), "begin".to_string());
        assert!(
            executor
                .upload_file(&target.to_string_lossy(), &begin)
                .await
                .success
        );

        let mut chunk = common.clone();
        chunk.insert("phase".to_string(), "chunk".to_string());
        chunk.insert("offset".to_string(), "0".to_string());
        chunk.insert("content_base64".to_string(), BASE64.encode(payload));
        assert!(
            executor
                .upload_file(&target.to_string_lossy(), &chunk)
                .await
                .success
        );

        let mut finish = common;
        finish.insert("phase".to_string(), "finish".to_string());
        finish.insert("sha256".to_string(), checksum);
        assert!(
            executor
                .upload_file(&target.to_string_lossy(), &finish)
                .await
                .success
        );
        assert_eq!(fs::read(&target).expect("read upload"), payload);

        let first = executor
            .download_file(
                &target.to_string_lossy(),
                &HashMap::from([
                    ("offset".to_string(), "0".to_string()),
                    ("length".to_string(), "7".to_string()),
                ]),
            )
            .await;
        assert!(first.success);
        assert_eq!(first.file_content, &payload[..7]);
        assert!(first.output.contains("eof=false"));

        let second = executor
            .download_file(
                &target.to_string_lossy(),
                &HashMap::from([
                    ("offset".to_string(), "7".to_string()),
                    ("length".to_string(), "512".to_string()),
                ]),
            )
            .await;
        assert!(second.success);
        assert_eq!(second.file_content, &payload[7..]);
        assert!(second.output.contains("eof=true"));

        let _ = fs::remove_dir_all(root);
    }
}
