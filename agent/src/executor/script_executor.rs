use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Arc;
use std::time::Duration;
use tracing::{info, warn};

use crate::config::Config;
use crate::proto::{CommandResult, ScriptInfo};

/// Script executor with security controls
pub struct ScriptExecutor {
    config: Arc<Config>,
}

/// Dangerous characters that could be used for injection
const DANGEROUS_CHARS: &[char] = &[
    '|', '&', ';', '$', '`', '(', ')', '{', '}', '<', '>', '\n', '\r', '\'', '"', '\\',
];

impl ScriptExecutor {
    /// Create a new script executor
    pub fn new(config: Arc<Config>) -> Self {
        Self { config }
    }

    /// List available scripts in the scripts directory
    pub async fn list_scripts(&self, _params: &HashMap<String, String>) -> CommandResult {
        if !self.config.scripts.enabled {
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: "Script execution is disabled".to_string(),
                ..Default::default()
            };
        }

        let scripts_dir = PathBuf::from(&self.config.scripts.scripts_dir);
        if !scripts_dir.exists() {
            return CommandResult {
                command_id: String::new(),
                success: true,
                output: "[]".to_string(), // Empty list
                error: String::new(),
                scripts: vec![],
                ..Default::default()
            };
        }

        let mut scripts = Vec::new();

