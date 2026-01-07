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
