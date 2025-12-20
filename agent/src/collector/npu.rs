//! NPU (Neural Processing Unit) collector
//!
//! Collects information about AI accelerators across platforms:
//! - Intel NPU (via xpu-smi)
//! - Huawei Ascend (via npu-smi)
//! - Other accelerators

use std::process::Command;

/// NPU metrics
#[derive(Debug, Clone, Default)]
pub struct NpuMetrics {
    pub index: u32,
    pub name: String,
    pub vendor: String, // "Intel", "Huawei", "Qualcomm", etc.
    pub usage_percent: f64,
    pub memory_total: u64,
    pub memory_used: u64,
    pub temperature: f64,
    pub power_watts: u32,
    pub driver_version: String,
}

/// NPU collector
pub struct NpuCollector {
    intel_available: bool,
    huawei_available: bool,
}

impl NpuCollector {
    pub fn new() -> Self {
        Self {
            intel_available: Self::check_intel_npu_available(),
            huawei_available: Self::check_huawei_npu_available(),
        }
    }

    /// Check if Intel NPU tools are available
    fn check_intel_npu_available() -> bool {
        // Check for xpu-smi (Intel data center accelerators)
        if Command::new("xpu-smi")
            .arg("discovery")
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false)
        {
            return true;
        }

        // Check for Intel NPU driver via sysfs (Intel Core Ultra NPU)
        #[cfg(target_os = "linux")]
        {
            use std::path::Path;
            if Path::new("/sys/class/accel").exists() {
                return true;
            }
        }

