use std::sync::OnceLock;
use sysinfo::System;

use crate::proto::MemoryMetrics;

/// Static memory hardware info
static MEMORY_INFO: OnceLock<MemoryHardwareInfo> = OnceLock::new();

#[derive(Debug, Clone, Default)]
struct MemoryHardwareInfo {
    memory_type: String,
    speed_mhz: u32,
}

/// Memory metrics collector
pub struct MemoryCollector;

impl MemoryCollector {
    pub fn new() -> Self {
        MEMORY_INFO.get_or_init(Self::collect_hardware_info);
        Self
    }

    fn collect_hardware_info() -> MemoryHardwareInfo {
        let mut info = MemoryHardwareInfo::default();

        #[cfg(target_os = "linux")]
        {
            info = Self::collect_linux_memory_info();
        }

        #[cfg(target_os = "macos")]
        {
            info = Self::collect_macos_memory_info();
        }

        #[cfg(target_os = "windows")]
        {
            info = Self::collect_windows_memory_info();
        }

        info
    }

    #[cfg(target_os = "linux")]
    fn collect_linux_memory_info() -> MemoryHardwareInfo {
        use std::process::Command;

        let mut info = MemoryHardwareInfo::default();

        // Use dmidecode to get memory info (requires root)
        if let Ok(output) = Command::new("dmidecode").args(["-t", "memory"]).output() {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                let mut in_device_section = false;

                for line in stdout.lines() {
                    let line = line.trim();

                    if line.starts_with("Memory Device") {
                        in_device_section = true;
                    }

                    if in_device_section {
                        if line.starts_with("Type:") && info.memory_type.is_empty() {
                            if let Some(val) = line.split(':').nth(1) {
                                let mem_type = val.trim();
                                if mem_type != "Unknown" && !mem_type.is_empty() {
                                    info.memory_type = mem_type.to_string();
                                }
                            }
                        } else if line.starts_with("Speed:") && info.speed_mhz == 0 {
                            if let Some(val) = line.split(':').nth(1) {
                                let speed_str = val.trim().split_whitespace().next().unwrap_or("0");
                                if let Ok(speed) = speed_str.parse() {
                                    info.speed_mhz = speed;
                                }
                            }
                        }
                    }
                }
            }
        }

