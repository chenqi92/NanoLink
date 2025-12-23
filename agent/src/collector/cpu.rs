use std::sync::OnceLock;
use sysinfo::System;

use crate::config::CollectorConfig;
use crate::proto::CpuMetrics;

/// Static CPU info that doesn't change
static CPU_INFO: OnceLock<CpuStaticInfo> = OnceLock::new();

#[derive(Debug, Clone)]
struct CpuStaticInfo {
    model: String,
    vendor: String,
    physical_cores: u32,
    logical_cores: u32,
    architecture: String,
    frequency_max_mhz: u64,
}

/// CPU metrics collector
pub struct CpuCollector {
    /// Previous CPU usage for delta calculation
    #[allow(dead_code)]
    prev_usage: Option<f64>,
}

impl CpuCollector {
    pub fn new() -> Self {
        // Initialize static CPU info once
        CPU_INFO.get_or_init(Self::collect_static_info);
        Self { prev_usage: None }
    }

    #[allow(unused_assignments)]
    fn collect_static_info() -> CpuStaticInfo {
        let mut info = CpuStaticInfo {
            model: String::new(),
            vendor: String::new(),
            physical_cores: 0,
            logical_cores: 0,
            architecture: std::env::consts::ARCH.to_string(),
            frequency_max_mhz: 0,
        };

        #[cfg(target_os = "linux")]
        {
            info = Self::collect_linux_cpu_info();
        }

        #[cfg(target_os = "macos")]
        {
            info = Self::collect_macos_cpu_info();
        }

        #[cfg(target_os = "windows")]
        {
            info = Self::collect_windows_cpu_info();
        }

        info
    }

    #[cfg(target_os = "linux")]
    fn collect_linux_cpu_info() -> CpuStaticInfo {
        use std::fs;

        let mut info = CpuStaticInfo {
            model: String::new(),
            vendor: String::new(),
            physical_cores: 0,
            logical_cores: 0,
            architecture: std::env::consts::ARCH.to_string(),
            frequency_max_mhz: 0,
        };

        // Parse /proc/cpuinfo
        if let Ok(cpuinfo) = fs::read_to_string("/proc/cpuinfo") {
            let mut physical_ids = std::collections::HashSet::new();
            let mut core_ids = std::collections::HashSet::new();
            let mut current_physical_id = String::new();

            for line in cpuinfo.lines() {
                if let Some((key, value)) = line.split_once(':') {
                    let key = key.trim();
                    let value = value.trim();

                    match key {
                        "model name" if info.model.is_empty() => {
                            info.model = value.to_string();
                        }
                        "vendor_id" if info.vendor.is_empty() => {
                            info.vendor = match value {
                                "GenuineIntel" => "Intel".to_string(),
                                "AuthenticAMD" => "AMD".to_string(),
                                other => other.to_string(),
                            };
                        }
                        "physical id" => {
                            current_physical_id = value.to_string();
                            physical_ids.insert(value.to_string());
                        }
                        "core id" => {
                            let key = format!("{}:{}", current_physical_id, value);
                            core_ids.insert(key);
                        }
                        "cpu MHz" if info.frequency_max_mhz == 0 => {
                            if let Ok(freq) = value.parse::<f64>() {
                                info.frequency_max_mhz = freq as u64;
                            }
                        }
                        "processor" => {
                            info.logical_cores += 1;
                        }
                        _ => {}
                    }
                }
            }

            info.physical_cores = if core_ids.is_empty() {
                info.logical_cores
            } else {
                core_ids.len() as u32
            };
        }

        // Try to get max frequency from scaling_max_freq
        if let Ok(max_freq) =
            fs::read_to_string("/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq")
        {
            if let Ok(freq_khz) = max_freq.trim().parse::<u64>() {
                info.frequency_max_mhz = freq_khz / 1000;
            }
        }

        info
    }

