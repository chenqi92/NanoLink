use std::collections::HashMap;
use std::env;
use std::path::{Path, PathBuf};
use tracing::{info, warn};

use crate::config::{UpdateConfig, UpdateSource};
use crate::proto::{CommandResult, UpdateInfo};

/// Validate URL to prevent command injection
fn is_safe_url(url: &str) -> bool {
    // Only allow http/https URLs
    if !url.starts_with("http://") && !url.starts_with("https://") {
        return false;
    }
    // Reject URLs with shell metacharacters
    !url.chars().any(|c| {
        matches!(
            c,
            '\'' | '"' | '`' | '$' | '\\' | ';' | '|' | '&' | '\n' | '\r'
        )
    })
}

/// Escape path for safe use in shell commands
fn escape_path(path: &Path) -> Result<String, String> {
    let s = path
        .to_str()
        .ok_or_else(|| "Path contains invalid UTF-8".to_string())?;
    // Check for dangerous characters
    if s.chars().any(|c| {
        matches!(
            c,
            '\'' | '"' | '`' | '$' | '\\' | ';' | '|' | '&' | '\n' | '\r'
        )
    }) {
        return Err("Path contains unsafe characters".to_string());
    }
    Ok(s.to_string())
}

/// Calculate SHA256 checksum of a file
fn calculate_sha256(path: &Path) -> Result<String, String> {
    use std::fs::File;
    use std::io::{BufReader, Read};

    let file = File::open(path).map_err(|e| format!("Failed to open file: {e}"))?;
    let mut reader = BufReader::new(file);
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 8192];

    loop {
        let bytes_read = reader
            .read(&mut buffer)
            .map_err(|e| format!("Failed to read file: {e}"))?;
        if bytes_read == 0 {
            break;
        }
        hasher.update(&buffer[..bytes_read]);
    }

    let hash = hasher.finalize();
    Ok(hash.iter().map(|b| format!("{b:02x}")).collect())
}

/// Simple SHA256 implementation (no external dependency)
struct Sha256 {
    state: [u32; 8],
    buffer: Vec<u8>,
    total_len: u64,
}

