use std::collections::HashMap;
use std::sync::OnceLock;
use sysinfo::Disks;

use crate::config::CollectorConfig;
use crate::proto::DiskMetrics;

/// Static disk hardware info that doesn't change
static DISK_INFO: OnceLock<HashMap<String, DiskHardwareInfo>> = OnceLock::new();

#[derive(Debug, Clone, Default)]
struct DiskHardwareInfo {
    model: String,
    serial: String,
    disk_type: String, // "SSD", "HDD", "NVMe"
}

#[derive(Debug, Clone, Default)]
struct DiskIoStats {
    read_bytes: u64,
    write_bytes: u64,
    read_ops: u64,
    write_ops: u64,
}

/// Disk metrics collector
pub struct DiskCollector {
    /// Previous disk I/O stats for rate calculation
    prev_stats: HashMap<String, DiskIoStats>,
    prev_time: Option<std::time::Instant>,
}

impl DiskCollector {
    pub fn new() -> Self {
        // Initialize disk hardware info once
        DISK_INFO.get_or_init(Self::collect_disk_hardware_info);
        Self {
            prev_stats: HashMap::new(),
            prev_time: None,
        }
    }

    #[allow(unused_assignments)]
    fn collect_disk_hardware_info() -> HashMap<String, DiskHardwareInfo> {
        let mut info = HashMap::new();

        #[cfg(target_os = "linux")]
        {
            info = Self::collect_linux_disk_info();
        }

        #[cfg(target_os = "macos")]
        {
            info = Self::collect_macos_disk_info();
        }

        #[cfg(target_os = "windows")]
        {
            info = Self::collect_windows_disk_info();
        }

        info
    }

    #[cfg(target_os = "linux")]
    fn collect_linux_disk_info() -> HashMap<String, DiskHardwareInfo> {
        use std::fs;
        use std::path::Path;

        let mut info = HashMap::new();
        let block_path = Path::new("/sys/block");

        if let Ok(entries) = fs::read_dir(block_path) {
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().to_string();

                // Skip loop devices and other virtual devices
                if name.starts_with("loop") || name.starts_with("ram") || name.starts_with("dm-") {
                    continue;
                }

                let device_path = entry.path().join("device");
                let mut disk_info = DiskHardwareInfo::default();

                // Get model
                if let Ok(model) = fs::read_to_string(device_path.join("model")) {
                    disk_info.model = model.trim().to_string();
                }

                // Get serial (might require root)
                if let Ok(serial) = fs::read_to_string(device_path.join("serial")) {
                    disk_info.serial = serial.trim().to_string();
                }

                // Determine disk type
                let rotational_path = entry.path().join("queue/rotational");
                if let Ok(rotational) = fs::read_to_string(&rotational_path) {
                    disk_info.disk_type = if rotational.trim() == "0" {
                        // Check if it's NVMe
                        if name.starts_with("nvme") {
                            "NVMe".to_string()
                        } else {
                            "SSD".to_string()
                        }
                    } else {
                        "HDD".to_string()
                    };
                }

                // Use device name as key (e.g., "sda", "nvme0n1")
                info.insert(name.clone(), disk_info);

                // Also add with /dev/ prefix
                info.insert(
                    format!("/dev/{}", name),
                    info.get(&name).cloned().unwrap_or_default(),
                );
            }
        }