    #[cfg(target_os = "macos")]
    fn collect_macos_cpu_info() -> CpuStaticInfo {
        use std::process::Command;

        let mut info = CpuStaticInfo {
            model: String::new(),
            vendor: String::new(),
            physical_cores: 0,
            logical_cores: 0,
            architecture: std::env::consts::ARCH.to_string(),
            frequency_max_mhz: 0,
        };

        // Get CPU brand string
        if let Ok(output) = Command::new("sysctl")
            .args(["-n", "machdep.cpu.brand_string"])
            .output()
        {
            if output.status.success() {
                info.model = String::from_utf8_lossy(&output.stdout).trim().to_string();
            }
        }

        // Get vendor
        if let Ok(output) = Command::new("sysctl")
            .args(["-n", "machdep.cpu.vendor"])
            .output()
        {
            if output.status.success() {
                let vendor = String::from_utf8_lossy(&output.stdout).trim().to_string();
                info.vendor = match vendor.as_str() {
                    "GenuineIntel" => "Intel".to_string(),
                    "AuthenticAMD" => "AMD".to_string(),
                    _ => {
                        // Apple Silicon
                        if info.model.contains("Apple") {
                            "Apple".to_string()
                        } else {
                            vendor
                        }
                    }
                };
            }
        }

        // For Apple Silicon, vendor won't be available via sysctl
        if info.vendor.is_empty()
            && (info.model.contains("Apple") || std::env::consts::ARCH == "aarch64")
        {
            info.vendor = "Apple".to_string();
        }

        // Get physical cores
        if let Ok(output) = Command::new("sysctl")
            .args(["-n", "hw.physicalcpu"])
            .output()
        {
            if output.status.success() {
                if let Ok(cores) = String::from_utf8_lossy(&output.stdout).trim().parse() {
                    info.physical_cores = cores;
                }
            }
        }

        // Get logical cores
        if let Ok(output) = Command::new("sysctl")
            .args(["-n", "hw.logicalcpu"])
            .output()
        {
            if output.status.success() {
                if let Ok(cores) = String::from_utf8_lossy(&output.stdout).trim().parse() {
                    info.logical_cores = cores;
                }
            }
        }

        // Get CPU frequency
        if let Ok(output) = Command::new("sysctl")
            .args(["-n", "hw.cpufrequency_max"])
            .output()
        {
            if output.status.success() {
                if let Ok(freq) = String::from_utf8_lossy(&output.stdout)
                    .trim()
                    .parse::<u64>()
                {
                    info.frequency_max_mhz = freq / 1_000_000;
                }
            }
        }

        info
    }

    #[cfg(target_os = "windows")]
    fn collect_windows_cpu_info() -> CpuStaticInfo {
        use std::process::Command;

        let mut info = CpuStaticInfo {
            model: String::new(),
            vendor: String::new(),
            physical_cores: 0,
            logical_cores: 0,
            architecture: std::env::consts::ARCH.to_string(),
            frequency_max_mhz: 0,
        };

        // Use WMIC to get CPU info
        if let Ok(output) = Command::new("wmic")
            .args([
                "cpu",
                "get",
                "Name,Manufacturer,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed",
                "/format:csv",
            ])
            .output()
        {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                for line in stdout.lines().skip(1) {
                    let parts: Vec<&str> = line.split(',').collect();
                    if parts.len() >= 6 {
                        info.vendor = match parts[1].trim() {
                            "GenuineIntel" => "Intel".to_string(),
                            "AuthenticAMD" => "AMD".to_string(),
                            other => other.to_string(),
                        };
                        info.frequency_max_mhz = parts[2].trim().parse().unwrap_or(0);
                        info.model = parts[3].trim().to_string();
                        info.physical_cores = parts[4].trim().parse().unwrap_or(0);
                        info.logical_cores = parts[5].trim().parse().unwrap_or(0);
                        break;
                    }
                }
            }
        }

