use std::process::Command;
use std::sync::OnceLock;
use std::time::Duration;
use sysinfo::System;

use crate::proto::SystemInfo;
use crate::utils::safe_command::exec_with_timeout;

/// System info command timeout - 10 seconds
const SYSTEM_COMMAND_TIMEOUT: Duration = Duration::from_secs(10);

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
    /// Enclosure/chassis type label (best-effort, e.g. "Laptop", "Desktop",
    /// "Server"). Empty string if it cannot be determined.
    chassis: String,
}

/// System info collector
pub struct SystemInfoCollector {
    hostname_override: Option<String>,
}

impl SystemInfoCollector {
    pub fn new() -> Self {
        SYSTEM_INFO.get_or_init(Self::collect_static_info);
        Self {
            hostname_override: None,
        }
    }

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

        // DMI/SMBIOS information (fast, uses sysfs)
        let dmi_path = "/sys/class/dmi/id";

        if let Ok(vendor) = fs::read_to_string(format!("{}/board_vendor", dmi_path)) {
            info.motherboard_vendor = vendor.trim().to_string();
        }
        if let Ok(name) = fs::read_to_string(format!("{}/board_name", dmi_path)) {
            info.motherboard_model = name.trim().to_string();
        }
        if let Ok(version) = fs::read_to_string(format!("{}/bios_version", dmi_path)) {
            info.bios_version = version.trim().to_string();
        }
        if let Ok(vendor) = fs::read_to_string(format!("{}/sys_vendor", dmi_path)) {
            info.system_vendor = vendor.trim().to_string();
        }
        if let Ok(name) = fs::read_to_string(format!("{}/product_name", dmi_path)) {
            info.system_model = name.trim().to_string();
        }
        // chassis_type is the SMBIOS numeric code (DMTF spec). Map to a label.
        if let Ok(code) = fs::read_to_string(format!("{}/chassis_type", dmi_path)) {
            if let Ok(n) = code.trim().parse::<u32>() {
                info.chassis = chassis_label(n).to_string();
            }
        }

