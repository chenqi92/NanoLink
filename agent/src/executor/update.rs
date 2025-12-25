use std::collections::HashMap;
use std::env;
use std::path::{Path, PathBuf};
use tracing::info;

use crate::config::UpdateConfig;
use crate::proto::{CommandResult, UpdateInfo};

/// Agent version from Cargo.toml
pub const AGENT_VERSION: &str = env!("CARGO_PKG_VERSION");

/// Update executor for agent self-upgrade operations
pub struct UpdateExecutor {
    config: UpdateConfig,
}

impl UpdateExecutor {
    /// Create a new update executor
    pub fn new(config: UpdateConfig) -> Self {
        Self { config }
    }

    /// Get current agent version info
    pub async fn get_version(&self) -> CommandResult {
        info!("[AUDIT] GetVersion requested");

        CommandResult {
            command_id: String::new(),
            success: true,
            output: format!("Agent version: {AGENT_VERSION}"),
            error: String::new(),
            file_content: vec![],
            processes: vec![],
            containers: vec![],
            update_info: Some(UpdateInfo {
                current_version: AGENT_VERSION.to_string(),
                latest_version: String::new(),
                update_available: false,
                download_url: String::new(),
                changelog: String::new(),
                release_date: String::new(),
                download_size: 0,
                checksum: String::new(),
                min_version: String::new(),
            }),
        }
    }

    /// Check for available updates from GitHub releases
    pub async fn check_update(&self) -> CommandResult {
        info!("[AUDIT] CheckUpdate requested");

        let repo = &self.config.repo;
        let api_url = format!("https://api.github.com/repos/{repo}/releases/latest");

        match self.fetch_latest_release(&api_url).await {
            Ok(release) => {
                let update_available = self.is_newer_version(&release.tag_name, AGENT_VERSION);

                CommandResult {
                    command_id: String::new(),
                    success: true,
                    output: if update_available {
                        format!(
                            "Update available: {} -> {}",
                            AGENT_VERSION, release.tag_name
                        )
                    } else {
                        format!("Agent is up to date ({AGENT_VERSION})")
                    },
                    error: String::new(),
                    file_content: vec![],
                    processes: vec![],
                    containers: vec![],
                    update_info: Some(UpdateInfo {
                        current_version: AGENT_VERSION.to_string(),
                        latest_version: release.tag_name.clone(),
                        update_available,
                        download_url: self.get_download_url(&release),
                        changelog: release.body.unwrap_or_default(),
                        release_date: release.published_at.unwrap_or_default(),
                        download_size: 0,
                        checksum: String::new(),
                        min_version: String::new(),
                    }),
                }
            }
            Err(e) => Self::error_result(format!("Failed to check for updates: {e}")),
        }
    }

    /// Download update package
    pub async fn download_update(&self, params: &HashMap<String, String>) -> CommandResult {
        info!("[AUDIT] DownloadUpdate requested");

        let download_url = match params.get("url") {
            Some(url) => url.clone(),
            None => {
                // Fetch latest release URL
                let repo = &self.config.repo;
                let api_url = format!("https://api.github.com/repos/{repo}/releases/latest");

                match self.fetch_latest_release(&api_url).await {
                    Ok(release) => self.get_download_url(&release),
                    Err(e) => {
                        return Self::error_result(format!("Failed to get download URL: {e}"))
                    }
                }
            }
        };

        if download_url.is_empty() {
            return Self::error_result(
                "No download URL available for current platform".to_string(),
            );
        }

        // Download to temp directory
        let temp_dir = env::temp_dir();
        let download_path = temp_dir.join("nanolink-agent-update");

        #[cfg(windows)]
        let download_path = download_path.with_extension("exe");

        match self.download_file(&download_url, &download_path).await {
            Ok(size) => CommandResult {
                command_id: String::new(),
                success: true,
                output: format!("Downloaded {} bytes to {}", size, download_path.display()),
                error: String::new(),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
                update_info: Some(UpdateInfo {
                    current_version: AGENT_VERSION.to_string(),
                    latest_version: String::new(),
                    update_available: true,
                    download_url,
                    changelog: String::new(),
                    release_date: String::new(),
                    download_size: size as i64,
                    checksum: String::new(),
                    min_version: String::new(),
                }),
            },
            Err(e) => Self::error_result(format!("Failed to download update: {e}")),
        }
    }