        info
    }

    #[cfg(target_os = "macos")]
    fn collect_macos_disk_info() -> HashMap<String, DiskHardwareInfo> {
        use std::process::Command;

        let mut info = HashMap::new();

        // Use diskutil to get disk info
        if let Ok(output) = Command::new("diskutil").args(["list", "-plist"]).output() {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                // Parse plist to get disk identifiers
                let mut current_disk = String::new();

                for line in stdout.lines() {
                    if line.contains("<string>disk") {
                        if let Some(start) = line.find("<string>") {
                            if let Some(end) = line.find("</string>") {
                                current_disk = line[start + 8..end].to_string();
                            }
                        }
                    }
                }

                // Get detailed info for each disk
                if !current_disk.is_empty() {
                    if let Ok(detail_output) = Command::new("diskutil")
                        .args(["info", &current_disk])
                        .output()
                    {
                        if detail_output.status.success() {
                            let detail = String::from_utf8_lossy(&detail_output.stdout);
                            let mut disk_info = DiskHardwareInfo::default();

                            for line in detail.lines() {
                                if line.contains("Device / Media Name:") {
                                    if let Some(val) = line.split(':').nth(1) {
                                        disk_info.model = val.trim().to_string();
                                    }
                                } else if line.contains("Solid State:") {
                                    disk_info.disk_type = if line.contains("Yes") {
                                        if disk_info.model.to_lowercase().contains("nvme") {
                                            "NVMe".to_string()
                                        } else {
                                            "SSD".to_string()
                                        }
                                    } else {
                                        "HDD".to_string()
                                    };
                                }
                            }

                            info.insert(current_disk.clone(), disk_info.clone());
                            info.insert(format!("/dev/{}", current_disk), disk_info);
                        }
                    }
                }
            }
        }

        info
    }

    #[cfg(target_os = "windows")]
    fn collect_windows_disk_info() -> HashMap<String, DiskHardwareInfo> {
        use std::process::Command;

        let mut info = HashMap::new();

        // Use WMIC to get disk info
        if let Ok(output) = Command::new("wmic")
            .args([
                "diskdrive",
                "get",
                "DeviceID,Model,SerialNumber,MediaType",
                "/format:csv",
            ])
            .output()
        {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);

                for line in stdout.lines().skip(1) {
                    let parts: Vec<&str> = line.split(',').collect();
                    if parts.len() >= 5 {
                        let device_id = parts[1].trim();
                        let media_type = parts[2].trim();
                        let model = parts[3].trim();
                        let serial = parts[4].trim();

                        let disk_type = if media_type.to_lowercase().contains("ssd") {
                            "SSD".to_string()
                        } else if media_type.to_lowercase().contains("fixed") {
                            // Check model name for hints
                            if model.to_lowercase().contains("nvme") {
                                "NVMe".to_string()
                            } else if model.to_lowercase().contains("ssd") {
                                "SSD".to_string()
                            } else {
                                "HDD".to_string()
                            }
                        } else {
                            "Unknown".to_string()
                        };

                        let disk_info = DiskHardwareInfo {
                            model: model.to_string(),
                            serial: serial.to_string(),
                            disk_type,
                        };

                        info.insert(device_id.to_string(), disk_info);
                    }
                }
            }
        }

        // Fallback to PowerShell
        if info.is_empty() {
            if let Ok(output) = Command::new("powershell")
                .args(["-Command", "Get-PhysicalDisk | Select-Object DeviceId,FriendlyName,SerialNumber,MediaType | ConvertTo-Json"])
                .output()
            {
                if output.status.success() {
                    let stdout = String::from_utf8_lossy(&output.stdout);
                    let mut current_device = String::new();
                    let mut current_info = DiskHardwareInfo::default();

                    for line in stdout.lines() {
                        let line = line.trim();
                        if line.contains("\"DeviceId\"") {
                            if let Some(val) = extract_json_value(line) {
                                current_device = val;
                            }
                        } else if line.contains("\"FriendlyName\"") {
                            if let Some(val) = extract_json_value(line) {
                                current_info.model = val;
                            }
                        } else if line.contains("\"SerialNumber\"") {
                            if let Some(val) = extract_json_value(line) {
                                current_info.serial = val;
                            }
                        } else if line.contains("\"MediaType\"") {
                            if let Some(val) = extract_json_value(line) {
                                current_info.disk_type = match val.as_str() {
                                    "4" | "SSD" => "SSD".to_string(),
                                    "3" | "HDD" => "HDD".to_string(),
                                    _ => {
                                        if current_info.model.to_lowercase().contains("nvme") {
                                            "NVMe".to_string()
                                        } else {
                                            "Unknown".to_string()
                                        }
                                    }
                                };
                            }
                        } else if line == "}" || line == "}," {
                            if !current_device.is_empty() {
                                info.insert(current_device.clone(), current_info.clone());
                                current_device.clear();
                                current_info = DiskHardwareInfo::default();
                            }
                        }
                    }
                }
            }
        }

        info
    }

    /// Read disk I/O stats (Linux-specific implementation)
    #[cfg(target_os = "linux")]
    fn read_disk_io_stats() -> HashMap<String, DiskIoStats> {
        use std::fs;

        let mut stats = HashMap::new();

        if let Ok(content) = fs::read_to_string("/proc/diskstats") {
            for line in content.lines() {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 14 {
                    let device = parts[2].to_string();

                    // Skip partitions, only track whole disks
                    if device
                        .chars()
                        .last()
                        .map(|c| c.is_numeric())
                        .unwrap_or(false)
                        && !device.starts_with("nvme")
                    {
                        continue;
                    }

                    let read_ops: u64 = parts[3].parse().unwrap_or(0);
                    let read_sectors: u64 = parts[5].parse().unwrap_or(0);
                    let write_ops: u64 = parts[7].parse().unwrap_or(0);
                    let write_sectors: u64 = parts[9].parse().unwrap_or(0);

                    // Sector size is typically 512 bytes
                    stats.insert(
                        device,
                        DiskIoStats {
                            read_bytes: read_sectors * 512,
                            write_bytes: write_sectors * 512,
                            read_ops,
                            write_ops,
                        },
                    );
                }
            }
        }

        stats
    }

    #[cfg(not(target_os = "linux"))]
    fn read_disk_io_stats() -> HashMap<String, DiskIoStats> {
        HashMap::new()
    }

    /// Get disk temperature using smartctl (if available)
    #[allow(unused_variables)]
    fn get_disk_temperature(device: &str) -> f64 {
        #[cfg(target_os = "linux")]
        {
            use std::process::Command;

            // Try smartctl (requires smartmontools)
            if let Ok(output) = Command::new("smartctl").args(["-A", device]).output() {
                if output.status.success() {
                    let stdout = String::from_utf8_lossy(&output.stdout);
                    for line in stdout.lines() {
                        if line.contains("Temperature_Celsius")
                            || line.contains("Airflow_Temperature")
                        {
                            let parts: Vec<&str> = line.split_whitespace().collect();
                            if parts.len() >= 10 {
                                if let Ok(temp) = parts[9].parse::<f64>() {
                                    return temp;
                                }
                            }
                        }
                    }
                }
            }

            // Try hwmon for NVMe
            if device.contains("nvme") {
                use std::fs;
                let hwmon_base = "/sys/class/hwmon";
                if let Ok(entries) = fs::read_dir(hwmon_base) {
                    for entry in entries.flatten() {
                        let path = entry.path();
                        if let Ok(name) = fs::read_to_string(path.join("name")) {
                            if name.trim().contains("nvme") {
                                if let Ok(temp) = fs::read_to_string(path.join("temp1_input")) {
                                    if let Ok(temp_mc) = temp.trim().parse::<i64>() {
                                        return temp_mc as f64 / 1000.0;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        0.0
    }

    /// Get S.M.A.R.T. health status
    #[allow(unused_variables)]
    fn get_smart_health(device: &str) -> String {
        #[cfg(target_os = "linux")]
        {
            use std::process::Command;

            if let Ok(output) = Command::new("smartctl").args(["-H", device]).output() {
                if output.status.success() {
                    let stdout = String::from_utf8_lossy(&output.stdout);
                    if stdout.contains("PASSED") {
                        return "PASSED".to_string();
                    } else if stdout.contains("FAILED") {
                        return "FAILED".to_string();
                    }
                }
            }
        }

        "Unknown".to_string()
    }

    /// Collect disk metrics
    pub fn collect(&mut self, disks: &Disks, _config: &CollectorConfig) -> Vec<DiskMetrics> {
        let now = std::time::Instant::now();
        let current_io_stats = Self::read_disk_io_stats();
        let empty_map = HashMap::new();
        let disk_info = DISK_INFO.get().unwrap_or(&empty_map);

        let elapsed_secs = self
            .prev_time
            .map(|t| now.duration_since(t).as_secs_f64())
            .unwrap_or(1.0);

        let mut metrics = Vec::new();

        for disk in disks.list() {
            let mount_point = disk.mount_point().to_string_lossy().to_string();
            let device = disk.name().to_string_lossy().to_string();
            let fs_type = disk.file_system().to_string_lossy().to_string();
            let total = disk.total_space();
            let available = disk.available_space();
            let used = total.saturating_sub(available);

            // Extract base device name for hardware info lookup
            let base_device = device
                .trim_start_matches("/dev/")
                .chars()
                .take_while(|c| !c.is_numeric() || device.contains("nvme"))
                .collect::<String>();

            let hw_info = disk_info
                .get(&device)
                .or_else(|| disk_info.get(&base_device))
                .cloned()
                .unwrap_or_default();

            // Calculate I/O rates
            let (read_bytes_sec, write_bytes_sec, read_iops, write_iops) =
                if let Some(current) = current_io_stats.get(&base_device) {
                    if let Some(prev) = self.prev_stats.get(&base_device) {
                        let read_diff = current.read_bytes.saturating_sub(prev.read_bytes);
                        let write_diff = current.write_bytes.saturating_sub(prev.write_bytes);
                        let read_ops_diff = current.read_ops.saturating_sub(prev.read_ops);
                        let write_ops_diff = current.write_ops.saturating_sub(prev.write_ops);

                        (
                            (read_diff as f64 / elapsed_secs) as u64,
                            (write_diff as f64 / elapsed_secs) as u64,
                            (read_ops_diff as f64 / elapsed_secs) as u64,
                            (write_ops_diff as f64 / elapsed_secs) as u64,
                        )
                    } else {
                        (0, 0, 0, 0)
                    }
                } else {
                    (0, 0, 0, 0)
                };

            let temperature = Self::get_disk_temperature(&format!("/dev/{}", base_device));
            let health_status = Self::get_smart_health(&format!("/dev/{}", base_device));

            metrics.push(DiskMetrics {
                mount_point,
                device,
                fs_type,
                total,
                used,
                available,
                read_bytes_sec,
                write_bytes_sec,
                model: hw_info.model,
                serial: hw_info.serial,
                disk_type: hw_info.disk_type,
                read_iops,
                write_iops,
                temperature,
                health_status,
            });
        }

        // Update previous stats
        self.prev_stats = current_io_stats;
        self.prev_time = Some(now);

        metrics
    }
}

impl Default for DiskCollector {
    fn default() -> Self {
        Self::new()
    }
}

/// Helper to extract value from JSON-like line
fn extract_json_value(line: &str) -> Option<String> {
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