        false
    }

    /// Check if Huawei NPU tools are available
    fn check_huawei_npu_available() -> bool {
        Command::new("npu-smi")
            .arg("info")
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false)
    }

    /// Collect all NPU metrics
    pub fn collect(&self) -> Vec<NpuMetrics> {
        let mut npus = Vec::new();

        if self.intel_available {
            if let Some(intel_npus) = self.collect_intel() {
                npus.extend(intel_npus);
            }
        }

        if self.huawei_available {
            if let Some(huawei_npus) = self.collect_huawei() {
                npus.extend(huawei_npus);
            }
        }

        // Try to detect Intel NPU via sysfs
        #[cfg(target_os = "linux")]
        if npus.is_empty() {
            if let Some(sysfs_npus) = self.collect_intel_sysfs() {
                npus.extend(sysfs_npus);
            }
        }

        npus
    }

    /// Collect Intel NPU metrics via xpu-smi
    fn collect_intel(&self) -> Option<Vec<NpuMetrics>> {
        let output = Command::new("xpu-smi").arg("discovery").output().ok()?;

        if !output.status.success() {
            return None;
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let mut npus = Vec::new();
        let mut current_index = 0u32;

        // Parse xpu-smi discovery output
        for line in stdout.lines() {
            if line.contains("Device Name") {
                let name = line
                    .split(':')
                    .nth(1)
                    .map(|s| s.trim().to_string())
                    .unwrap_or_default();

                let mut npu = NpuMetrics {
                    index: current_index,
                    name,
                    vendor: "Intel".to_string(),
                    ..Default::default()
                };

                // Get detailed stats for this device
                if let Some(stats) = self.get_intel_device_stats(current_index) {
                    npu.usage_percent = stats.0;
                    npu.memory_total = stats.1;
                    npu.memory_used = stats.2;
                    npu.temperature = stats.3;
                    npu.power_watts = stats.4;
                }

                npus.push(npu);
                current_index += 1;
            }
        }

        if npus.is_empty() {
            None
        } else {
            Some(npus)
        }
    }

    /// Get Intel device statistics
    fn get_intel_device_stats(&self, device_id: u32) -> Option<(f64, u64, u64, f64, u32)> {
        let output = Command::new("xpu-smi")
            .args(["stats", "-d", &device_id.to_string()])
            .output()
            .ok()?;

        if !output.status.success() {
            return None;
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let mut usage = 0.0;
        let mut mem_total = 0u64;
        let mut mem_used = 0u64;
        let mut temp = 0.0;
        let mut power = 0u32;

        for line in stdout.lines() {
            if line.contains("GPU Utilization") {
                usage = Self::extract_number(line);
            } else if line.contains("GPU Memory Total") {
                mem_total = Self::extract_bytes(line);
            } else if line.contains("GPU Memory Used") {
                mem_used = Self::extract_bytes(line);
            } else if line.contains("GPU Temperature") {
                temp = Self::extract_number(line);
            } else if line.contains("GPU Power") {
                power = Self::extract_number(line) as u32;
            }
        }

        Some((usage, mem_total, mem_used, temp, power))
    }

    /// Collect Intel NPU via sysfs (Linux)
    #[cfg(target_os = "linux")]
    fn collect_intel_sysfs(&self) -> Option<Vec<NpuMetrics>> {
        use std::fs;
        use std::path::Path;

        let accel_path = Path::new("/sys/class/accel");
        if !accel_path.exists() {
            return None;
        }

        let mut npus = Vec::new();
        let mut index = 0u32;

        if let Ok(entries) = fs::read_dir(accel_path) {
            for entry in entries.flatten() {
                let path = entry.path();
                let name = path.file_name()?.to_str()?;

                if name.starts_with("accel") {
                    let device_path = path.join("device");

                    // Check if it's an Intel device
                    let vendor_path = device_path.join("vendor");
                    if let Ok(vendor) = fs::read_to_string(&vendor_path) {
                        // Intel vendor ID
                        if vendor.trim() == "0x8086" {
                            let mut npu = NpuMetrics {
                                index,
                                vendor: "Intel".to_string(),
                                name: "Intel NPU".to_string(),
                                ..Default::default()
                            };

                            // Try to get device name
                            if let Ok(device_name) =
                                fs::read_to_string(device_path.join("device_name"))
                            {
                                npu.name = device_name.trim().to_string();
                            }

                            npus.push(npu);
                            index += 1;
                        }
                    }
                }
            }
        }

        if npus.is_empty() {
            None
        } else {
            Some(npus)
        }
    }

    /// Collect Huawei Ascend NPU metrics
    fn collect_huawei(&self) -> Option<Vec<NpuMetrics>> {
        let output = Command::new("npu-smi").arg("info").output().ok()?;

        if !output.status.success() {
            return None;
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let mut npus = Vec::new();
        let mut current_npu: Option<NpuMetrics> = None;

        for line in stdout.lines() {
            // Parse device header
            if line.contains("NPU ID") {
                // Save previous NPU if exists
                if let Some(npu) = current_npu.take() {
                    npus.push(npu);
                }

                let index: u32 = line
                    .split_whitespace()
                    .nth(2)
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(0);

                current_npu = Some(NpuMetrics {
                    index,
                    vendor: "Huawei".to_string(),
                    name: "Ascend NPU".to_string(),
                    ..Default::default()
                });
            }

            if let Some(ref mut npu) = current_npu {
                if line.contains("Chip Name") {
                    npu.name = line
                        .split(':')
                        .nth(1)
                        .map(|s| s.trim().to_string())
                        .unwrap_or_else(|| "Ascend NPU".to_string());
                } else if line.contains("Aicore Usage Rate") {
                    npu.usage_percent = Self::extract_number(line);
                } else if line.contains("HBM Usage Rate") {
                    // Parse HBM as memory usage
                    npu.usage_percent = Self::extract_number(line);
                } else if line.contains("Chip Temp") {
                    npu.temperature = Self::extract_number(line);
                } else if line.contains("Power") {
                    npu.power_watts = Self::extract_number(line) as u32;
                }
            }
        }

        // Don't forget the last NPU
        if let Some(npu) = current_npu {
            npus.push(npu);
        }

        if npus.is_empty() {
            None
        } else {
            Some(npus)
        }
    }

    /// Extract numeric value from a line
    fn extract_number(line: &str) -> f64 {
        // Find first numeric value in line
        for part in line.split_whitespace() {
            let cleaned = part
                .trim_end_matches('%')
                .trim_end_matches('C')
                .trim_end_matches('W');
            if let Ok(num) = cleaned.parse::<f64>() {
                return num;
            }
        }
        0.0
    }

    /// Extract bytes value from a line (handles MB, GB, etc.)
    fn extract_bytes(line: &str) -> u64 {
        let parts: Vec<&str> = line.split_whitespace().collect();
        for (i, part) in parts.iter().enumerate() {
            if let Ok(num) = part.parse::<f64>() {
                // Check for unit in next part
                let unit = parts.get(i + 1).map(|s| s.to_uppercase());
                return match unit.as_deref() {
                    Some("KB") | Some("KIB") => (num * 1024.0) as u64,
                    Some("MB") | Some("MIB") => (num * 1024.0 * 1024.0) as u64,
                    Some("GB") | Some("GIB") => (num * 1024.0 * 1024.0 * 1024.0) as u64,
                    _ => num as u64,
                };
            }
        }
        0
    }
}

impl Default for NpuCollector {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_npu_collector_new() {
        let collector = NpuCollector::new();
        // Just verify it doesn't panic
        println!("Intel NPU available: {}", collector.intel_available);
        println!("Huawei NPU available: {}", collector.huawei_available);
    }

    #[test]
    fn test_collect_npus() {
        let collector = NpuCollector::new();
        let npus = collector.collect();
        println!("Found {} NPUs", npus.len());
        for npu in &npus {
            println!("  NPU {}: {} ({})", npu.index, npu.name, npu.vendor);
        }
    }

    #[test]
    fn test_extract_number() {
        assert_eq!(NpuCollector::extract_number("Usage: 50%"), 50.0);
        assert_eq!(NpuCollector::extract_number("Temperature: 45C"), 45.0);
        assert_eq!(NpuCollector::extract_number("Power: 75W"), 75.0);
    }
}