        info
    }

    #[cfg(target_os = "macos")]
    fn add_macos_hardware_info(mut info: SystemInfoStatic) -> SystemInfoStatic {
        // Get hardware info with JSON output
        let mut cmd = Command::new("system_profiler");
        cmd.args(["SPHardwareDataType", "-json"]);

        if let Some(output) = exec_with_timeout(cmd, SYSTEM_COMMAND_TIMEOUT) {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);

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
        let mut cmd = Command::new("system_profiler");
        cmd.args(["SPHardwareDataType"]);

        if let Some(output) = exec_with_timeout(cmd, SYSTEM_COMMAND_TIMEOUT) {
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

        // Best-effort chassis from the model name (no DMI on macOS).
        let model_lower = info.system_model.to_lowercase();
        if model_lower.contains("macbook") {
            info.chassis = "Laptop".to_string();
        } else if !info.system_model.is_empty() {
            info.chassis = "Desktop".to_string();
        }

        info
    }

    #[cfg(target_os = "windows")]
    fn add_windows_hardware_info(mut info: SystemInfoStatic) -> SystemInfoStatic {
        // Get system info using WMIC
        let mut cmd = Command::new("wmic");
        cmd.args(["csproduct", "get", "Name,Vendor", "/format:csv"]);

        if let Some(output) = exec_with_timeout(cmd, SYSTEM_COMMAND_TIMEOUT) {
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
        let mut cmd = Command::new("wmic");
        cmd.args(["baseboard", "get", "Manufacturer,Product", "/format:csv"]);

        if let Some(output) = exec_with_timeout(cmd, SYSTEM_COMMAND_TIMEOUT) {
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
        let mut cmd = Command::new("wmic");
        cmd.args(["bios", "get", "SMBIOSBIOSVersion", "/format:csv"]);

        if let Some(output) = exec_with_timeout(cmd, SYSTEM_COMMAND_TIMEOUT) {
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

        // Get chassis type (SMBIOS ChassisTypes numeric code).
        let mut cmd = Command::new("wmic");
        cmd.args(["systemenclosure", "get", "ChassisTypes", "/format:csv"]);

        if let Some(output) = exec_with_timeout(cmd, SYSTEM_COMMAND_TIMEOUT) {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                for line in stdout.lines().skip(1) {
                    // CSV: Node,ChassisTypes -> ChassisTypes may look like "{3}".
                    let parts: Vec<&str> = line.split(',').collect();
                    if parts.len() >= 2 {
                        let raw = parts[1].trim().trim_matches(|c| c == '{' || c == '}');
                        // Multiple values are semicolon-separated; take the first.
                        let first = raw.split(';').next().unwrap_or("").trim();
                        if let Ok(n) = first.parse::<u32>() {
                            info.chassis = chassis_label(n).to_string();
                        }
                    }
                }
            }
        }

        info
    }

    pub fn collect(&self) -> SystemInfo {
        // Both constructors prime SYSTEM_INFO via get_or_init, so this should
        // already be populated. Fall back to initializing on demand instead of
        // expect() — a panic deep in metric collection would tear down the
        // tokio worker that owns this future, taking the whole agent's
        // collection loop with it.
        let static_info = SYSTEM_INFO.get_or_init(Self::collect_static_info);
        let uptime_seconds = System::uptime();

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
            chassis: static_info.chassis.clone(),
            // Primary outbound IPv4 can change (DHCP, VPN, interface up/down), so
            // it is resolved on each collect rather than cached as static info.
            primary_ip: primary_ipv4(),
        }
    }
}

/// Map an SMBIOS chassis-type numeric code (DMTF System Management BIOS spec,
/// "System Enclosure or Chassis" / DMI type 3) to a human-readable label.
/// Returns "" for unknown/unmapped codes so callers can treat it as unavailable.
#[allow(dead_code)]
fn chassis_label(code: u32) -> &'static str {
    match code {
        3 | 4 | 6 | 7 => "Desktop",
        8 | 9 | 10 | 14 | 30 | 31 | 32 => "Laptop",
        11 => "Hand Held",
        12 | 13 => "All-in-One",
        15 | 16 => "Desktop",
        17 | 23 | 28 => "Server",
        18..=22 => "Expansion Chassis",
        24 => "Sealed-Case PC",
        25 => "Multi-System Chassis",
        29 => "All-in-One",
        _ => "",
    }
}

/// Resolve the primary outbound IPv4 address (the source address the OS would
/// use to reach the public internet). Returns "" if it cannot be determined.
///
/// Uses the standard "connect a UDP socket to a public address and read the
/// local address" trick: UDP connect performs no handshake and sends no packets,
/// it only makes the kernel pick the egress interface, so this is fast, has no
/// extra dependency, and works on Linux/macOS/Windows alike.
fn primary_ipv4() -> String {
    use std::net::UdpSocket;

    // 0.0.0.0:0 lets the OS choose the source port/interface. The remote is a
    // routable public IPv4 (Google DNS); no traffic is actually sent.
    let socket = match UdpSocket::bind("0.0.0.0:0") {
        Ok(s) => s,
        Err(_) => return String::new(),
    };
    if socket.connect("8.8.8.8:80").is_err() {
        return String::new();
    }
    match socket.local_addr() {
        Ok(addr) => {
            let ip = addr.ip();
            if ip.is_unspecified() {
                String::new()
            } else {
                ip.to_string()
            }
        }
        Err(_) => String::new(),
    }
}

impl Default for SystemInfoCollector {
    fn default() -> Self {
        Self::new()
    }
}

#[allow(dead_code)]
fn extract_json_string(line: &str) -> Option<String> {
    let parts: Vec<&str> = line.split(':').collect();
    if parts.len() >= 2 {
        let val = parts[1..]
            .join(":")
            .trim()
            .trim_matches(',')
            .trim_matches('"')
            .to_string();
        Some(val)
    } else {
        None
    }
}