    /// Apply update and restart agent
    pub async fn apply_update(&self, params: &HashMap<String, String>) -> CommandResult {
        info!("[AUDIT] ApplyUpdate requested");

        let update_path = match params.get("path") {
            Some(p) => PathBuf::from(p),
            None => {
                let temp_dir = env::temp_dir();
                let path = temp_dir.join("nanolink-agent-update");
                #[cfg(windows)]
                let path = path.with_extension("exe");
                path
            }
        };

        if !update_path.exists() {
            return Self::error_result(format!(
                "Update file not found: {}. Run download_update first.",
                update_path.display()
            ));
        }

        // Get current binary path
        let current_exe = match env::current_exe() {
            Ok(p) => p,
            Err(e) => return Self::error_result(format!("Failed to get current exe path: {e}")),
        };

        // Create backup of current binary
        let backup_path = current_exe.with_extension("bak");

        info!(
            "Applying update: {} -> {}",
            update_path.display(),
            current_exe.display()
        );

        // Platform-specific update logic
        #[cfg(unix)]
        {
            self.apply_update_unix(&update_path, &current_exe, &backup_path)
                .await
        }

        #[cfg(windows)]
        {
            self.apply_update_windows(&update_path, &current_exe, &backup_path)
                .await
        }
    }

    #[cfg(unix)]
    async fn apply_update_unix(
        &self,
        update_path: &Path,
        current_exe: &Path,
        backup_path: &Path,
    ) -> CommandResult {
        use std::fs;
        use std::os::unix::fs::PermissionsExt;
        use tracing::warn;

        // Backup current binary
        if let Err(e) = fs::copy(current_exe, backup_path) {
            return Self::error_result(format!("Failed to create backup: {}", e));
        }

        // Replace binary
        if let Err(e) = fs::copy(update_path, current_exe) {
            // Restore backup
            let _ = fs::copy(backup_path, current_exe);
            return Self::error_result(format!("Failed to replace binary: {}", e));
        }

        // Set executable permissions
        if let Err(e) = fs::set_permissions(current_exe, fs::Permissions::from_mode(0o755)) {
            warn!("Failed to set permissions: {}", e);
        }

        // Clean up downloaded file
        let _ = fs::remove_file(update_path);

        CommandResult {
            command_id: String::new(),
            success: true,
            output: "Update applied successfully. Agent will restart.".to_string(),
            error: String::new(),
            file_content: vec![],
            processes: vec![],
            containers: vec![],
            update_info: None,
        }
    }

    #[cfg(windows)]
    async fn apply_update_windows(
        &self,
        update_path: &Path,
        current_exe: &Path,
        backup_path: &Path,
    ) -> CommandResult {
        use std::fs;
        use std::process::Command;

        // On Windows, we can't replace a running binary directly
        // Create a batch script to replace the binary after agent exits
        let script_path = env::temp_dir().join("nanolink-update.bat");
        let script_content = format!(
            r#"@echo off
timeout /t 2 /nobreak >nul
copy /Y "{}" "{}"
del /F "{}"
net start NanoLinkAgent
del /F "%~f0"
"#,
            update_path.display(),
            current_exe.display(),
            update_path.display()
        );

        if let Err(e) = fs::write(&script_path, script_content) {
            return Self::error_result(format!("Failed to create update script: {e}"));
        }

        // Backup current binary
        if let Err(e) = fs::copy(current_exe, backup_path) {
            return Self::error_result(format!("Failed to create backup: {e}"));
        }

        // Launch update script in background
        match Command::new("cmd")
            .args(["/C", "start", "/MIN", "", script_path.to_str().unwrap()])
            .spawn()
        {
            Ok(_) => CommandResult {
                command_id: String::new(),
                success: true,
                output: "Update scheduled. Agent will restart shortly.".to_string(),
                error: String::new(),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
                update_info: None,
            },
            Err(e) => Self::error_result(format!("Failed to launch update script: {e}")),
        }
    }

