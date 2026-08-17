use std::collections::HashMap;
use std::process::Command;
use std::sync::Arc;
use tracing::{info, warn};

use crate::config::Config;
use crate::proto::{CommandResult, PackageInfo};

/// Package manager executor with multi-platform support
pub struct PackageManager {
    config: Arc<Config>,
    package_manager_type: PackageManagerType,
}

#[derive(Debug, Clone, Copy)]
#[allow(dead_code)] // Some variants only used on specific platforms
enum PackageManagerType {
    Apt,    // Debian/Ubuntu
    Yum,    // CentOS/RHEL
    Dnf,    // Fedora
    Pacman, // Arch Linux
    Brew,   // macOS
    Winget, // Windows
    Choco,  // Windows Chocolatey
    Unknown,
}

impl PackageManager {
    /// Create a new package manager
    pub fn new(config: Arc<Config>) -> Self {
        let package_manager_type = Self::detect_package_manager();
        info!("Detected package manager: {:?}", package_manager_type);
        Self {
            config,
            package_manager_type,
        }
    }

    /// Detect the system's package manager
    fn detect_package_manager() -> PackageManagerType {
        #[cfg(target_os = "linux")]
        {
            // Check for apt (Debian/Ubuntu) - verify both execution and exit status
            if let Ok(output) = Command::new("apt").arg("--version").output() {
                if output.status.success() {
                    return PackageManagerType::Apt;
                }
            }
            // Check for dnf (Fedora)
            if let Ok(output) = Command::new("dnf").arg("--version").output() {
                if output.status.success() {
                    return PackageManagerType::Dnf;
                }
            }
            // Check for yum (CentOS/RHEL)
            if let Ok(output) = Command::new("yum").arg("--version").output() {
                if output.status.success() {
                    return PackageManagerType::Yum;
                }
            }
            // Check for pacman (Arch)
            if let Ok(output) = Command::new("pacman").arg("--version").output() {
                if output.status.success() {
                    return PackageManagerType::Pacman;
                }
            }
        }

        #[cfg(target_os = "macos")]
        {
            if let Ok(output) = Command::new("brew").arg("--version").output() {
                if output.status.success() {
                    return PackageManagerType::Brew;
                }
            }
        }

        #[cfg(target_os = "windows")]
        {
            // Check for winget
            if let Ok(output) = Command::new("winget").arg("--version").output() {
                if output.status.success() {
                    return PackageManagerType::Winget;
                }
            }
            // Check for chocolatey
            if let Ok(output) = Command::new("choco").arg("--version").output() {
                if output.status.success() {
                    return PackageManagerType::Choco;
                }
            }
        }

        PackageManagerType::Unknown
    }

    /// List installed packages
    pub async fn list_packages(&self, params: &HashMap<String, String>) -> CommandResult {
        if !self.config.package_management.enabled {
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: "Package management is disabled".to_string(),
                ..Default::default()
            };
        }

        let filter = params.get("filter").map(|s| s.as_str());
        let limit = params
            .get("limit")
            .and_then(|s| s.parse().ok())
            .unwrap_or(100);