        // Fallback: try lshw
        if info.memory_type.is_empty() {
            if let Ok(output) = Command::new("lshw")
                .args(["-class", "memory", "-short"])
                .output()
            {
                if output.status.success() {
                    let stdout = String::from_utf8_lossy(&output.stdout);
                    for line in stdout.lines() {
                        if line.contains("DDR") {
                            // Extract DDR type from line
                            for word in line.split_whitespace() {
                                if word.starts_with("DDR") {
                                    info.memory_type = word.to_string();
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }

        info
    }

    #[cfg(target_os = "macos")]
    fn collect_macos_memory_info() -> MemoryHardwareInfo {
        use std::process::Command;

        let mut info = MemoryHardwareInfo::default();

        // Use system_profiler
        if let Ok(output) = Command::new("system_profiler")
            .args(["SPMemoryDataType"])
            .output()
        {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);

                for line in stdout.lines() {
                    let line = line.trim();
                    if line.starts_with("Type:") {
                        if let Some(val) = line.split(':').nth(1) {
                            info.memory_type = val.trim().to_string();
                        }
                    } else if line.starts_with("Speed:") {
                        if let Some(val) = line.split(':').nth(1) {
                            let speed_str = val.split_whitespace().next().unwrap_or("0");
                            if let Ok(speed) = speed_str.parse() {
                                info.speed_mhz = speed;
                            }
                        }
                    }
                }
            }
        }

        info
    }

    #[cfg(target_os = "windows")]
    fn collect_windows_memory_info() -> MemoryHardwareInfo {
        use std::process::Command;

        let mut info = MemoryHardwareInfo::default();

        // Use WMIC to get memory info
        if let Ok(output) = Command::new("wmic")
            .args(["memorychip", "get", "MemoryType,Speed", "/format:csv"])
            .output()
        {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);

                for line in stdout.lines().skip(1) {
                    let parts: Vec<&str> = line.split(',').collect();
                    if parts.len() >= 3 {
                        // Memory type code to string
                        let mem_type_code: u32 = parts[1].trim().parse().unwrap_or(0);
                        info.memory_type = match mem_type_code {
                            20 => "DDR".to_string(),
                            21 => "DDR2".to_string(),
                            22 => "DDR2 FB-DIMM".to_string(),
                            24 => "DDR3".to_string(),
                            26 => "DDR4".to_string(),
                            34 => "DDR5".to_string(),
                            _ => format!("Type {}", mem_type_code),
                        };

                        if let Ok(speed) = parts[2].trim().parse() {
                            info.speed_mhz = speed;
                        }
                        break;
                    }
                }
            }
        }

        // Fallback to PowerShell
        if info.memory_type.is_empty() || info.memory_type.starts_with("Type ") {
            if let Ok(output) = Command::new("powershell")
                .args(["-Command", "Get-CimInstance -ClassName Win32_PhysicalMemory | Select-Object SMBIOSMemoryType,Speed | ConvertTo-Json"])
                .output()
            {
                if output.status.success() {
                    let stdout = String::from_utf8_lossy(&output.stdout);

                    for line in stdout.lines() {
                        let line = line.trim();
                        if line.contains("\"SMBIOSMemoryType\"") {
                            if let Some(val) = line.split(':').nth(1) {
                                let type_code: u32 = val.trim().trim_matches(',').parse().unwrap_or(0);
                                info.memory_type = match type_code {
                                    20 => "DDR".to_string(),
                                    21 => "DDR2".to_string(),
                                    22 => "DDR2 FB-DIMM".to_string(),
                                    24 => "DDR3".to_string(),
                                    26 => "DDR4".to_string(),
                                    34 => "DDR5".to_string(),
                                    _ => format!("Type {}", type_code),
                                };
                            }
                        } else if line.contains("\"Speed\"") {
                            if let Some(val) = line.split(':').nth(1) {
                                if let Ok(speed) = val.trim().trim_matches(',').parse() {
                                    info.speed_mhz = speed;
                                }
                            }
                        }
                    }
                }
            }
        }

        info
    }

    /// Get cached memory (Linux-specific)
    #[cfg(target_os = "linux")]
    fn get_cached_memory() -> u64 {
        use std::fs;

        if let Ok(meminfo) = fs::read_to_string("/proc/meminfo") {
            for line in meminfo.lines() {
                if line.starts_with("Cached:") {
                    if let Some(val) = line.split_whitespace().nth(1) {
                        // Value is in kB
                        return val.parse::<u64>().unwrap_or(0) * 1024;
                    }
                }
            }
        }
        0
    }

    #[cfg(not(target_os = "linux"))]
    fn get_cached_memory() -> u64 {
        0
    }

    /// Get buffer memory (Linux-specific)
    #[cfg(target_os = "linux")]
    fn get_buffers_memory() -> u64 {
        use std::fs;

        if let Ok(meminfo) = fs::read_to_string("/proc/meminfo") {
            for line in meminfo.lines() {
                if line.starts_with("Buffers:") {
                    if let Some(val) = line.split_whitespace().nth(1) {
                        // Value is in kB
                        return val.parse::<u64>().unwrap_or(0) * 1024;
                    }
                }
            }
        }
        0
    }

    #[cfg(not(target_os = "linux"))]
    fn get_buffers_memory() -> u64 {
        0
    }

    /// Collect memory metrics
    pub fn collect(&self, system: &System) -> MemoryMetrics {
        let total = system.total_memory();
        let used = system.used_memory();
        let available = system.available_memory();
        let swap_total = system.total_swap();
        let swap_used = system.used_swap();

        let hw_info = MEMORY_INFO.get().cloned().unwrap_or_default();

        MemoryMetrics {
            total,
            used,
            available,
            swap_total,
            swap_used,
            cached: Self::get_cached_memory(),
            buffers: Self::get_buffers_memory(),
            memory_type: hw_info.memory_type,
            memory_speed_mhz: hw_info.speed_mhz,
        }
    }
}

impl Default for MemoryCollector {
    fn default() -> Self {
        Self::new()
    }
}