impl Sha256 {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2,
    ];

    fn new() -> Self {
        Self {
            state: [
                0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
                0x5be0cd19,
            ],
            buffer: Vec::new(),
            total_len: 0,
        }
    }

    fn update(&mut self, data: &[u8]) {
        self.buffer.extend_from_slice(data);
        self.total_len += data.len() as u64;

        while self.buffer.len() >= 64 {
            let chunk: [u8; 64] = self.buffer[..64].try_into().unwrap();
            self.process_block(&chunk);
            self.buffer.drain(..64);
        }
    }

    #[allow(clippy::needless_range_loop)]
    fn process_block(&mut self, block: &[u8; 64]) {
        let mut w = [0u32; 64];
        for (i, chunk) in block.chunks(4).enumerate() {
            w[i] = u32::from_be_bytes(chunk.try_into().unwrap());
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }

        let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut h] = self.state;

        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = h
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(Self::K[i])
                .wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);

            h = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }

        self.state[0] = self.state[0].wrapping_add(a);
        self.state[1] = self.state[1].wrapping_add(b);
        self.state[2] = self.state[2].wrapping_add(c);
        self.state[3] = self.state[3].wrapping_add(d);
        self.state[4] = self.state[4].wrapping_add(e);
        self.state[5] = self.state[5].wrapping_add(f);
        self.state[6] = self.state[6].wrapping_add(g);
        self.state[7] = self.state[7].wrapping_add(h);
    }

    fn finalize(mut self) -> [u8; 32] {
        let bit_len = self.total_len * 8;
        self.buffer.push(0x80);
        while (self.buffer.len() % 64) != 56 {
            self.buffer.push(0);
        }
        self.buffer.extend_from_slice(&bit_len.to_be_bytes());

        while self.buffer.len() >= 64 {
            let chunk: [u8; 64] = self.buffer[..64].try_into().unwrap();
            self.process_block(&chunk);
            self.buffer.drain(..64);
        }

        let mut result = [0u8; 32];
        for (i, &val) in self.state.iter().enumerate() {
            result[i * 4..(i + 1) * 4].copy_from_slice(&val.to_be_bytes());
        }
        result
    }
}

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
            ..Default::default()
        }
    }

    /// Check for available updates based on configured source
    pub async fn check_update(&self) -> CommandResult {
        info!(
            "[AUDIT] CheckUpdate requested (source: {:?})",
            self.config.source
        );

        match self.fetch_release_info().await {
            Ok(release) => {
                let update_available = self.is_newer_version(&release.version, AGENT_VERSION);

                CommandResult {
                    command_id: String::new(),
                    success: true,
                    output: if update_available {
                        format!("Update available: {} -> {}", AGENT_VERSION, release.version)
                    } else {
                        format!("Agent is up to date ({AGENT_VERSION})")
                    },
                    error: String::new(),
                    update_info: Some(UpdateInfo {
                        current_version: AGENT_VERSION.to_string(),
                        latest_version: release.version.clone(),
                        update_available,
                        download_url: release.download_url,
                        changelog: release.changelog,
                        release_date: release.release_date,
                        download_size: 0,
                        checksum: String::new(),
                        min_version: String::new(),
                    }),
                    ..Default::default()
                }
            }
            Err(e) => Self::error_result(format!("Failed to check for updates: {e}")),
        }
    }

    /// Fetch release info based on configured source
    async fn fetch_release_info(&self) -> Result<ReleaseInfo, String> {
        match self.config.source {
            UpdateSource::Github => self.fetch_github_release().await,
            UpdateSource::Cloudflare => self.fetch_cloudflare_release().await,
            UpdateSource::Custom => self.fetch_custom_release().await,
        }
    }

    /// Fetch release from GitHub
    async fn fetch_github_release(&self) -> Result<ReleaseInfo, String> {
        let repo = &self.config.repo;
        let api_url = format!("https://api.github.com/repos/{repo}/releases/latest");

        let release = self.fetch_latest_release(&api_url).await?;
        let download_url = self.get_github_download_url(&release);

        Ok(ReleaseInfo {
            version: release.tag_name.trim_start_matches('v').to_string(),
            changelog: release.body.unwrap_or_default(),
            release_date: release.published_at.unwrap_or_default(),
            download_url,
            checksum: None, // GitHub releases don't include checksums in API
        })
    }

    /// Fetch release from Cloudflare R2
    async fn fetch_cloudflare_release(&self) -> Result<ReleaseInfo, String> {
        let version_url = "https://agent.download.kkape.cn/newest/version.json";

        let release = self.fetch_cloudflare_version(version_url).await?;
        let download_url = self.get_cloudflare_download_url(&release);
        let checksum = Self::get_platform_checksum(&release);

        Ok(ReleaseInfo {
            version: release.version.trim_start_matches('v').to_string(),
            changelog: release.changelog.unwrap_or_default(),
            release_date: release.release_date.unwrap_or_default(),
            download_url,
            checksum,
        })
    }

    /// Fetch release from custom URL
    async fn fetch_custom_release(&self) -> Result<ReleaseInfo, String> {
        let base_url = self
            .config
            .custom_url
            .as_ref()
            .ok_or_else(|| "Custom source requires custom_url to be set".to_string())?;

        let version_url = format!("{}/version.json", base_url.trim_end_matches('/'));

        let release = self.fetch_cloudflare_version(&version_url).await?;
        let download_url = self.get_custom_download_url(base_url, &release);
        let checksum = Self::get_platform_checksum(&release);

        Ok(ReleaseInfo {
            version: release.version.trim_start_matches('v').to_string(),
            changelog: release.changelog.unwrap_or_default(),
            release_date: release.release_date.unwrap_or_default(),
            download_url,
            checksum,
        })
    }

    /// Get platform-specific checksum from release
    fn get_platform_checksum(release: &CloudflareRelease) -> Option<String> {
        let platform = Self::get_platform_identifier()?;
        release.checksums.get(platform).cloned()
    }

    /// Fetch Cloudflare version.json
    async fn fetch_cloudflare_version(&self, url: &str) -> Result<CloudflareRelease, String> {
        #[cfg(unix)]
        {
            use std::process::Command;

            let output = Command::new("curl")
                .args(["-sL", "-H", "User-Agent: NanoLink-Agent", url])
                .output()
                .map_err(|e| format!("Failed to execute curl: {e}"))?;

            if !output.status.success() {
                return Err(format!(
                    "curl failed: {}",
                    String::from_utf8_lossy(&output.stderr)
                ));
            }

            let body = String::from_utf8_lossy(&output.stdout);
            serde_json::from_str(&body).map_err(|e| format!("Failed to parse response: {e}"))
        }

        #[cfg(windows)]
        {
            use std::process::Command;

            let output = Command::new("powershell")
                .args([
                    "-Command",
                    &format!(
                        "Invoke-RestMethod -Uri '{url}' -Headers @{{'User-Agent'='NanoLink-Agent'}} | ConvertTo-Json -Depth 10"
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

    /// Download update package
    pub async fn download_update(&self, params: &HashMap<String, String>) -> CommandResult {
        info!("[AUDIT] DownloadUpdate requested");

        let download_url = match params.get("url") {
            Some(url) => url.clone(),
            None => {
                // Fetch latest release URL using configured source
                match self.fetch_release_info().await {
                    Ok(release) => release.download_url,
                    Err(e) => {
                        return Self::error_result(format!("Failed to get download URL: {e}"));
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
                ..Default::default()
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

        // Verify checksum if provided
        if let Some(expected_checksum) = params.get("checksum") {
            info!("Verifying checksum...");
            match calculate_sha256(&update_path) {
                Ok(actual_checksum) => {
                    if actual_checksum.to_lowercase() != expected_checksum.to_lowercase() {
                        return Self::error_result(format!(
                            "Checksum mismatch! Expected: {expected_checksum}, Got: {actual_checksum}. Update file may be corrupted or tampered."
                        ));
                    }
                    info!("Checksum verified successfully");
                }
                Err(e) => {
                    return Self::error_result(format!("Failed to calculate checksum: {e}"));
                }
            }
        } else {
            warn!("No checksum provided, skipping verification (not recommended)");
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

        // Backup current binary
        if let Err(e) = fs::copy(current_exe, backup_path) {
            return Self::error_result(format!("Failed to create backup: {e}"));
        }

        // Replace binary
        if let Err(e) = fs::copy(update_path, current_exe) {
            // Restore backup and log the error
            if let Err(restore_err) = fs::copy(backup_path, current_exe) {
                warn!("Failed to restore backup after update failure: {restore_err}");
            }
            return Self::error_result(format!("Failed to replace binary: {e}"));
        }

        // Set executable permissions
        if let Err(e) = fs::set_permissions(current_exe, fs::Permissions::from_mode(0o755)) {
            warn!("Failed to set permissions: {e}");
        }

        // Clean up downloaded file
        if let Err(e) = fs::remove_file(update_path) {
            warn!("Failed to clean up downloaded file: {e}");
        }

        // Clean up backup file after successful update
        if let Err(e) = fs::remove_file(backup_path) {
            warn!("Failed to clean up backup file: {e}");
        }

        CommandResult {
            command_id: String::new(),
            success: true,
            output: "Update applied successfully. Agent will restart.".to_string(),
            error: String::new(),
            ..Default::default()
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

        // Validate paths to prevent injection
        let update_path_str = match escape_path(update_path) {
            Ok(s) => s,
            Err(e) => return Self::error_result(format!("Invalid update path: {e}")),
        };
        let current_exe_str = match escape_path(current_exe) {
            Ok(s) => s,
            Err(e) => return Self::error_result(format!("Invalid executable path: {e}")),
        };

        // On Windows, we can't replace a running binary directly
        // Create a batch script to replace the binary after agent exits
        // Use delayed expansion to avoid injection issues
        let script_path = env::temp_dir().join("nanolink-update.bat");
        let script_content = format!(
            r#"@echo off
setlocal EnableDelayedExpansion
set "UPDATE_SRC={update_path_str}"
set "UPDATE_DST={current_exe_str}"
timeout /t 3 /nobreak >nul
copy /Y "!UPDATE_SRC!" "!UPDATE_DST!"
if errorlevel 1 (
    echo Update failed
    pause
    exit /b 1
)
del /F "!UPDATE_SRC!"
net start NanoLinkAgent
del /F "%~f0"
"#
        );

        if let Err(e) = fs::write(&script_path, &script_content) {
            return Self::error_result(format!("Failed to create update script: {e}"));
        }

        // Backup current binary
        if let Err(e) = fs::copy(current_exe, backup_path) {
            // Clean up script file
            if let Err(cleanup_err) = fs::remove_file(&script_path) {
                warn!("Failed to clean up script file: {cleanup_err}");
            }
            return Self::error_result(format!("Failed to create backup: {e}"));
        }

        // Get script path as string
        let script_path_str = match escape_path(&script_path) {
            Ok(s) => s,
            Err(e) => return Self::error_result(format!("Invalid script path: {e}")),
        };

        // Launch update script in background
        match Command::new("cmd")
            .args(["/C", "start", "/MIN", "", &script_path_str])
            .spawn()
        {
            Ok(_) => CommandResult {
                command_id: String::new(),
                success: true,
                output: "Update scheduled. Agent will restart shortly.".to_string(),
                error: String::new(),
                ..Default::default()
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
        // Validate URL to prevent command injection
        if !is_safe_url(url) {
            return Err("Invalid or unsafe URL".to_string());
        }

        // Validate destination path
        let dest_str = escape_path(dest)?;

        #[cfg(unix)]
        {
            use std::process::Command;

            let output = Command::new("curl")
                .args(["-sL", "-o", &dest_str, url])
                .output()
                .map_err(|e| format!("Failed to execute curl: {e}"))?;

            if !output.status.success() {
                return Err(format!(
                    "curl failed: {}",
                    String::from_utf8_lossy(&output.stderr)
                ));
            }

            std::fs::metadata(dest)
                .map(|m| m.len() as usize)
                .map_err(|e| format!("Failed to get file size: {e}"))
        }

        #[cfg(windows)]
        {
            use std::process::Command;

            // Use argument array instead of string interpolation to prevent injection
            let script = "$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri $args[0] -OutFile $args[1]";

            let output = Command::new("powershell")
                .args(["-Command", script, url, &dest_str])
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

    /// Get platform identifier for downloads
    fn get_platform_identifier() -> Option<&'static str> {
        let os = env::consts::OS;
        let arch = env::consts::ARCH;

        match (os, arch) {
            ("linux", "x86_64") => Some("linux-x86_64"),
            ("linux", "aarch64") => Some("linux-aarch64"),
            ("macos", "x86_64") => Some("macos-x86_64"),
            ("macos", "aarch64") => Some("macos-aarch64"),
            ("windows", "x86_64") => Some("windows-x86_64"),
            _ => None,
        }
    }

    /// Get platform-specific binary name
    fn get_binary_name() -> Option<String> {
        let platform = Self::get_platform_identifier()?;
        let name = format!("nanolink-agent-{platform}");
        if cfg!(windows) {
            Some(format!("{name}.exe"))
        } else {
            Some(name)
        }
    }

    /// Get platform-specific download URL from GitHub release
    fn get_github_download_url(&self, release: &GitHubRelease) -> String {
        let binary_name = match Self::get_binary_name() {
            Some(name) => name,
            None => return String::new(),
        };

        release
            .assets
            .iter()
            .find(|a| a.name.contains(&binary_name))
            .map(|a| a.browser_download_url.clone())
            .unwrap_or_default()
    }

    /// Get platform-specific download URL from Cloudflare release
    fn get_cloudflare_download_url(&self, release: &CloudflareRelease) -> String {
        let platform = match Self::get_platform_identifier() {
            Some(p) => p,
            None => return String::new(),
        };

        // Try to get from assets map first
        if let Some(asset_name) = release.assets.get(platform) {
            return format!("https://agent.download.kkape.cn/newest/{asset_name}");
        }

        // Fallback to default naming
        let binary_name = Self::get_binary_name().unwrap_or_default();
        format!("https://agent.download.kkape.cn/newest/{binary_name}")
    }

    /// Get platform-specific download URL from custom source
    fn get_custom_download_url(&self, base_url: &str, release: &CloudflareRelease) -> String {
        let platform = match Self::get_platform_identifier() {
            Some(p) => p,
            None => return String::new(),
        };

        let base = base_url.trim_end_matches('/');

        // Try to get from assets map first
        if let Some(asset_name) = release.assets.get(platform) {
            return format!("{base}/{asset_name}");
        }

        // Fallback to default naming
        let binary_name = Self::get_binary_name().unwrap_or_default();
        format!("{base}/{binary_name}")
    }

    /// Compare version strings (semantic versioning)
    ///
    /// Supports:
    /// - Standard semver: 1.2.3, 1.2.3.4
    /// - Pre-release versions: 1.2.3-beta.1, 1.2.3-rc.2
    /// - v prefix: v1.2.3
    fn is_newer_version(&self, latest: &str, current: &str) -> bool {
        let latest = latest.trim_start_matches('v');
        let current = current.trim_start_matches('v');

        // Split version and pre-release parts
        let (latest_ver, latest_pre) = Self::split_version_prerelease(latest);
        let (current_ver, current_pre) = Self::split_version_prerelease(current);

        let parse_version =
            |v: &str| -> Vec<u32> { v.split('.').filter_map(|s| s.parse().ok()).collect() };

        let latest_parts = parse_version(latest_ver);
        let current_parts = parse_version(current_ver);

        // Compare all version parts (not just first 3)
        let max_len = latest_parts.len().max(current_parts.len());
        for i in 0..max_len {
            let l = latest_parts.get(i).copied().unwrap_or(0);
            let c = current_parts.get(i).copied().unwrap_or(0);
            if l > c {
                return true;
            }
            if l < c {
                return false;
            }
        }

        // If version numbers are equal, compare pre-release
        // A release version (no pre-release) is newer than any pre-release
        match (latest_pre, current_pre) {
            (None, Some(_)) => true,  // 1.0.0 > 1.0.0-beta
            (Some(_), None) => false, // 1.0.0-beta < 1.0.0
            (None, None) => false,    // Same version
            (Some(l), Some(c)) => Self::compare_prerelease(l, c) > 0,
        }
    }

    /// Split version string into version and pre-release parts
    fn split_version_prerelease(v: &str) -> (&str, Option<&str>) {
        if let Some(pos) = v.find('-') {
            (&v[..pos], Some(&v[pos + 1..]))
        } else {
            (v, None)
        }
    }

    /// Compare pre-release identifiers
    /// Returns: positive if a > b, negative if a < b, 0 if equal
    fn compare_prerelease(a: &str, b: &str) -> i32 {
        let a_parts: Vec<&str> = a.split('.').collect();
        let b_parts: Vec<&str> = b.split('.').collect();

        let max_len = a_parts.len().max(b_parts.len());
        for i in 0..max_len {
            let a_part = a_parts.get(i).copied().unwrap_or("");
            let b_part = b_parts.get(i).copied().unwrap_or("");

            // Try to parse as numbers
            match (a_part.parse::<u32>(), b_part.parse::<u32>()) {
                (Ok(a_num), Ok(b_num)) => {
                    if a_num != b_num {
                        return if a_num > b_num { 1 } else { -1 };
                    }
                }
                (Ok(_), Err(_)) => return 1,  // Numeric > non-numeric
                (Err(_), Ok(_)) => return -1, // Non-numeric < numeric
                (Err(_), Err(_)) => {
                    // String comparison
                    match a_part.cmp(b_part) {
                        std::cmp::Ordering::Greater => return 1,
                        std::cmp::Ordering::Less => return -1,
                        std::cmp::Ordering::Equal => {}
                    }
                }
            }
        }
        0
    }

    fn error_result(error: String) -> CommandResult {
        CommandResult {
            command_id: String::new(),
            success: false,
            output: String::new(),
            error,
            ..Default::default()
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

/// Cloudflare R2 version info structure
#[derive(Debug, serde::Deserialize)]
struct CloudflareRelease {
    version: String,
    release_date: Option<String>,
    changelog: Option<String>,
    assets: HashMap<String, String>,
    /// Optional checksums map: platform -> sha256
    #[serde(default)]
    checksums: HashMap<String, String>,
}

/// Generic release info for internal use
#[derive(Debug)]
struct ReleaseInfo {
    version: String,
    changelog: String,
    release_date: String,
    download_url: String,
    /// SHA256 checksum (if available)
    #[allow(dead_code)]
    checksum: Option<String>,
}
