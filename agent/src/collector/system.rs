use std::sync::OnceLock;
use sysinfo::System;

use crate::proto::SystemInfo;

/// Static system info that doesn't change
static SYSTEM_INFO: OnceLock<SystemInfoStatic> = OnceLock::new();

#[derive(Debug, Clone, Default)]
struct SystemInfoStatic {
    os_name: String,
    os_version: String,
    kernel_version: String,
    hostname: String,
    boot_time: u64,
    motherboard_model: String,
    motherboard_vendor: String,
    bios_version: String,
    system_model: String,
    system_vendor: String,
}

/// System info collector
pub struct SystemInfoCollector {
    /// Optional hostname override from config
    hostname_override: Option<String>,
}

impl SystemInfoCollector {
    pub fn new() -> Self {
        SYSTEM_INFO.get_or_init(Self::collect_static_info);
        Self {
            hostname_override: None,
        }
    }

    /// Create a new collector with a custom hostname override
    pub fn with_hostname(hostname: Option<String>) -> Self {
        SYSTEM_INFO.get_or_init(Self::collect_static_info);
        Self {
            hostname_override: hostname,
        }
    }

    fn collect_static_info() -> SystemInfoStatic {
        let mut info = SystemInfoStatic {
            os_name: System::name().unwrap_or_else(|| "Unknown".to_string()),
            os_version: System::os_version().unwrap_or_else(|| "Unknown".to_string()),
            kernel_version: System::kernel_version().unwrap_or_else(|| "Unknown".to_string()),
            hostname: System::host_name().unwrap_or_else(|| "Unknown".to_string()),
            boot_time: System::boot_time(),
            ..Default::default()
        };

        // Get hardware info (platform-specific)
        #[cfg(target_os = "linux")]
        {
            info = Self::add_linux_hardware_info(info);
        }

        #[cfg(target_os = "macos")]
        {
            info = Self::add_macos_hardware_info(info);
        }

        #[cfg(target_os = "windows")]
        {
            info = Self::add_windows_hardware_info(info);
        }

        info
    }

    #[cfg(target_os = "linux")]
    fn add_linux_hardware_info(mut info: SystemInfoStatic) -> SystemInfoStatic {
        use std::fs;

        // DMI/SMBIOS information (requires root or specific permissions)
        let dmi_path = "/sys/class/dmi/id";

        // Motherboard info
        if let Ok(vendor) = fs::read_to_string(format!("{}/board_vendor", dmi_path)) {
            info.motherboard_vendor = vendor.trim().to_string();
        }
        if let Ok(name) = fs::read_to_string(format!("{}/board_name", dmi_path)) {
            info.motherboard_model = name.trim().to_string();
        }

        // BIOS info
        if let Ok(version) = fs::read_to_string(format!("{}/bios_version", dmi_path)) {
            info.bios_version = version.trim().to_string();
        }

        // System info
        if let Ok(vendor) = fs::read_to_string(format!("{}/sys_vendor", dmi_path)) {
            info.system_vendor = vendor.trim().to_string();
        }
        if let Ok(name) = fs::read_to_string(format!("{}/product_name", dmi_path)) {
            info.system_model = name.trim().to_string();
        }

        info
    }

    #[cfg(target_os = "macos")]
    fn add_macos_hardware_info(mut info: SystemInfoStatic) -> SystemInfoStatic {
        use std::process::Command;

        // Use system_profiler to get hardware info
        if let Ok(output) = Command::new("system_profiler")
            .args(["SPHardwareDataType", "-json"])
            .output()
        {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);

                // Simple JSON parsing
                for line in stdout.lines() {
                    let line = line.trim();
                    if line.contains("\"model_name\"") {
                        if let Some(val) = extract_json_string(line) {
                            info.system_model = val;
                        }
                    } else if line.contains("\"model_identifier\"") {
                        if let Some(val) = extract_json_string(line) {
                            if info.motherboard_model.is_empty() {
                                info.motherboard_model = val;
                            }
                        }
                    }
                }
            }
        }

        // Get boot ROM version
        if let Ok(output) = Command::new("system_profiler")
            .args(["SPHardwareDataType"])
            .output()
        {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                for line in stdout.lines() {
                    if line.contains("Boot ROM Version") || line.contains("System Firmware Version")
                    {
                        if let Some(val) = line.split(':').nth(1) {
                            info.bios_version = val.trim().to_string();
                        }
                    }
                }
            }
        }

        info.system_vendor = "Apple".to_string();

        info
    }

    #[cfg(target_os = "windows")]
    fn add_windows_hardware_info(mut info: SystemInfoStatic) -> SystemInfoStatic {
        use std::process::Command;

        // Get system info using WMIC
        if let Ok(output) = Command::new("wmic")
            .args(["csproduct", "get", "Name,Vendor", "/format:csv"])
            .output()
        {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                for line in stdout.lines().skip(1) {
                    let parts: Vec<&str> = line.split(',').collect();
                    if parts.len() >= 3 {
                        info.system_model = parts[1].trim().to_string();
                        info.system_vendor = parts[2].trim().to_string();
                    }
                }
            }
        }

        // Get motherboard info
        if let Ok(output) = Command::new("wmic")
            .args(["baseboard", "get", "Manufacturer,Product", "/format:csv"])
            .output()
        {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                for line in stdout.lines().skip(1) {
                    let parts: Vec<&str> = line.split(',').collect();
                    if parts.len() >= 3 {
                        info.motherboard_vendor = parts[1].trim().to_string();
                        info.motherboard_model = parts[2].trim().to_string();
                    }
                }
            }
        }

        // Get BIOS info
        if let Ok(output) = Command::new("wmic")
            .args(["bios", "get", "SMBIOSBIOSVersion", "/format:csv"])
            .output()
        {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                for line in stdout.lines().skip(1) {
                    let parts: Vec<&str> = line.split(',').collect();
                    if parts.len() >= 2 {
                        info.bios_version = parts[1].trim().to_string();
                    }
                }
            }
        }

        info
    }

    /// Collect system info with current uptime
    pub fn collect(&self) -> SystemInfo {
        let static_info = SYSTEM_INFO.get().expect("System info not initialized");
        let uptime_seconds = System::uptime();

        // Use hostname_override if set, otherwise use system hostname
        let hostname = self
            .hostname_override
            .clone()
            .unwrap_or_else(|| static_info.hostname.clone());

        SystemInfo {
            os_name: static_info.os_name.clone(),
            os_version: static_info.os_version.clone(),
            kernel_version: static_info.kernel_version.clone(),
            hostname,
            boot_time: static_info.boot_time,
            uptime_seconds,
            motherboard_model: static_info.motherboard_model.clone(),
            motherboard_vendor: static_info.motherboard_vendor.clone(),
            bios_version: static_info.bios_version.clone(),
            system_model: static_info.system_model.clone(),
            system_vendor: static_info.system_vendor.clone(),
        }
    }
}

impl Default for SystemInfoCollector {
    fn default() -> Self {
        Self::new()
    }
}