    /// Fetch latest release from GitHub API
    async fn fetch_latest_release(&self, api_url: &str) -> Result<GitHubRelease, String> {
        // Use reqwest or hyper to fetch - for simplicity, use std::process::Command with curl
        #[cfg(unix)]
        {
            use std::process::Command;

            let output = Command::new("curl")
                .args(["-sL", "-H", "User-Agent: NanoLink-Agent", api_url])
                .output()
                .map_err(|e| format!("Failed to execute curl: {}", e))?;

            if !output.status.success() {
                return Err(format!(
                    "curl failed: {}",
                    String::from_utf8_lossy(&output.stderr)
                ));
            }

            let body = String::from_utf8_lossy(&output.stdout);
            serde_json::from_str(&body).map_err(|e| format!("Failed to parse response: {}", e))
        }

        #[cfg(windows)]
        {
            use std::process::Command;

            let output = Command::new("powershell")
                .args([
                    "-Command",
                    &format!(
                        "Invoke-RestMethod -Uri '{api_url}' -Headers @{{'User-Agent'='NanoLink-Agent'}} | ConvertTo-Json -Depth 10"
                    ),
                ])
                .output()
                .map_err(|e| format!("Failed to execute PowerShell: {e}"))?;

            if !output.status.success() {
                return Err(format!(
                    "PowerShell failed: {}",
                    String::from_utf8_lossy(&output.stderr)
                ));
            }

            let body = String::from_utf8_lossy(&output.stdout);
            serde_json::from_str(&body).map_err(|e| format!("Failed to parse response: {e}"))
        }
    }

    /// Download file from URL
    async fn download_file(&self, url: &str, dest: &Path) -> Result<usize, String> {
        #[cfg(unix)]
        {
            use std::process::Command;

            let output = Command::new("curl")
                .args(["-sL", "-o", dest.to_str().unwrap(), url])
                .output()
                .map_err(|e| format!("Failed to execute curl: {}", e))?;

            if !output.status.success() {
                return Err(format!(
                    "curl failed: {}",
                    String::from_utf8_lossy(&output.stderr)
                ));
            }

            std::fs::metadata(dest)
                .map(|m| m.len() as usize)
                .map_err(|e| format!("Failed to get file size: {}", e))
        }

        #[cfg(windows)]
        {
            use std::process::Command;

            let output = Command::new("powershell")
                .args([
                    "-Command",
                    &format!(
                        "Invoke-WebRequest -Uri '{}' -OutFile '{}'",
                        url,
                        dest.display()
                    ),
                ])
                .output()
                .map_err(|e| format!("Failed to execute PowerShell: {e}"))?;

            if !output.status.success() {
                return Err(format!(
                    "PowerShell failed: {}",
                    String::from_utf8_lossy(&output.stderr)
                ));
            }

            std::fs::metadata(dest)
                .map(|m| m.len() as usize)
                .map_err(|e| format!("Failed to get file size: {e}"))
        }
    }

    /// Get platform-specific download URL from release
    fn get_download_url(&self, release: &GitHubRelease) -> String {
        let os = env::consts::OS;
        let arch = env::consts::ARCH;

        let target_name = match (os, arch) {
            ("linux", "x86_64") => "nanolink-agent-linux-x86_64",
            ("linux", "aarch64") => "nanolink-agent-linux-aarch64",
            ("macos", "x86_64") => "nanolink-agent-macos-x86_64",
            ("macos", "aarch64") => "nanolink-agent-macos-aarch64",
            ("windows", "x86_64") => "nanolink-agent-windows-x86_64.exe",
            _ => return String::new(),
        };

        release
            .assets
            .iter()
            .find(|a| a.name.contains(target_name))
            .map(|a| a.browser_download_url.clone())
            .unwrap_or_default()
    }

    /// Compare version strings (semantic versioning)
    fn is_newer_version(&self, latest: &str, current: &str) -> bool {
        let latest = latest.trim_start_matches('v');
        let current = current.trim_start_matches('v');

        let parse_version = |v: &str| -> Vec<u32> {
            v.split('.')
                .filter_map(|s| s.split('-').next())
                .filter_map(|s| s.parse().ok())
                .collect()
        };

        let latest_parts = parse_version(latest);
        let current_parts = parse_version(current);

        for i in 0..3 {
            let l = latest_parts.get(i).copied().unwrap_or(0);
            let c = current_parts.get(i).copied().unwrap_or(0);
            if l > c {
                return true;
            }
            if l < c {
                return false;
            }
        }
        false
    }

    fn error_result(error: String) -> CommandResult {
        CommandResult {
            command_id: String::new(),
            success: false,
            output: String::new(),
            error,
            file_content: vec![],
            processes: vec![],
            containers: vec![],
            update_info: None,
        }
    }
}

impl Default for UpdateExecutor {
    fn default() -> Self {
        Self::new(UpdateConfig::default())
    }
}

/// GitHub release structure (simplified)
#[derive(Debug, serde::Deserialize)]
struct GitHubRelease {
    tag_name: String,
    body: Option<String>,
    published_at: Option<String>,
    assets: Vec<GitHubAsset>,
}

#[derive(Debug, serde::Deserialize)]
struct GitHubAsset {
    name: String,
    browser_download_url: String,
}