        // Read scripts directory
        match fs::read_dir(&scripts_dir) {
            Ok(entries) => {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.is_file() {
                        if let Some(script_info) = self.parse_script_info(&path) {
                            // Check category filter
                            if !self.config.scripts.allowed_categories.is_empty()
                                && !self
                                    .config
                                    .scripts
                                    .allowed_categories
                                    .contains(&script_info.category)
                            {
                                continue;
                            }
                            scripts.push(script_info);
                        }
                    }
                }
            }
            Err(e) => {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: format!("Failed to read scripts directory: {e}"),
                    ..Default::default()
                };
            }
        }

        info!("Listed {} scripts", scripts.len());

        CommandResult {
            command_id: String::new(),
            success: true,
            output: format!("Found {} scripts", scripts.len()),
            error: String::new(),
            scripts,
            ..Default::default()
        }
    }

    /// Execute a predefined script
    pub async fn execute_script(&self, params: &HashMap<String, String>) -> CommandResult {
        if !self.config.scripts.enabled {
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: "Script execution is disabled".to_string(),
                ..Default::default()
            };
        }

        let script_name = match params.get("name") {
            Some(n) => n,
            None => {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: "Script name is required".to_string(),
                    ..Default::default()
                };
            }
        };

        // Validate script name - no path traversal
        if script_name.contains("..") || script_name.contains('/') || script_name.contains('\\') {
            warn!("Attempted path traversal in script name: {}", script_name);
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: "Invalid script name".to_string(),
                ..Default::default()
            };
        }

        let scripts_dir = PathBuf::from(&self.config.scripts.scripts_dir);
        let script_path = scripts_dir.join(script_name);

        // Verify script exists and is within scripts directory
        if !script_path.exists() {
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: format!("Script '{script_name}' not found"),
                ..Default::default()
            };
        }

        // Verify script is within scripts directory (prevent symlink attacks)
        let canonical_script = match script_path.canonicalize() {
            Ok(p) => p,
            Err(e) => {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: format!("Failed to resolve script path: {e}"),
                    ..Default::default()
                };
            }
        };

        let canonical_dir = match scripts_dir.canonicalize() {
            Ok(p) => p,
            Err(e) => {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: format!("Failed to resolve scripts directory: {e}"),
                    ..Default::default()
                };
            }
        };

        if !canonical_script.starts_with(&canonical_dir) {
            warn!("Script path escape attempt: {}", script_path.display());
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: "Script path is outside scripts directory".to_string(),
                ..Default::default()
            };
        }

        // Verify signature if required
        if self.config.scripts.require_signature {
            if let Err(e) = self.verify_script_signature(&canonical_script) {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: format!("Script signature verification failed: {e}"),
                    ..Default::default()
                };
            }
        }

        // Parse and validate arguments
        let args_str = params.get("args").map(|s| s.as_str()).unwrap_or("");
        let args: Vec<&str> = if args_str.is_empty() {
            vec![]
        } else {
            args_str.split_whitespace().collect()
        };

        // Validate arguments for dangerous characters
        for arg in &args {
            if arg.chars().any(|c| DANGEROUS_CHARS.contains(&c)) {
                warn!("Dangerous characters in script argument: {}", arg);
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: "Arguments contain dangerous characters".to_string(),
                    ..Default::default()
                };
            }
        }

        info!("Executing script: {} with args: {:?}", script_name, args);

        // Execute the script
        let timeout_secs = self.config.scripts.timeout_seconds;
        let result = self.run_script(&canonical_script, &args, timeout_secs);

        // Truncate output if needed
        let mut output = result.0;
        if output.len() > self.config.scripts.max_output_size {
            output.truncate(self.config.scripts.max_output_size);
            output.push_str("\n... (output truncated)");
        }

        CommandResult {
            command_id: String::new(),
            success: result.1,
            output,
            error: result.2,
            ..Default::default()
        }
    }

    /// Parse script info from file
    fn parse_script_info(&self, path: &Path) -> Option<ScriptInfo> {
        let name = path.file_name()?.to_str()?.to_string();

        // Read first few lines for metadata
        let content = fs::read_to_string(path).ok()?;
        let mut description = String::new();
        let mut category = "general".to_string();
        let mut required_args = Vec::new();
        let mut required_permission = 2; // Default to SERVICE_CONTROL

        for line in content.lines().take(20) {
            let line = line.trim();
            if line.starts_with("# Description:") || line.starts_with("# description:") {
                description = line
                    .trim_start_matches("# Description:")
                    .trim_start_matches("# description:")
                    .trim()
                    .to_string();
            } else if line.starts_with("# Category:") || line.starts_with("# category:") {
                category = line
                    .trim_start_matches("# Category:")
                    .trim_start_matches("# category:")
                    .trim()
                    .to_string();
            } else if line.starts_with("# Args:") || line.starts_with("# args:") {
                let args_str = line
                    .trim_start_matches("# Args:")
                    .trim_start_matches("# args:")
                    .trim();
                required_args = args_str.split(',').map(|s| s.trim().to_string()).collect();
            } else if line.starts_with("# Permission:") || line.starts_with("# permission:") {
                let perm_str = line
                    .trim_start_matches("# Permission:")
                    .trim_start_matches("# permission:")
                    .trim();
                required_permission = perm_str.parse().unwrap_or(2);
            }
        }

        // Calculate checksum
        let checksum = self.calculate_checksum(path).unwrap_or_default();

        // Get file metadata
        let metadata = fs::metadata(path).ok()?;
        let file_size = metadata.len() as i64;
        let last_modified = metadata
            .modified()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .and_then(|d| chrono::DateTime::from_timestamp(d.as_secs() as i64, 0))
            .map(|dt| dt.to_rfc3339())
            .unwrap_or_default();

        // Check signature
        let signature_verified = if self.config.scripts.require_signature {
            self.verify_script_signature(path).is_ok()
        } else {
            false
        };

        Some(ScriptInfo {
            name,
            description,
            category,
            required_args,
            required_permission,
            checksum,
            file_size,
            last_modified,
            signature_verified,
        })
    }

    /// Calculate SHA256 checksum of a file
    fn calculate_checksum(&self, path: &Path) -> Option<String> {
        let content = fs::read(path).ok()?;
        let mut hasher = Sha256::new();
        hasher.update(&content);
        Some(format!("{:x}", hasher.finalize()))
    }

    /// Verify script signature using SHA256 checksum
    ///
    /// The .sig file should contain the SHA256 hash of the script content.
    /// Format: `<sha256_hex>  <filename>` (similar to sha256sum output)
    ///
    /// This provides integrity verification to ensure scripts haven't been tampered with.
    /// For production use, consider implementing asymmetric signature verification (e.g., GPG).
    fn verify_script_signature(&self, path: &Path) -> Result<(), String> {
        // Check for .sig file
        let sig_path = path.with_extension(
            path.extension()
                .map(|e| format!("{}.sig", e.to_string_lossy()))
                .unwrap_or_else(|| "sig".to_string()),
        );

        if !sig_path.exists() {
            return Err("Signature file not found".to_string());
        }

        // Read the expected checksum from .sig file
        let sig_content = fs::read_to_string(&sig_path)
            .map_err(|e| format!("Failed to read signature file: {e}"))?;

        // Parse signature file (format: "<sha256_hex>  <filename>" or just "<sha256_hex>")
        let expected_hash = sig_content
            .lines()
            .next()
            .and_then(|line| line.split_whitespace().next())
            .ok_or_else(|| "Invalid signature file format".to_string())?
            .trim()
            .to_lowercase();

        // Validate hash format (64 hex characters)
        if expected_hash.len() != 64 || !expected_hash.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(
                "Invalid signature format: expected SHA256 hash (64 hex characters)".to_string(),
            );
        }

        // Calculate actual checksum of the script
        let actual_hash = self
            .calculate_checksum(path)
            .ok_or_else(|| "Failed to calculate script checksum".to_string())?;

        // Use constant-time comparison to prevent timing attacks
        use subtle::ConstantTimeEq;
        let expected_bytes = expected_hash.as_bytes();
        let actual_bytes = actual_hash.as_bytes();

        if expected_bytes.len() != actual_bytes.len() {
            warn!(
                "Script signature mismatch for {}: hash length mismatch",
                path.display()
            );
            return Err("Script signature verification failed: checksum mismatch".to_string());
        }

        if expected_bytes.ct_eq(actual_bytes).into() {
            info!("Script signature verified: {}", path.display());
            Ok(())
        } else {
            warn!(
                "Script signature mismatch for {}: expected {}, got {}",
                path.display(),
                expected_hash,
                actual_hash
            );
            Err("Script signature verification failed: checksum mismatch".to_string())
        }
    }

    /// Run the script with timeout
    fn run_script(
        &self,
        script_path: &Path,
        args: &[&str],
        timeout_secs: u64,
    ) -> (String, bool, String) {
        #[cfg(unix)]
        let result = self.run_script_unix(script_path, args, timeout_secs);

        #[cfg(windows)]
        let result = self.run_script_windows(script_path, args, timeout_secs);

        result
    }

    #[cfg(unix)]
    fn run_script_unix(
        &self,
        script_path: &Path,
        args: &[&str],
        timeout_secs: u64,
    ) -> (String, bool, String) {
        use std::io::Read;
        use std::process::Stdio;

        let mut cmd = Command::new(script_path);
        cmd.args(args).stdout(Stdio::piped()).stderr(Stdio::piped());

        let mut child = match cmd.spawn() {
            Ok(c) => c,
            Err(e) => {
                return (
                    String::new(),
                    false,
                    format!("Failed to spawn script: {}", e),
                );
            }
        };

        // Wait with timeout
        let timeout = Duration::from_secs(timeout_secs);
        let start = std::time::Instant::now();

        loop {
            match child.try_wait() {
                Ok(Some(status)) => {
                    let mut stdout = String::new();
                    let mut stderr = String::new();

                    if let Some(mut out) = child.stdout.take() {
                        let _ = out.read_to_string(&mut stdout);
                    }
                    if let Some(mut err) = child.stderr.take() {
                        let _ = err.read_to_string(&mut stderr);
                    }

                    return (stdout, status.success(), stderr);
                }
                Ok(None) => {
                    if start.elapsed() > timeout {
                        let _ = child.kill();
                        return (
                            String::new(),
                            false,
                            format!("Script timed out after {} seconds", timeout_secs),
                        );
                    }
                    std::thread::sleep(Duration::from_millis(100));
                }
                Err(e) => {
                    return (
                        String::new(),
                        false,
                        format!("Failed to wait for script: {}", e),
                    );
                }
            }
        }
    }

    #[cfg(windows)]
    fn run_script_windows(
        &self,
        script_path: &Path,
        args: &[&str],
        timeout_secs: u64,
    ) -> (String, bool, String) {
        use std::io::Read;
        use std::process::Stdio;

        // Determine script type and executor
        let ext = script_path
            .extension()
            .and_then(|e| e.to_str())
            .map(|e| e.to_lowercase());

        let (program, script_args): (&str, Vec<&str>) = match ext.as_deref() {
            Some("ps1") => (
                "powershell",
                vec![
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    script_path.to_str().unwrap_or(""),
                ],
            ),
            Some("bat") | Some("cmd") => ("cmd", vec!["/C", script_path.to_str().unwrap_or("")]),
            _ => {
                return (
                    String::new(),
                    false,
                    "Unsupported script type on Windows".to_string(),
                );
            }
        };

        let mut cmd = Command::new(program);
        cmd.args(&script_args)
            .args(args)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());

        let mut child = match cmd.spawn() {
            Ok(c) => c,
            Err(e) => {
                return (String::new(), false, format!("Failed to spawn script: {e}"));
            }
        };

        // Wait with timeout
        let timeout = Duration::from_secs(timeout_secs);
        let start = std::time::Instant::now();

        loop {
            match child.try_wait() {
                Ok(Some(status)) => {
                    let mut stdout = String::new();
                    let mut stderr = String::new();

                    if let Some(mut out) = child.stdout.take() {
                        let _ = out.read_to_string(&mut stdout);
                    }
                    if let Some(mut err) = child.stderr.take() {
                        let _ = err.read_to_string(&mut stderr);
                    }

                    return (stdout, status.success(), stderr);
                }
                Ok(None) => {
                    if start.elapsed() > timeout {
                        let _ = child.kill();
                        return (
                            String::new(),
                            false,
                            format!("Script timed out after {timeout_secs} seconds"),
                        );
                    }
                    std::thread::sleep(Duration::from_millis(100));
                }
                Err(e) => {
                    return (
                        String::new(),
                        false,
                        format!("Failed to wait for script: {e}"),
                    );
                }
            }
        }
    }
}