        let packages = match self.package_manager_type {
            PackageManagerType::Apt => self.list_apt_packages(filter, limit),
            PackageManagerType::Yum | PackageManagerType::Dnf => {
                self.list_yum_packages(filter, limit)
            }
            PackageManagerType::Pacman => self.list_pacman_packages(filter, limit),
            PackageManagerType::Brew => self.list_brew_packages(filter, limit),
            PackageManagerType::Winget => self.list_winget_packages(filter, limit),
            PackageManagerType::Choco => self.list_choco_packages(filter, limit),
            PackageManagerType::Unknown => {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: "No supported package manager found".to_string(),
                    ..Default::default()
                };
            }
        };

        match packages {
            Ok(pkgs) => {
                info!("Listed {} packages", pkgs.len());
                CommandResult {
                    command_id: String::new(),
                    success: true,
                    output: format!("Found {} packages", pkgs.len()),
                    error: String::new(),
                    packages: pkgs,
                    ..Default::default()
                }
            }
            Err(e) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: e,
                ..Default::default()
            },
        }
    }

    /// Check for available updates
    pub async fn check_updates(&self, _params: &HashMap<String, String>) -> CommandResult {
        if !self.config.package_management.enabled {
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: "Package management is disabled".to_string(),
                ..Default::default()
            };
        }

        let packages = match self.package_manager_type {
            PackageManagerType::Apt => self.check_apt_updates(),
            PackageManagerType::Yum | PackageManagerType::Dnf => self.check_yum_updates(),
            PackageManagerType::Pacman => self.check_pacman_updates(),
            PackageManagerType::Brew => self.check_brew_updates(),
            PackageManagerType::Winget => self.check_winget_updates(),
            PackageManagerType::Choco => self.check_choco_updates(),
            PackageManagerType::Unknown => {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: "No supported package manager found".to_string(),
                    ..Default::default()
                };
            }
        };

        match packages {
            Ok(pkgs) => {
                info!("Found {} packages with updates", pkgs.len());
                CommandResult {
                    command_id: String::new(),
                    success: true,
                    output: format!("{} packages have updates available", pkgs.len()),
                    error: String::new(),
                    packages: pkgs,
                    ..Default::default()
                }
            }
            Err(e) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: e,
                ..Default::default()
            },
        }
    }

    /// Install a package that is not currently present. This is deliberately
    /// separate from updates so policy, audit logs, and UI confirmations can
    /// distinguish adding new host software from patching an existing package.
    pub async fn install_package(&self, params: &HashMap<String, String>) -> CommandResult {
        if !self.config.package_management.enabled {
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: "Package management is disabled".to_string(),
                ..Default::default()
            };
        }
        if !self.config.package_management.allow_install {
            warn!("Package install attempted but allow_install is disabled");
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: "Package installation is disabled in configuration".to_string(),
                ..Default::default()
            };
        }

        let package_name = match params.get("package") {
            Some(package) => package,
            None => {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: "Package name is required".to_string(),
                    ..Default::default()
                };
            }
        };
        if !Self::is_valid_package_name(package_name) {
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: "Invalid package name".to_string(),
                ..Default::default()
            };
        }
        let allowlist = &self.config.package_management.allowed_install_packages;
        if !allowlist.is_empty() && !allowlist.iter().any(|allowed| allowed == package_name) {
            warn!("Package is not in install allowlist: {}", package_name);
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: "Package is not in the configured install allowlist".to_string(),
                ..Default::default()
            };
        }

        let refresh = params
            .get("refresh")
            .map(|value| value.eq_ignore_ascii_case("true"))
            .unwrap_or(false);
        info!("Installing package: {}", package_name);
        let result = match self.package_manager_type {
            PackageManagerType::Apt => self.install_apt_package(package_name, refresh),
            PackageManagerType::Yum | PackageManagerType::Dnf => {
                self.install_yum_package(package_name)
            }
            PackageManagerType::Pacman => self.install_pacman_package(package_name),
            PackageManagerType::Brew => self.install_brew_package(package_name),
            PackageManagerType::Winget => self.install_winget_package(package_name),
            PackageManagerType::Choco => self.install_choco_package(package_name),
            PackageManagerType::Unknown => Err("No supported package manager found".to_string()),
        };

        match result {
            Ok(mut output) => {
                let start = params
                    .get("start")
                    .map(|value| value.eq_ignore_ascii_case("true"))
                    .unwrap_or(false);
                if start {
                    match self.start_installed_service(package_name) {
                        Ok(service_output) => {
                            if !output.ends_with('\n') {
                                output.push('\n');
                            }
                            output.push_str(&service_output);
                        }
                        Err(error) => {
                            return CommandResult {
                                command_id: String::new(),
                                success: false,
                                output,
                                error,
                                ..Default::default()
                            };
                        }
                    }
                }
                CommandResult {
                    command_id: String::new(),
                    success: true,
                    output,
                    error: String::new(),
                    ..Default::default()
                }
            }
            Err(error) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error,
                ..Default::default()
            },
        }
    }

    /// Update a specific package (dangerous operation, requires SYSTEM_ADMIN)
    pub async fn update_package(&self, params: &HashMap<String, String>) -> CommandResult {
        if !self.config.package_management.enabled {
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: "Package management is disabled".to_string(),
                ..Default::default()
            };
        }

        if !self.config.package_management.allow_update {
            warn!("Package update attempted but allow_update is disabled");
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: "Package updates are disabled in configuration".to_string(),
                ..Default::default()
            };
        }

        let package_name = match params.get("package") {
            Some(p) => p,
            None => {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: "Package name is required".to_string(),
                    ..Default::default()
                };
            }
        };

        // Validate package name
        if !Self::is_valid_package_name(package_name) {
            warn!("Invalid package name: {}", package_name);
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: "Invalid package name".to_string(),
                ..Default::default()
            };
        }

        info!("Updating package: {}", package_name);

        let result = match self.package_manager_type {
            PackageManagerType::Apt => self.update_apt_package(package_name),
            PackageManagerType::Yum | PackageManagerType::Dnf => {
                self.update_yum_package(package_name)
            }
            PackageManagerType::Pacman => self.update_pacman_package(package_name),
            PackageManagerType::Brew => self.update_brew_package(package_name),
            PackageManagerType::Winget => self.update_winget_package(package_name),
            PackageManagerType::Choco => self.update_choco_package(package_name),
            PackageManagerType::Unknown => {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: "No supported package manager found".to_string(),
                    ..Default::default()
                };
            }
        };

        match result {
            Ok(output) => {
                info!("Package {} updated successfully", package_name);
                CommandResult {
                    command_id: String::new(),
                    success: true,
                    output,
                    error: String::new(),
                    ..Default::default()
                }
            }
            Err(e) => {
                warn!("Failed to update package {}: {}", package_name, e);
                CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: e,
                    ..Default::default()
                }
            }
        }
    }

    /// Perform system update (very dangerous, requires SYSTEM_ADMIN)
    pub async fn system_update(&self, _params: &HashMap<String, String>) -> CommandResult {
        if !self.config.package_management.enabled {
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: "Package management is disabled".to_string(),
                ..Default::default()
            };
        }

        if !self.config.package_management.allow_system_update {
            warn!("System update attempted but allow_system_update is disabled");
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: "System updates are disabled in configuration".to_string(),
                ..Default::default()
            };
        }

        info!("Starting system update");

        let result = match self.package_manager_type {
            PackageManagerType::Apt => self.system_update_apt(),
            PackageManagerType::Yum | PackageManagerType::Dnf => self.system_update_yum(),
            PackageManagerType::Pacman => self.system_update_pacman(),
            PackageManagerType::Brew => self.system_update_brew(),
            PackageManagerType::Winget => self.system_update_winget(),
            PackageManagerType::Choco => self.system_update_choco(),
            PackageManagerType::Unknown => {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: "No supported package manager found".to_string(),
                    ..Default::default()
                };
            }
        };

        match result {
            Ok(output) => {
                info!("System update completed");
                CommandResult {
                    command_id: String::new(),
                    success: true,
                    output,
                    error: String::new(),
                    ..Default::default()
                }
            }
            Err(e) => {
                warn!("System update failed: {}", e);
                CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: e,
                    ..Default::default()
                }
            }
        }
    }

    /// Validate package name to prevent command injection
    fn is_valid_package_name(name: &str) -> bool {
        // Package name should only contain alphanumeric, dash, underscore, dot
        // Additional security checks:
        // - Cannot be empty or too long
        // - Cannot start or end with a dot (prevents hidden files and path issues)
        // - Cannot be "." or ".." (prevents path traversal)
        // - Cannot contain consecutive dots (prevents ".." embedded in name)
        // - Must start with alphanumeric character
        if name.is_empty() || name.len() > 255 {
            return false;
        }

        // Check for path traversal patterns
        if name == "." || name == ".." || name.contains("..") {
            return false;
        }

        // Must start with alphanumeric
        if !name
            .chars()
            .next()
            .map(|c| c.is_alphanumeric())
            .unwrap_or(false)
        {
            return false;
        }

        // Cannot end with a dot
        if name.ends_with('.') {
            return false;
        }

        // All characters must be alphanumeric, dash, underscore, or dot
        name.chars()
            .all(|c| c.is_alphanumeric() || c == '-' || c == '_' || c == '.')
    }

    fn command_output(output: std::process::Output, action: &str) -> Result<String, String> {
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        if output.status.success() {
            Ok(if stdout.is_empty() { stderr } else { stdout })
        } else {
            let detail = if stderr.is_empty() { stdout } else { stderr };
            Err(format!("{action} failed: {detail}"))
        }
    }

    fn start_installed_service(&self, package_name: &str) -> Result<String, String> {
        if package_name != "nginx" {
            return Err(format!(
                "Automatic service start is not supported for package '{package_name}'"
            ));
        }
        #[cfg(target_os = "linux")]
        {
            let output = Command::new("systemctl")
                .args(["enable", "--now", "nginx"])
                .output()
                .map_err(|e| format!("Failed to start nginx: {e}"))?;
            Self::command_output(output, "Starting nginx")?;
            return Ok("nginx enabled and started".to_string());
        }
        #[cfg(not(target_os = "linux"))]
        Err("Automatic nginx startup is only supported on Linux".to_string())
    }

    // ========== APT (Debian/Ubuntu) ==========
    fn list_apt_packages(
        &self,
        filter: Option<&str>,
        limit: usize,
    ) -> Result<Vec<PackageInfo>, String> {
        let output = Command::new("dpkg-query")
            .args(["-W", "-f", "${Package}\t${Version}\t${Status}\n"])
            .output()
            .map_err(|e| format!("Failed to run dpkg-query: {e}"))?;

        if !output.status.success() {
            return Err(String::from_utf8_lossy(&output.stderr).to_string());
        }

        let packages: Vec<PackageInfo> = String::from_utf8_lossy(&output.stdout)
            .lines()
            .filter(|line| filter.map(|f| line.contains(f)).unwrap_or(true))
            .take(limit)
            .filter_map(|line| {
                let parts: Vec<&str> = line.split('\t').collect();
                if parts.len() >= 2 {
                    Some(PackageInfo {
                        name: parts[0].to_string(),
                        version: parts[1].to_string(),
                        description: String::new(),
                        architecture: String::new(),
                        installed_size: 0,
                        install_date: String::new(),
                        update_available: false,
                        new_version: String::new(),
                        repository: String::new(),
                        package_manager: "apt".to_string(),
                    })
                } else {
                    None
                }
            })
            .collect();

        Ok(packages)
    }

    fn check_apt_updates(&self) -> Result<Vec<PackageInfo>, String> {
        // Update package lists first
        Command::new("apt-get")
            .args(["update", "-qq"])
            .output()
            .map_err(|e| format!("Failed to update package lists: {e}"))?;

        let output = Command::new("apt-get")
            .args(["--simulate", "upgrade"])
            .output()
            .map_err(|e| format!("Failed to check updates: {e}"))?;

        let packages: Vec<PackageInfo> = String::from_utf8_lossy(&output.stdout)
            .lines()
            .filter(|line| line.starts_with("Inst "))
            .filter_map(|line| {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 4 {
                    Some(PackageInfo {
                        name: parts[1].to_string(),
                        version: parts.get(2).unwrap_or(&"").to_string(),
                        description: String::new(),
                        architecture: String::new(),
                        installed_size: 0,
                        install_date: String::new(),
                        update_available: true,
                        new_version: parts
                            .get(3)
                            .unwrap_or(&"")
                            .trim_matches(['[', ']'])
                            .to_string(),
                        repository: String::new(),
                        package_manager: "apt".to_string(),
                    })
                } else {
                    None
                }
            })
            .collect();

        Ok(packages)
    }

    fn update_apt_package(&self, name: &str) -> Result<String, String> {
        let output = Command::new("apt-get")
            .args(["install", "--only-upgrade", "-y", name])
            .output()
            .map_err(|e| format!("Failed to update package: {e}"))?;

        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        } else {
            Err(String::from_utf8_lossy(&output.stderr).to_string())
        }
    }

    fn install_apt_package(&self, name: &str, refresh: bool) -> Result<String, String> {
        if refresh {
            let update = Command::new("apt-get")
                .env("DEBIAN_FRONTEND", "noninteractive")
                .args(["update", "-qq"])
                .output()
                .map_err(|e| format!("Failed to refresh package lists: {e}"))?;
            Self::command_output(update, "Refreshing package lists")?;
        }
        let output = Command::new("apt-get")
            .env("DEBIAN_FRONTEND", "noninteractive")
            .args(["install", "-y", "--no-install-recommends", name])
            .output()
            .map_err(|e| format!("Failed to install package: {e}"))?;
        Self::command_output(output, "Package installation")
    }

    fn system_update_apt(&self) -> Result<String, String> {
        let output = Command::new("apt-get")
            .args(["upgrade", "-y"])
            .output()
            .map_err(|e| format!("Failed to perform system update: {e}"))?;

        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        } else {
            Err(String::from_utf8_lossy(&output.stderr).to_string())
        }
    }

    // ========== YUM/DNF (CentOS/RHEL/Fedora) ==========
    fn list_yum_packages(
        &self,
        filter: Option<&str>,
        limit: usize,
    ) -> Result<Vec<PackageInfo>, String> {
        let cmd = if matches!(self.package_manager_type, PackageManagerType::Dnf) {
            "dnf"
        } else {
            "yum"
        };

        let output = Command::new(cmd)
            .args(["list", "installed", "-q"])
            .output()
            .map_err(|e| format!("Failed to run {cmd}: {e}"))?;

        let packages: Vec<PackageInfo> = String::from_utf8_lossy(&output.stdout)
            .lines()
            .filter(|line| filter.map(|f| line.contains(f)).unwrap_or(true))
            .take(limit)
            .filter_map(|line| {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 2 {
                    Some(PackageInfo {
                        name: parts[0].to_string(),
                        version: parts[1].to_string(),
                        description: String::new(),
                        architecture: String::new(),
                        installed_size: 0,
                        install_date: String::new(),
                        update_available: false,
                        new_version: String::new(),
                        repository: String::new(),
                        package_manager: cmd.to_string(),
                    })
                } else {
                    None
                }
            })
            .collect();

        Ok(packages)
    }

    fn check_yum_updates(&self) -> Result<Vec<PackageInfo>, String> {
        let cmd = if matches!(self.package_manager_type, PackageManagerType::Dnf) {
            "dnf"
        } else {
            "yum"
        };

        let output = Command::new(cmd)
            .args(["check-update", "-q"])
            .output()
            .map_err(|e| format!("Failed to check updates: {e}"))?;

        let packages: Vec<PackageInfo> = String::from_utf8_lossy(&output.stdout)
            .lines()
            .filter_map(|line| {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 2 {
                    Some(PackageInfo {
                        name: parts[0].to_string(),
                        version: String::new(),
                        description: String::new(),
                        architecture: String::new(),
                        installed_size: 0,
                        install_date: String::new(),
                        update_available: true,
                        new_version: parts[1].to_string(),
                        repository: String::new(),
                        package_manager: cmd.to_string(),
                    })
                } else {
                    None
                }
            })
            .collect();

        Ok(packages)
    }

    fn update_yum_package(&self, name: &str) -> Result<String, String> {
        let cmd = if matches!(self.package_manager_type, PackageManagerType::Dnf) {
            "dnf"
        } else {
            "yum"
        };

        let output = Command::new(cmd)
            .args(["update", "-y", name])
            .output()
            .map_err(|e| format!("Failed to update package: {e}"))?;

        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        } else {
            Err(String::from_utf8_lossy(&output.stderr).to_string())
        }
    }

    fn install_yum_package(&self, name: &str) -> Result<String, String> {
        let cmd = if matches!(self.package_manager_type, PackageManagerType::Dnf) {
            "dnf"
        } else {
            "yum"
        };
        let install = || {
            Command::new(cmd)
                .args(["install", "-y", name])
                .output()
                .map_err(|e| format!("Failed to install package: {e}"))
        };
        let first = install()?;
        if first.status.success() {
            return Self::command_output(first, "Package installation");
        }

        // nginx is commonly provided by EPEL on CentOS 7. Keep this fallback
        // narrow so installing an unrelated package never adds a repository.
        if name == "nginx" && matches!(self.package_manager_type, PackageManagerType::Yum) {
            let epel = Command::new("yum")
                .args(["install", "-y", "epel-release"])
                .output()
                .map_err(|e| format!("Failed to enable EPEL for nginx: {e}"))?;
            Self::command_output(epel, "Enabling EPEL for nginx")?;
            return Self::command_output(install()?, "Package installation");
        }
        Self::command_output(first, "Package installation")
    }

    fn system_update_yum(&self) -> Result<String, String> {
        let cmd = if matches!(self.package_manager_type, PackageManagerType::Dnf) {
            "dnf"
        } else {
            "yum"
        };

        let output = Command::new(cmd)
            .args(["update", "-y"])
            .output()
            .map_err(|e| format!("Failed to perform system update: {e}"))?;

        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        } else {
            Err(String::from_utf8_lossy(&output.stderr).to_string())
        }
    }

    // ========== Pacman (Arch Linux) ==========
    fn list_pacman_packages(
        &self,
        filter: Option<&str>,
        limit: usize,
    ) -> Result<Vec<PackageInfo>, String> {
        let output = Command::new("pacman")
            .args(["-Q"])
            .output()
            .map_err(|e| format!("Failed to run pacman: {e}"))?;

        let packages: Vec<PackageInfo> = String::from_utf8_lossy(&output.stdout)
            .lines()
            .filter(|line| filter.map(|f| line.contains(f)).unwrap_or(true))
            .take(limit)
            .filter_map(|line| {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 2 {
                    Some(PackageInfo {
                        name: parts[0].to_string(),
                        version: parts[1].to_string(),
                        description: String::new(),
                        architecture: String::new(),
                        installed_size: 0,
                        install_date: String::new(),
                        update_available: false,
                        new_version: String::new(),
                        repository: String::new(),
                        package_manager: "pacman".to_string(),
                    })
                } else {
                    None
                }
            })
            .collect();

        Ok(packages)
    }

    fn check_pacman_updates(&self) -> Result<Vec<PackageInfo>, String> {
        // Sync first
        Command::new("pacman").args(["-Sy"]).output().ok();

        let output = Command::new("pacman")
            .args(["-Qu"])
            .output()
            .map_err(|e| format!("Failed to check updates: {e}"))?;

        let packages: Vec<PackageInfo> = String::from_utf8_lossy(&output.stdout)
            .lines()
            .filter_map(|line| {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 4 {
                    Some(PackageInfo {
                        name: parts[0].to_string(),
                        version: parts[1].to_string(),
                        description: String::new(),
                        architecture: String::new(),
                        installed_size: 0,
                        install_date: String::new(),
                        update_available: true,
                        new_version: parts[3].to_string(),
                        repository: String::new(),
                        package_manager: "pacman".to_string(),
                    })
                } else {
                    None
                }
            })
            .collect();

        Ok(packages)
    }

    fn update_pacman_package(&self, name: &str) -> Result<String, String> {
        let output = Command::new("pacman")
            .args(["-S", "--noconfirm", name])
            .output()
            .map_err(|e| format!("Failed to update package: {e}"))?;

        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        } else {
            Err(String::from_utf8_lossy(&output.stderr).to_string())
        }
    }

    fn install_pacman_package(&self, name: &str) -> Result<String, String> {
        let output = Command::new("pacman")
            .args(["-S", "--noconfirm", "--needed", name])
            .output()
            .map_err(|e| format!("Failed to install package: {e}"))?;
        Self::command_output(output, "Package installation")
    }

    fn system_update_pacman(&self) -> Result<String, String> {
        let output = Command::new("pacman")
            .args(["-Syu", "--noconfirm"])
            .output()
            .map_err(|e| format!("Failed to perform system update: {e}"))?;

        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        } else {
            Err(String::from_utf8_lossy(&output.stderr).to_string())
        }
    }

    // ========== Homebrew (macOS) ==========
    fn list_brew_packages(
        &self,
        filter: Option<&str>,
        limit: usize,
    ) -> Result<Vec<PackageInfo>, String> {
        let output = Command::new("brew")
            .args(["list", "--versions"])
            .output()
            .map_err(|e| format!("Failed to run brew: {e}"))?;

        let packages: Vec<PackageInfo> = String::from_utf8_lossy(&output.stdout)
            .lines()
            .filter(|line| filter.map(|f| line.contains(f)).unwrap_or(true))
            .take(limit)
            .filter_map(|line| {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 2 {
                    Some(PackageInfo {
                        name: parts[0].to_string(),
                        version: parts[1].to_string(),
                        description: String::new(),
                        architecture: String::new(),
                        installed_size: 0,
                        install_date: String::new(),
                        update_available: false,
                        new_version: String::new(),
                        repository: String::new(),
                        package_manager: "brew".to_string(),
                    })
                } else {
                    None
                }
            })
            .collect();

        Ok(packages)
    }

    fn check_brew_updates(&self) -> Result<Vec<PackageInfo>, String> {
        Command::new("brew").args(["update"]).output().ok();

        let output = Command::new("brew")
            .args(["outdated", "--verbose"])
            .output()
            .map_err(|e| format!("Failed to check updates: {e}"))?;

        let packages: Vec<PackageInfo> = String::from_utf8_lossy(&output.stdout)
            .lines()
            .filter_map(|line| {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 3 {
                    Some(PackageInfo {
                        name: parts[0].to_string(),
                        version: parts[1].to_string(),
                        description: String::new(),
                        architecture: String::new(),
                        installed_size: 0,
                        install_date: String::new(),
                        update_available: true,
                        new_version: parts.get(3).unwrap_or(&"").to_string(),
                        repository: String::new(),
                        package_manager: "brew".to_string(),
                    })
                } else {
                    None
                }
            })
            .collect();

        Ok(packages)
    }

    fn update_brew_package(&self, name: &str) -> Result<String, String> {
        let output = Command::new("brew")
            .args(["upgrade", name])
            .output()
            .map_err(|e| format!("Failed to update package: {e}"))?;

        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        } else {
            Err(String::from_utf8_lossy(&output.stderr).to_string())
        }
    }

    fn install_brew_package(&self, name: &str) -> Result<String, String> {
        let output = Command::new("brew")
            .args(["install", name])
            .output()
            .map_err(|e| format!("Failed to install package: {e}"))?;
        Self::command_output(output, "Package installation")
    }

    fn system_update_brew(&self) -> Result<String, String> {
        let output = Command::new("brew")
            .args(["upgrade"])
            .output()
            .map_err(|e| format!("Failed to perform system update: {e}"))?;

        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        } else {
            Err(String::from_utf8_lossy(&output.stderr).to_string())
        }
    }

    // ========== Winget (Windows) ==========
    fn list_winget_packages(
        &self,
        filter: Option<&str>,
        limit: usize,
    ) -> Result<Vec<PackageInfo>, String> {
        let output = Command::new("winget")
            .args(["list", "--accept-source-agreements"])
            .output()
            .map_err(|e| format!("Failed to run winget: {e}"))?;

        let packages: Vec<PackageInfo> = String::from_utf8_lossy(&output.stdout)
            .lines()
            .skip(2) // Skip header lines
            .filter(|line| filter.map(|f| line.contains(f)).unwrap_or(true))
            .take(limit)
            .filter_map(|line| {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 2 {
                    Some(PackageInfo {
                        name: parts[0].to_string(),
                        version: parts.get(1).unwrap_or(&"").to_string(),
                        description: String::new(),
                        architecture: String::new(),
                        installed_size: 0,
                        install_date: String::new(),
                        update_available: false,
                        new_version: String::new(),
                        repository: String::new(),
                        package_manager: "winget".to_string(),
                    })
                } else {
                    None
                }
            })
            .collect();

        Ok(packages)
    }

    fn check_winget_updates(&self) -> Result<Vec<PackageInfo>, String> {
        let output = Command::new("winget")
            .args(["upgrade", "--accept-source-agreements"])
            .output()
            .map_err(|e| format!("Failed to check updates: {e}"))?;

        let packages: Vec<PackageInfo> = String::from_utf8_lossy(&output.stdout)
            .lines()
            .skip(2)
            .filter_map(|line| {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 3 {
                    Some(PackageInfo {
                        name: parts[0].to_string(),
                        version: parts[1].to_string(),
                        description: String::new(),
                        architecture: String::new(),
                        installed_size: 0,
                        install_date: String::new(),
                        update_available: true,
                        new_version: parts[2].to_string(),
                        repository: String::new(),
                        package_manager: "winget".to_string(),
                    })
                } else {
                    None
                }
            })
            .collect();

        Ok(packages)
    }

    fn update_winget_package(&self, name: &str) -> Result<String, String> {
        let output = Command::new("winget")
            .args([
                "upgrade",
                "--id",
                name,
                "--accept-source-agreements",
                "--silent",
            ])
            .output()
            .map_err(|e| format!("Failed to update package: {e}"))?;

        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        } else {
            Err(String::from_utf8_lossy(&output.stderr).to_string())
        }
    }

    fn install_winget_package(&self, name: &str) -> Result<String, String> {
        let output = Command::new("winget")
            .args([
                "install",
                "--id",
                name,
                "--exact",
                "--accept-package-agreements",
                "--accept-source-agreements",
                "--silent",
            ])
            .output()
            .map_err(|e| format!("Failed to install package: {e}"))?;
        Self::command_output(output, "Package installation")
    }

    fn system_update_winget(&self) -> Result<String, String> {
        let output = Command::new("winget")
            .args(["upgrade", "--all", "--accept-source-agreements", "--silent"])
            .output()
            .map_err(|e| format!("Failed to perform system update: {e}"))?;

        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        } else {
            Err(String::from_utf8_lossy(&output.stderr).to_string())
        }
    }

    // ========== Chocolatey (Windows) ==========
    fn list_choco_packages(
        &self,
        filter: Option<&str>,
        limit: usize,
    ) -> Result<Vec<PackageInfo>, String> {
        let output = Command::new("choco")
            .args(["list", "--local-only"])
            .output()
            .map_err(|e| format!("Failed to run choco: {e}"))?;

        let packages: Vec<PackageInfo> = String::from_utf8_lossy(&output.stdout)
            .lines()
            .filter(|line| filter.map(|f| line.contains(f)).unwrap_or(true))
            .take(limit)
            .filter_map(|line| {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 2 {
                    Some(PackageInfo {
                        name: parts[0].to_string(),
                        version: parts[1].to_string(),
                        description: String::new(),
                        architecture: String::new(),
                        installed_size: 0,
                        install_date: String::new(),
                        update_available: false,
                        new_version: String::new(),
                        repository: String::new(),
                        package_manager: "choco".to_string(),
                    })
                } else {
                    None
                }
            })
            .collect();

        Ok(packages)
    }

    fn check_choco_updates(&self) -> Result<Vec<PackageInfo>, String> {
        let output = Command::new("choco")
            .args(["outdated"])
            .output()
            .map_err(|e| format!("Failed to check updates: {e}"))?;

        let packages: Vec<PackageInfo> = String::from_utf8_lossy(&output.stdout)
            .lines()
            .filter_map(|line| {
                if line.contains('|') {
                    let parts: Vec<&str> = line.split('|').collect();
                    if parts.len() >= 3 {
                        return Some(PackageInfo {
                            name: parts[0].trim().to_string(),
                            version: parts[1].trim().to_string(),
                            description: String::new(),
                            architecture: String::new(),
                            installed_size: 0,
                            install_date: String::new(),
                            update_available: true,
                            new_version: parts[2].trim().to_string(),
                            repository: String::new(),
                            package_manager: "choco".to_string(),
                        });
                    }
                }
                None
            })
            .collect();

        Ok(packages)
    }

    fn update_choco_package(&self, name: &str) -> Result<String, String> {
        let output = Command::new("choco")
            .args(["upgrade", "-y", name])
            .output()
            .map_err(|e| format!("Failed to update package: {e}"))?;

        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        } else {
            Err(String::from_utf8_lossy(&output.stderr).to_string())
        }
    }

    fn install_choco_package(&self, name: &str) -> Result<String, String> {
        let output = Command::new("choco")
            .args(["install", "-y", name])
            .output()
            .map_err(|e| format!("Failed to install package: {e}"))?;
        Self::command_output(output, "Package installation")
    }

    fn system_update_choco(&self) -> Result<String, String> {
        let output = Command::new("choco")
            .args(["upgrade", "-y", "all"])
            .output()
            .map_err(|e| format!("Failed to perform system update: {e}"))?;

        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).to_string())
        } else {
            Err(String::from_utf8_lossy(&output.stderr).to_string())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::PackageManager;

    #[test]
    fn package_names_are_strictly_validated() {
        for valid in ["nginx", "java-11-openjdk-headless", "python3.12", "lib_ssl"] {
            assert!(PackageManager::is_valid_package_name(valid), "{valid}");
        }
        for invalid in [
            "",
            "../nginx",
            "nginx;reboot",
            "-nginx",
            "nginx.",
            "nginx repo",
        ] {
            assert!(!PackageManager::is_valid_package_name(invalid), "{invalid}");
        }
    }
}