        // Fallback: use PowerShell if WMIC fails
        if info.model.is_empty() {
            if let Ok(output) = Command::new("powershell")
                .args(["-Command", "Get-CimInstance -ClassName Win32_Processor | Select-Object Name,Manufacturer,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed | ConvertTo-Json"])
                .output()
            {
                if output.status.success() {
                    let stdout = String::from_utf8_lossy(&output.stdout);
                    // Simple JSON parsing without external dependency
                    for line in stdout.lines() {
                        let line = line.trim();
                        if line.contains("\"Name\"") {
                            if let Some(val) = extract_json_string(line) {
                                info.model = val;
                            }
                        } else if line.contains("\"Manufacturer\"") {
                            if let Some(val) = extract_json_string(line) {
                                info.vendor = match val.as_str() {
                                    "GenuineIntel" => "Intel".to_string(),
                                    "AuthenticAMD" => "AMD".to_string(),
                                    other => other.to_string(),
                                };
                            }
                        } else if line.contains("\"NumberOfCores\"") {
                            if let Some(val) = extract_json_number(line) {
                                info.physical_cores = val;
                            }
                        } else if line.contains("\"NumberOfLogicalProcessors\"") {
                            if let Some(val) = extract_json_number(line) {
                                info.logical_cores = val;
                            }
                        } else if line.contains("\"MaxClockSpeed\"") {
                            if let Some(val) = extract_json_number(line) {
                                info.frequency_max_mhz = val as u64;
                            }
                        }
                    }
                }
            }
        }

        info
    }

    /// Get current CPU frequency in MHz
    fn get_current_frequency(system: &System) -> u64 {
        system
            .cpus()
            .first()
            .map(|cpu| cpu.frequency())
            .unwrap_or(0)
    }

    /// Get CPU temperature (platform-specific)
    fn get_temperature() -> f64 {
        #[cfg(target_os = "linux")]
        {
            use std::fs;
            // Try hwmon thermal zones
            let hwmon_path = "/sys/class/hwmon";
            if let Ok(entries) = fs::read_dir(hwmon_path) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    // Check if this is a CPU thermal sensor
                    if let Ok(name) = fs::read_to_string(path.join("name")) {
                        let name = name.trim();
                        if name.contains("coretemp")
                            || name.contains("k10temp")
                            || name.contains("cpu")
                        {
                            // Read temp1_input (in millidegrees)
                            if let Ok(temp) = fs::read_to_string(path.join("temp1_input")) {
                                if let Ok(temp_mc) = temp.trim().parse::<i64>() {
                                    return temp_mc as f64 / 1000.0;
                                }
                            }
                        }
                    }
                }
            }

            // Fallback to thermal zones
            if let Ok(temp) = fs::read_to_string("/sys/class/thermal/thermal_zone0/temp") {
                if let Ok(temp_mc) = temp.trim().parse::<i64>() {
                    return temp_mc as f64 / 1000.0;
                }
            }

            0.0
        }
        #[cfg(not(target_os = "linux"))]
        {
            0.0 // Temperature reading not easily available on macOS/Windows without admin
        }
    }

    /// Collect CPU metrics
    pub fn collect(&mut self, system: &System, config: &CollectorConfig) -> CpuMetrics {
        let global_cpu = system.global_cpu_usage();
        let cpu_info = CPU_INFO.get().expect("CPU info not initialized");

        // Collect per-core usage if enabled
        let per_core_usage = if config.enable_per_core_cpu {
            system
                .cpus()
                .iter()
                .map(|cpu| cpu.cpu_usage() as f64)
                .collect()
        } else {
            vec![]
        };

        CpuMetrics {
            usage_percent: global_cpu as f64,
            core_count: system.cpus().len() as u32,
            per_core_usage,
            model: cpu_info.model.clone(),
            vendor: cpu_info.vendor.clone(),
            frequency_mhz: Self::get_current_frequency(system),
            frequency_max_mhz: cpu_info.frequency_max_mhz,
            physical_cores: cpu_info.physical_cores,
            logical_cores: cpu_info.logical_cores,
            architecture: cpu_info.architecture.clone(),
            temperature: Self::get_temperature(),
        }
    }
}

impl Default for CpuCollector {
    fn default() -> Self {
        Self::new()
    }
}

/// Helper to extract string from JSON line
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

/// Helper to extract number from JSON line
fn extract_json_number(line: &str) -> Option<u32> {
    let parts: Vec<&str> = line.split(':').collect();
    if parts.len() >= 2 {
        let val_str = parts[1].trim().trim_matches(',').trim();
        val_str.parse().ok()
    } else {
        None
    }
}
