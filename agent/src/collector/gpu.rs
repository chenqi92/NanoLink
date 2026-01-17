use std::process::Command;
use std::time::{Duration, Instant};

use parking_lot::RwLock;

use crate::utils::safe_command::exec_with_timeout;

/// Default cache duration for GPU metrics (5 seconds)
const GPU_CACHE_DURATION: Duration = Duration::from_secs(5);

#[derive(Debug, Clone, Default)]
pub struct GpuMetrics {
    pub index: u32,
    pub name: String,
    pub vendor: String,
    pub usage_percent: f64,
    pub memory_total: u64,
    pub memory_used: u64,
    pub temperature: f64,
    pub fan_speed_percent: u32,
    pub power_watts: u32,
    pub power_limit_watts: u32,
    pub clock_core_mhz: u64,
    pub clock_memory_mhz: u64,
    pub driver_version: String,
    pub pcie_generation: String,
    pub encoder_usage: f64,
    pub decoder_usage: f64,
}

/// GPU command timeout - 15 seconds for nvidia-smi under load
const GPU_COMMAND_TIMEOUT: Duration = Duration::from_secs(15);
/// Fast GPU availability check timeout
const GPU_CHECK_TIMEOUT: Duration = Duration::from_secs(5);

/// GPU metrics collector
/// Supports NVIDIA (via nvidia-smi), AMD (via rocm-smi), and Intel (via xpu-smi/intel_gpu_top/sysfs)
#[allow(dead_code)]
pub struct GpuCollector {
    nvidia_available: bool,
    amd_available: bool,
    /// Intel GPU monitoring via intel_gpu_top (requires root on Linux)
    intel_gpu_top_available: bool,
    /// Intel GPU monitoring via xpu-smi (for Arc/Data Center GPUs on Linux)
    xpu_smi_available: bool,
    driver_version: String,
    /// Cached metrics with timestamp for reducing nvidia-smi calls
    cached_metrics: RwLock<Option<(Vec<GpuMetrics>, Instant)>>,
}

impl GpuCollector {
    pub fn new() -> Self {
        let nvidia_available = Self::check_nvidia_available();
        let amd_available = Self::check_amd_available();
        let driver_version = if nvidia_available {
            Self::get_nvidia_driver_version().unwrap_or_default()
        } else {
            String::new()
        };

        // Check Intel GPU tools availability (Linux only, non-blocking)
        let intel_gpu_top_available = Self::check_intel_gpu_top_available();
        let xpu_smi_available = Self::check_xpu_smi_available();

        Self {
            nvidia_available,
            amd_available,
            intel_gpu_top_available,
            xpu_smi_available,
            driver_version,
            cached_metrics: RwLock::new(None),
        }
    }

    fn check_nvidia_available() -> bool {
        let mut cmd = Command::new("nvidia-smi");
        cmd.args(["--query-gpu=name", "--format=csv,noheader"]);
        exec_with_timeout(cmd, GPU_CHECK_TIMEOUT)
            .map(|o| o.status.success())
            .unwrap_or(false)
    }

    fn check_amd_available() -> bool {
        #[cfg(target_os = "linux")]
        {
            let mut cmd = Command::new("rocm-smi");
            cmd.arg("--showproductname");
            exec_with_timeout(cmd, GPU_CHECK_TIMEOUT)
                .map(|o| o.status.success())
                .unwrap_or(false)
        }
        #[cfg(not(target_os = "linux"))]
        {
            false
        }
    }

    /// Check if intel_gpu_top is available (Linux only, requires root/CAP_PERFMON)
    fn check_intel_gpu_top_available() -> bool {
        #[cfg(target_os = "linux")]
        {
            // Quick check if intel_gpu_top exists and can output JSON
            // Use very short timeout to avoid blocking startup
            let mut cmd = Command::new("intel_gpu_top");
            cmd.args(["-J", "-s", "100", "-o", "-"]);
            // Just check if the command exists, don't wait for full output
            match Command::new("which").arg("intel_gpu_top").output() {
                Ok(output) => output.status.success(),
                Err(_) => false,
            }
        }
        #[cfg(not(target_os = "linux"))]
        {
            false
        }
    }

    /// Check if xpu-smi is available (Linux only, for Intel Arc/Data Center GPUs)
    fn check_xpu_smi_available() -> bool {
        #[cfg(target_os = "linux")]
        {
            let mut cmd = Command::new("xpu-smi");
            cmd.arg("discovery");
            exec_with_timeout(cmd, GPU_CHECK_TIMEOUT)
                .map(|o| o.status.success())
                .unwrap_or(false)
        }
        #[cfg(not(target_os = "linux"))]
        {
            false
        }
    }

    fn get_nvidia_driver_version() -> Option<String> {
        let mut cmd = Command::new("nvidia-smi");
        cmd.args(["--query-gpu=driver_version", "--format=csv,noheader"]);

        let output = exec_with_timeout(cmd, GPU_CHECK_TIMEOUT)?;
        if output.status.success() {
            let version = String::from_utf8_lossy(&output.stdout)
                .trim()
                .lines()
                .next()
                .unwrap_or("")
                .to_string();
            Some(version)
        } else {
            None
        }
    }

    pub fn collect(&self) -> Vec<GpuMetrics> {
        // Check cache first to avoid expensive nvidia-smi calls
        {
            let cache = self.cached_metrics.read();
            if let Some((metrics, cached_at)) = cache.as_ref() {
                if cached_at.elapsed() < GPU_CACHE_DURATION {
                    return metrics.clone();
                }
            }
        }

        // Cache miss or expired - collect fresh metrics
        let mut gpus = Vec::new();

        // NVIDIA is supported on all platforms via nvidia-smi
        if self.nvidia_available {
            if let Some(nvidia_gpus) = self.collect_nvidia() {
                gpus.extend(nvidia_gpus);
            }
        }

        // Platform-specific GPU collection
        #[cfg(target_os = "linux")]
        {
            // AMD via rocm-smi (Linux only)
            if self.amd_available {
                if let Some(amd_gpus) = self.collect_amd() {
                    gpus.extend(amd_gpus);
                }
            }

            // AMD APU via sysfs (fallback for APUs without ROCm support)
            // Only try if rocm-smi is not available or didn't find any GPUs
            if !self.amd_available || gpus.iter().all(|g| g.vendor != "AMD") {
                if let Some(amd_apu_gpus) = self.collect_amd_apu_sysfs() {
                    gpus.extend(amd_apu_gpus);
                }
            }

            // Intel via xpu-smi/intel_gpu_top/sysfs (Linux only)
            if let Some(intel_gpus) = self.collect_intel() {
                gpus.extend(intel_gpus);
            }
        }

        #[cfg(target_os = "windows")]
        {
            // Collect AMD/Intel GPUs via WMI/PowerShell on Windows
            // Skip if we already have GPUs (to avoid duplicating NVIDIA)
            let nvidia_names: Vec<String> = gpus.iter().map(|g| g.name.clone()).collect();
            if let Some(win_gpus) = self.collect_windows_gpu(&nvidia_names) {
                gpus.extend(win_gpus);
            }
        }

        #[cfg(target_os = "macos")]
        {
            // Collect GPUs via system_profiler on macOS
            let nvidia_names: Vec<String> = gpus.iter().map(|g| g.name.clone()).collect();
            if let Some(mac_gpus) = self.collect_macos_gpu(&nvidia_names) {
                gpus.extend(mac_gpus);
            }
        }

        // Update cache
        *self.cached_metrics.write() = Some((gpus.clone(), Instant::now()));

        gpus
    }

    fn collect_nvidia(&self) -> Option<Vec<GpuMetrics>> {
        let mut cmd = Command::new("nvidia-smi");
        cmd.args([
            "--query-gpu=index,name,utilization.gpu,memory.total,memory.used,temperature.gpu,fan.speed,power.draw,power.limit,clocks.current.graphics,clocks.current.memory,pcie.link.gen.current,pcie.link.width.current,utilization.encoder,utilization.decoder",
            "--format=csv,noheader,nounits"
        ]);

        let output = exec_with_timeout(cmd, GPU_COMMAND_TIMEOUT)?;
        if !output.status.success() {
            return None;
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let mut gpus = Vec::new();

        for line in stdout.lines() {
            let parts: Vec<&str> = line.split(',').map(|s| s.trim()).collect();
            if parts.len() >= 15 {
                let index = parts[0].parse().unwrap_or(0);
                let pcie_gen = parts[11].trim();
                let pcie_width = parts[12].trim();

                gpus.push(GpuMetrics {
                    index,
                    name: parts[1].to_string(),
                    vendor: "NVIDIA".to_string(),
                    usage_percent: parts[2].parse().unwrap_or(0.0),
                    memory_total: Self::parse_mib_to_bytes(parts[3]),
                    memory_used: Self::parse_mib_to_bytes(parts[4]),
                    temperature: parts[5].parse().unwrap_or(0.0),
                    fan_speed_percent: parts[6].parse().unwrap_or(0),
                    power_watts: parts[7].parse::<f64>().unwrap_or(0.0) as u32,
                    power_limit_watts: parts[8].parse::<f64>().unwrap_or(0.0) as u32,
                    clock_core_mhz: parts[9].parse().unwrap_or(0),
                    clock_memory_mhz: parts[10].parse().unwrap_or(0),
                    driver_version: self.driver_version.clone(),
                    pcie_generation: format!("Gen{pcie_gen} x{pcie_width}"),
                    encoder_usage: parts[13].parse().unwrap_or(0.0),
                    decoder_usage: parts[14].parse().unwrap_or(0.0),
                });
            }
        }

        Some(gpus)
    }

    #[cfg(target_os = "linux")]
    fn collect_amd(&self) -> Option<Vec<GpuMetrics>> {
        use std::collections::HashMap;

        let mut gpus = Vec::new();

        let mut cmd = Command::new("rocm-smi");
        cmd.arg("--showproductname");
        let list_output = exec_with_timeout(cmd, GPU_COMMAND_TIMEOUT)?;

        if !list_output.status.success() {
            return None;
        }

        let stdout = String::from_utf8_lossy(&list_output.stdout);
        let mut gpu_names: HashMap<u32, String> = HashMap::new();

        for line in stdout.lines() {
            if line.contains("GPU[") {
                if let Some(idx_start) = line.find('[') {
                    if let Some(idx_end) = line.find(']') {
                        let idx: u32 = line[idx_start + 1..idx_end].parse().unwrap_or(0);
                        if let Some(name_part) = line.split(':').nth(1) {
                            gpu_names.insert(idx, name_part.trim().to_string());
                        }
                    }
                }
            }
        }

        for (index, name) in gpu_names {
            let metrics = self.collect_amd_gpu_metrics(index, &name);
            gpus.push(metrics);
        }

        Some(gpus)
    }

    #[cfg(target_os = "linux")]
    fn collect_amd_gpu_metrics(&self, index: u32, name: &str) -> GpuMetrics {
        let mut metrics = GpuMetrics {
            index,
            name: name.to_string(),
            vendor: "AMD".to_string(),
            ..Default::default()
        };

        // Get GPU usage
        let mut cmd = Command::new("rocm-smi");
        cmd.args(["-d", &index.to_string(), "--showuse"]);
        if let Some(output) = exec_with_timeout(cmd, GPU_COMMAND_TIMEOUT) {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines() {
                if line.contains("GPU use") {
                    if let Some(val) = line.split(':').nth(1) {
                        metrics.usage_percent =
                            val.trim().trim_end_matches('%').parse().unwrap_or(0.0);
                    }
                }
            }
        }

        // Get memory info
        let mut cmd = Command::new("rocm-smi");
        cmd.args(["-d", &index.to_string(), "--showmeminfo", "vram"]);
        if let Some(output) = exec_with_timeout(cmd, GPU_COMMAND_TIMEOUT) {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines() {
                if line.contains("Total Memory") {
                    if let Some(val) = line.split(':').nth(1) {
                        metrics.memory_total = Self::parse_memory_string(val.trim());
                    }
                } else if line.contains("Used Memory") {
                    if let Some(val) = line.split(':').nth(1) {
                        metrics.memory_used = Self::parse_memory_string(val.trim());
                    }
                }
            }
        }

        // Get temperature
        let mut cmd = Command::new("rocm-smi");
        cmd.args(["-d", &index.to_string(), "--showtemp"]);
        if let Some(output) = exec_with_timeout(cmd, GPU_COMMAND_TIMEOUT) {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines() {
                if line.contains("Temperature") && line.contains("edge") {
                    if let Some(val) = line.split(':').nth(1) {
                        metrics.temperature = val
                            .trim()
                            .trim_end_matches('c')
                            .trim()
                            .parse()
                            .unwrap_or(0.0);
                    }
                }
            }
        }

        // Get fan speed
        let mut cmd = Command::new("rocm-smi");
        cmd.args(["-d", &index.to_string(), "--showfan"]);
        if let Some(output) = exec_with_timeout(cmd, GPU_COMMAND_TIMEOUT) {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines() {
                if line.contains("Fan Speed") {
                    if let Some(val) = line.split(':').nth(1) {
                        metrics.fan_speed_percent =
                            val.trim().trim_end_matches('%').trim().parse().unwrap_or(0);
                    }
                }
            }
        }

        // Get power
        let mut cmd = Command::new("rocm-smi");
        cmd.args(["-d", &index.to_string(), "--showpower"]);
        if let Some(output) = exec_with_timeout(cmd, GPU_COMMAND_TIMEOUT) {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines() {
                if line.contains("Average Graphics Package Power") {
                    if let Some(val) = line.split(':').nth(1) {
                        metrics.power_watts = val
                            .split_whitespace()
                            .next()
                            .unwrap_or("0")
                            .parse()
                            .unwrap_or(0);
                    }
                }
            }
        }

        // Get clocks
        let mut cmd = Command::new("rocm-smi");
        cmd.args(["-d", &index.to_string(), "--showclocks"]);
        if let Some(output) = exec_with_timeout(cmd, GPU_COMMAND_TIMEOUT) {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines() {
                if line.contains("sclk") {
                    if let Some(val) = line.split(':').nth(1) {
                        metrics.clock_core_mhz = val
                            .trim()
                            .trim_end_matches("Mhz")
                            .trim()
                            .parse()
                            .unwrap_or(0);
                    }
                } else if line.contains("mclk") {
                    if let Some(val) = line.split(':').nth(1) {
                        metrics.clock_memory_mhz = val
                            .trim()
                            .trim_end_matches("Mhz")
                            .trim()
                            .parse()
                            .unwrap_or(0);
                    }
                }
            }
        }

        metrics
    }

    #[cfg(target_os = "linux")]
    fn collect_intel(&self) -> Option<Vec<GpuMetrics>> {
        // Try xpu-smi first (for Arc/Data Center GPUs - provides most complete data)
        if self.xpu_smi_available {
            if let Some(gpus) = self.collect_intel_xpu_smi() {
                if !gpus.is_empty() {
                    return Some(gpus);
                }
            }
        }

        // Try intel_gpu_top next (for integrated GPUs - requires root)
        if self.intel_gpu_top_available {
            if let Some(gpus) = self.collect_intel_gpu_top() {
                if !gpus.is_empty() {
                    return Some(gpus);
                }
            }
        }

        // Fallback to sysfs-based detection (basic info only, no usage metrics)
        self.collect_intel_sysfs()
    }

    /// Collect Intel GPU metrics using xpu-smi (for Arc/Data Center GPUs)
    #[cfg(target_os = "linux")]
    fn collect_intel_xpu_smi(&self) -> Option<Vec<GpuMetrics>> {
        use std::collections::HashMap;

        // Get device list first
        let mut cmd = Command::new("xpu-smi");
        cmd.args(["discovery", "-j"]);
        let discovery_output = exec_with_timeout(cmd, GPU_COMMAND_TIMEOUT)?;

        if !discovery_output.status.success() {
            return None;
        }

        let stdout = String::from_utf8_lossy(&discovery_output.stdout);

        // Parse JSON to get device IDs
        // xpu-smi discovery -j returns: {"device_list":[{"device_id":0,"device_name":"..."},...]}
        let mut gpus = Vec::new();
        let mut device_ids: Vec<u32> = Vec::new();

        // Simple JSON parsing for device_id
        for line in stdout.lines() {
            if line.contains("\"device_id\"") {
                if let Some(id_str) = line.split(':').nth(1) {
                    let id = id_str
                        .trim()
                        .trim_matches(',')
                        .trim_matches('}')
                        .parse()
                        .unwrap_or(0);
                    device_ids.push(id);
                }
            }
        }

        // Collect stats for each device
        for device_id in device_ids {
            let mut gpu = GpuMetrics {
                index: device_id,
                vendor: "Intel".to_string(),
                ..Default::default()
            };

            // Get device stats
            let mut cmd = Command::new("xpu-smi");
            cmd.args(["stats", "-d", &device_id.to_string()]);
            if let Some(output) = exec_with_timeout(cmd, GPU_COMMAND_TIMEOUT) {
                let stats = String::from_utf8_lossy(&output.stdout);

                for line in stats.lines() {
                    let line = line.trim();
                    if line.contains("GPU Utilization (%)") {
                        if let Some(val) = Self::extract_xpu_smi_value(line) {
                            gpu.usage_percent = val.parse().unwrap_or(0.0);
                        }
                    } else if line.contains("GPU Memory Utilization (%)")
                        || line.contains("Memory Used")
                    {
                        // Memory in MB
                        if let Some(val) = Self::extract_xpu_smi_value(line) {
                            gpu.memory_used = Self::parse_memory_string(&val);
                        }
                    } else if line.contains("GPU Temperature") {
                        if let Some(val) = Self::extract_xpu_smi_value(line) {
                            gpu.temperature = val.trim_end_matches(" C").parse().unwrap_or(0.0);
                        }
                    } else if line.contains("GPU Power") {
                        if let Some(val) = Self::extract_xpu_smi_value(line) {
                            gpu.power_watts =
                                val.split_whitespace()
                                    .next()
                                    .unwrap_or("0")
                                    .parse::<f64>()
                                    .unwrap_or(0.0) as u32;
                        }
                    } else if line.contains("Device Name") {
                        if let Some(val) = Self::extract_xpu_smi_value(line) {
                            gpu.name = val;
                        }
                    }
                }
            }

            // Get memory total from discovery if not set
            if gpu.memory_total == 0 {
                let mut cmd = Command::new("xpu-smi");
                cmd.args(["discovery", "-d", &device_id.to_string()]);
                if let Some(output) = exec_with_timeout(cmd, GPU_COMMAND_TIMEOUT) {
                    let info = String::from_utf8_lossy(&output.stdout);
                    for line in info.lines() {
                        if line.contains("Memory Physical Size") {
                            if let Some(val) = Self::extract_xpu_smi_value(line) {
                                gpu.memory_total = Self::parse_memory_string(&val);
                            }
                        }
                    }
                }
            }

            gpus.push(gpu);
        }

        if gpus.is_empty() { None } else { Some(gpus) }
    }

    /// Extract value from xpu-smi output line (format: "Label: Value" or "Label Value")
    #[cfg(target_os = "linux")]
    fn extract_xpu_smi_value(line: &str) -> Option<String> {
        line.split(':').nth(1).map(|val| val.trim().to_string())
    }

    /// Collect Intel GPU metrics using intel_gpu_top (for integrated GPUs)
    /// Note: Requires root privileges or CAP_PERFMON capability
    #[cfg(target_os = "linux")]
    fn collect_intel_gpu_top(&self) -> Option<Vec<GpuMetrics>> {
        // intel_gpu_top -J -s 500 outputs JSON with GPU usage
        // We run it briefly and capture one sample
        let mut cmd = Command::new("intel_gpu_top");
        cmd.args(["-J", "-s", "500", "-o", "-"]);

        // Use shorter timeout - intel_gpu_top streams continuously
        let output = exec_with_timeout(cmd, Duration::from_secs(2))?;

        // Even if the command is killed (expected), we may have partial output
        let stdout = String::from_utf8_lossy(&output.stdout);

        if stdout.is_empty() {
            return None;
        }

        let mut gpu = GpuMetrics {
            index: 0,
            vendor: "Intel".to_string(),
            name: "Intel Integrated Graphics".to_string(),
            ..Default::default()
        };

        // Parse JSON output - intel_gpu_top outputs one JSON object per line
        // Format: {"period":{"duration":500.123},"frequency":{"requested":0,"actual":1200},"engines":{"Render/3D/0":{"busy":45.2},...}}
        for line in stdout.lines() {
            if line.starts_with('{') {
                // Simple JSON field extraction
                // Get overall "busy" percentage from engines
                let mut total_busy = 0.0;
                let mut engine_count = 0;

                // Extract busy values from engines
                if let Some(engines_start) = line.find("\"engines\"") {
                    if let Some(engines_section) = line.get(engines_start..) {
                        // Find all "busy" values
                        let mut search_pos = 0;
                        while let Some(busy_pos) = engines_section[search_pos..].find("\"busy\":") {
                            let start = search_pos + busy_pos + 7;
                            if let Some(end_pos) = engines_section[start..].find([',', '}']) {
                                if let Some(val_str) = engines_section.get(start..start + end_pos) {
                                    if let Ok(val) = val_str.trim().parse::<f64>() {
                                        total_busy += val;
                                        engine_count += 1;
                                    }
                                }
                                search_pos = start + end_pos;
                            } else {
                                break;
                            }
                        }
                    }
                }

                // Use max engine busy as overall usage (or average if preferred)
                if engine_count > 0 {
                    gpu.usage_percent = total_busy / engine_count as f64;
                }

                // Extract frequency
                if let Some(freq_pos) = line.find("\"actual\":") {
                    let start = freq_pos + 9;
                    if let Some(end_pos) = line[start..].find([',', '}']) {
                        if let Some(val_str) = line.get(start..start + end_pos) {
                            gpu.clock_core_mhz = val_str.trim().parse().unwrap_or(0);
                        }
                    }
                }

                // Extract power if available
                if let Some(power_pos) = line.find("\"power\"") {
                    if let Some(gpu_power_pos) = line[power_pos..].find("\"GPU\":") {
                        let start = power_pos + gpu_power_pos + 6;
                        if let Some(end_pos) = line[start..].find([',', '}']) {
                            if let Some(val_str) = line.get(start..start + end_pos) {
                                gpu.power_watts =
                                    val_str.trim().parse::<f64>().unwrap_or(0.0) as u32;
                            }
                        }
                    }
                }

                break; // Only need first complete JSON line
            }
        }

        // Get GPU name from sysfs
        if let Some(name) = Self::get_intel_gpu_name_from_sysfs(0) {
            gpu.name = name;
        }

        Some(vec![gpu])
    }

    /// Get Intel GPU name from sysfs
    #[cfg(target_os = "linux")]
    fn get_intel_gpu_name_from_sysfs(card_index: u32) -> Option<String> {
        use std::fs;

        let card_path = format!("/sys/class/drm/card{}/device", card_index);
        let product_name_path = format!("{}/product_name", card_path);

        if let Ok(name) = fs::read_to_string(&product_name_path) {
            return Some(name.trim().to_string());
        }

        // Try to get device name from PCI info
        let device_path = format!("{}/device", card_path);
        if let Ok(device_id) = fs::read_to_string(&device_path) {
            return Some(format!("Intel GPU ({})", device_id.trim()));
        }

        None
    }

    /// Fallback: Collect basic Intel GPU info from sysfs (no usage metrics)
    #[cfg(target_os = "linux")]
    fn collect_intel_sysfs(&self) -> Option<Vec<GpuMetrics>> {
        use std::fs;
        use std::path::Path;

        let drm_path = Path::new("/sys/class/drm");
        if !drm_path.exists() {
            return None;
        }

        let mut gpus = Vec::new();
        let mut index = 0u32;

        let entries = fs::read_dir(drm_path).ok()?;
        for entry in entries.flatten() {
            let path = entry.path();
            let name = path.file_name()?.to_str()?;

            if name.starts_with("card") && !name.contains('-') {
                let device_path = path.join("device");
                let vendor_path = device_path.join("vendor");

                if let Ok(vendor) = fs::read_to_string(&vendor_path) {
                    if vendor.trim() == "0x8086" {
                        let mut gpu = GpuMetrics {
                            index,
                            vendor: "Intel".to_string(),
                            ..Default::default()
                        };

                        // Try to get product name
                        if let Ok(product) = fs::read_to_string(device_path.join("product_name")) {
                            gpu.name = product.trim().to_string();
                        } else if let Ok(device_id) = fs::read_to_string(device_path.join("device"))
                        {
                            gpu.name = format!("Intel GPU ({})", device_id.trim());
                        } else {
                            gpu.name = "Intel Integrated Graphics".to_string();
                        }

                        // Try to get current frequency from gt directory
                        let gt_path = path.join("gt");
                        if gt_path.exists() {
                            // Try gt0, gt1, etc.
                            'gt_loop: for gt_entry in fs::read_dir(&gt_path).ok()?.flatten() {
                                let gt_name = gt_entry.file_name();
                                if gt_name
                                    .to_str()
                                    .map(|s| s.starts_with("gt") && !s.contains('.'))
                                    .unwrap_or(false)
                                {
                                    // Try multiple frequency file names (different driver versions)
                                    let freq_files = [
                                        "rps_cur_freq_mhz", // Modern Intel drivers (Meteor Lake, etc.)
                                        "rps_act_freq_mhz", // Actual frequency
                                        "gt_cur_freq_mhz",  // Older drivers
                                    ];
                                    for freq_file in &freq_files {
                                        let freq_path = gt_entry.path().join(freq_file);
                                        if let Ok(freq) = fs::read_to_string(&freq_path) {
                                            gpu.clock_core_mhz = freq.trim().parse().unwrap_or(0);
                                            if gpu.clock_core_mhz > 0 {
                                                break 'gt_loop;
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Try to get memory info for discrete GPUs
                        let lmem_path = device_path.join("lmem_total_bytes");
                        if let Ok(mem) = fs::read_to_string(&lmem_path) {
                            gpu.memory_total = mem.trim().parse().unwrap_or(0);
                        }

                        gpus.push(gpu);
                        index += 1;
                    }
                }
            }
        }

        if gpus.is_empty() { None } else { Some(gpus) }
    }

    /// Collect AMD APU/integrated GPU metrics via sysfs
    /// This is a fallback for AMD APUs (like Radeon 780M) that don't have ROCm support
    #[cfg(target_os = "linux")]
    fn collect_amd_apu_sysfs(&self) -> Option<Vec<GpuMetrics>> {
        use std::fs;
        use std::path::Path;

        let drm_path = Path::new("/sys/class/drm");
        if !drm_path.exists() {
            return None;
        }

        let mut gpus = Vec::new();
        let mut index = 0u32;

        let entries = fs::read_dir(drm_path).ok()?;
        for entry in entries.flatten() {
            let path = entry.path();
            let name = path.file_name()?.to_str()?;

            // Look for card devices (card0, card1, etc.)
            if name.starts_with("card") && !name.contains('-') {
                let device_path = path.join("device");
                let vendor_path = device_path.join("vendor");

                // Check if it's an AMD device (vendor 0x1002)
                if let Ok(vendor) = fs::read_to_string(&vendor_path) {
                    if vendor.trim() == "0x1002" {
                        let mut gpu = GpuMetrics {
                            index,
                            vendor: "AMD".to_string(),
                            ..Default::default()
                        };

                        // Get GPU name from product_name or marketing_name
                        gpu.name = Self::get_amd_gpu_name(&device_path);

                        // Get current GPU frequency from pp_dpm_sclk
                        gpu.clock_core_mhz = Self::get_amd_sclk_frequency(&device_path);

                        // Get temperature from hwmon
                        gpu.temperature = Self::get_amd_temperature(&path);

                        // Get VRAM info (for discrete GPUs/APUs with dedicated memory)
                        let (vram_used, vram_total) = Self::get_amd_vram_info(&device_path);
                        gpu.memory_used = vram_used;
                        gpu.memory_total = vram_total;

                        // Get GPU busy percentage if available
                        gpu.usage_percent = Self::get_amd_gpu_busy(&device_path);

                        // Get power usage if available
                        gpu.power_watts = Self::get_amd_power(&path);

                        gpus.push(gpu);
                        index += 1;
                    }
                }
            }
        }

        if gpus.is_empty() { None } else { Some(gpus) }
    }

    /// Get AMD GPU name from sysfs
    #[cfg(target_os = "linux")]
    fn get_amd_gpu_name(device_path: &std::path::Path) -> String {
        use std::fs;

        // Try marketing_name first (more user-friendly)
        if let Ok(name) = fs::read_to_string(device_path.join("product_name")) {
            let name = name.trim();
            if !name.is_empty() {
                return name.to_string();
            }
        }

        // Try PCI subsystem info
        if let Ok(device_id) = fs::read_to_string(device_path.join("device")) {
            let device_id = device_id.trim();
            // Map common AMD APU device IDs to names
            return match device_id {
                "0x15bf" => "AMD Radeon 780M".to_string(),
                "0x15c8" => "AMD Radeon 760M".to_string(),
                "0x164c" => "AMD Radeon 680M".to_string(),
                "0x164d" => "AMD Radeon 660M".to_string(),
                "0x1681" => "AMD Radeon Vega 8 Graphics".to_string(),
                "0x1636" => "AMD Radeon Vega 7 Graphics".to_string(),
                _ => format!("AMD GPU ({})", device_id),
            };
        }

        "AMD Integrated Graphics".to_string()
    }

    /// Get current GPU SCLK frequency from pp_dpm_sclk
    #[cfg(target_os = "linux")]
    fn get_amd_sclk_frequency(device_path: &std::path::Path) -> u64 {
        use std::fs;

        let sclk_path = device_path.join("pp_dpm_sclk");
        if let Ok(content) = fs::read_to_string(&sclk_path) {
            // Format: "0: 500Mhz\n1: 800Mhz *\n2: 1800Mhz"
            // The active frequency has a '*' marker
            for line in content.lines() {
                if line.contains('*') {
                    // Extract frequency value
                    if let Some(freq_str) = line.split(':').nth(1) {
                        let freq_str = freq_str.trim().trim_end_matches('*').trim();
                        if let Some(mhz_pos) = freq_str.to_lowercase().find("mhz") {
                            if let Ok(freq) = freq_str[..mhz_pos].trim().parse::<u64>() {
                                return freq;
                            }
                        }
                    }
                }
            }
        }
        0
    }

    /// Get AMD GPU temperature from hwmon
    #[cfg(target_os = "linux")]
    fn get_amd_temperature(card_path: &std::path::Path) -> f64 {
        use std::fs;

        // First try hwmon in device path
        let device_path = card_path.join("device");
        let hwmon_path = device_path.join("hwmon");

        if hwmon_path.exists() {
            if let Ok(entries) = fs::read_dir(&hwmon_path) {
                for entry in entries.flatten() {
                    // Try edge temperature (temp1_input is typically edge temp for AMD)
                    let temp_path = entry.path().join("temp1_input");
                    if let Ok(temp_str) = fs::read_to_string(&temp_path) {
                        if let Ok(temp_mc) = temp_str.trim().parse::<i64>() {
                            return temp_mc as f64 / 1000.0;
                        }
                    }
                }
            }
        }

        // Fallback: scan all hwmon devices for amdgpu
        let hwmon_base = std::path::Path::new("/sys/class/hwmon");
        if let Ok(entries) = fs::read_dir(hwmon_base) {
            for entry in entries.flatten() {
                let path = entry.path();
                if let Ok(name) = fs::read_to_string(path.join("name")) {
                    if name.trim() == "amdgpu" {
                        if let Ok(temp_str) = fs::read_to_string(path.join("temp1_input")) {
                            if let Ok(temp_mc) = temp_str.trim().parse::<i64>() {
                                return temp_mc as f64 / 1000.0;
                            }
                        }
                    }
                }
            }
        }

        0.0
    }

    /// Get AMD VRAM info
    #[cfg(target_os = "linux")]
    fn get_amd_vram_info(device_path: &std::path::Path) -> (u64, u64) {
        use std::fs;

        let mut used = 0u64;
        let mut total = 0u64;

        // Try mem_info_vram_used and mem_info_vram_total
        if let Ok(used_str) = fs::read_to_string(device_path.join("mem_info_vram_used")) {
            used = used_str.trim().parse().unwrap_or(0);
        }
        if let Ok(total_str) = fs::read_to_string(device_path.join("mem_info_vram_total")) {
            total = total_str.trim().parse().unwrap_or(0);
        }

        // For APUs, VRAM might be reported as GTT (graphics translation table) memory
        if total == 0 {
            if let Ok(total_str) = fs::read_to_string(device_path.join("mem_info_gtt_total")) {
                total = total_str.trim().parse().unwrap_or(0);
            }
            if let Ok(used_str) = fs::read_to_string(device_path.join("mem_info_gtt_used")) {
                used = used_str.trim().parse().unwrap_or(0);
            }
        }

        (used, total)
    }

    /// Get AMD GPU busy percentage
    #[cfg(target_os = "linux")]
    fn get_amd_gpu_busy(device_path: &std::path::Path) -> f64 {
        use std::fs;

        // Try gpu_busy_percent
        let busy_path = device_path.join("gpu_busy_percent");
        if let Ok(busy_str) = fs::read_to_string(&busy_path) {
            if let Ok(busy) = busy_str.trim().parse::<f64>() {
                return busy;
            }
        }

        0.0
    }

    /// Get AMD GPU power usage from hwmon
    #[cfg(target_os = "linux")]
    fn get_amd_power(card_path: &std::path::Path) -> u32 {
        use std::fs;

        let device_path = card_path.join("device");
        let hwmon_path = device_path.join("hwmon");

        if hwmon_path.exists() {
            if let Ok(entries) = fs::read_dir(&hwmon_path) {
                for entry in entries.flatten() {
                    // power1_average is in microwatts
                    let power_path = entry.path().join("power1_average");
                    if let Ok(power_str) = fs::read_to_string(&power_path) {
                        if let Ok(power_uw) = power_str.trim().parse::<u64>() {
                            return (power_uw / 1_000_000) as u32; // Convert to watts
                        }
                    }
                }
            }
        }

        0
    }

    fn parse_mib_to_bytes(mib_str: &str) -> u64 {
        let mib: f64 = mib_str.parse().unwrap_or(0.0);
        (mib * 1024.0 * 1024.0) as u64
    }

    #[allow(dead_code)]
    fn parse_memory_string(mem_str: &str) -> u64 {
        let parts: Vec<&str> = mem_str.split_whitespace().collect();
        if parts.len() >= 2 {
            let value: f64 = parts[0].parse().unwrap_or(0.0);
            let unit = parts[1].to_uppercase();
            match unit.as_str() {
                "B" => value as u64,
                "KB" | "KIB" => (value * 1024.0) as u64,
                "MB" | "MIB" => (value * 1024.0 * 1024.0) as u64,
                "GB" | "GIB" => (value * 1024.0 * 1024.0 * 1024.0) as u64,
                _ => value as u64,
            }
        } else {
            mem_str.parse().unwrap_or(0)
        }
    }

    // ==================== Windows GPU Collection ====================

    /// Collect AMD/Intel GPUs on Windows using PowerShell and WMI
    /// nvidia_names: list of already detected NVIDIA GPU names to avoid duplicates
    #[cfg(target_os = "windows")]
    fn collect_windows_gpu(&self, nvidia_names: &[String]) -> Option<Vec<GpuMetrics>> {
        let mut gpus = Vec::new();

        // Step 1: Get GPU info via WMI (Get-CimInstance Win32_VideoController)
        let mut cmd = Command::new("powershell");
        cmd.args([
            "-NoProfile",
            "-Command",
            r#"Get-CimInstance Win32_VideoController | Select-Object Name, AdapterRAM, VideoProcessor | ConvertTo-Json -Compress"#,
        ]);

        if let Some(output) = exec_with_timeout(cmd, GPU_COMMAND_TIMEOUT) {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);

                // Parse JSON output - can be a single object or array
                let json_str = stdout.trim();
                if !json_str.is_empty() {
                    // Handle both single object and array
                    let entries: Vec<&str> = if json_str.starts_with('[') {
                        // Parse array manually
                        Self::extract_json_objects(json_str)
                    } else {
                        vec![json_str]
                    };

                    let mut index = 0u32;
                    for entry in entries {
                        if let Some(gpu) = Self::parse_windows_gpu_entry(entry, index, nvidia_names)
                        {
                            gpus.push(gpu);
                            index += 1;
                        }
                    }
                }
            }
        }

        // Step 2: Try to get GPU utilization via Performance Counters
        // This is slow (~500ms) so we only do it if we have GPUs
        if !gpus.is_empty() {
            if let Some(usage_map) = Self::get_windows_gpu_usage() {
                for gpu in &mut gpus {
                    // Try to find matching usage by GPU index
                    if let Some(usage) = usage_map.get(&(gpu.index as usize)) {
                        gpu.usage_percent = *usage;
                    }
                }
            }
        }

        if gpus.is_empty() { None } else { Some(gpus) }
    }

    /// Extract individual JSON objects from a JSON array string
    #[cfg(target_os = "windows")]
    fn extract_json_objects(json_str: &str) -> Vec<&str> {
        // Simple extraction - find each {} pair
        let mut objects = Vec::new();
        let mut depth = 0;
        let mut start = 0;

        for (i, c) in json_str.char_indices() {
            match c {
                '{' => {
                    if depth == 0 {
                        start = i;
                    }
                    depth += 1;
                }
                '}' => {
                    depth -= 1;
                    if depth == 0 {
                        if let Some(obj) = json_str.get(start..=i) {
                            objects.push(obj);
                        }
                    }
                }
                _ => {}
            }
        }
        objects
    }

    /// Parse a single Windows GPU entry from JSON
    #[cfg(target_os = "windows")]
    fn parse_windows_gpu_entry(
        json: &str,
        index: u32,
        nvidia_names: &[String],
    ) -> Option<GpuMetrics> {
        // Extract Name field
        let name = Self::extract_json_string_field(json, "Name")?;

        // Skip if this is an NVIDIA GPU (already detected via nvidia-smi)
        let name_lower = name.to_lowercase();
        if name_lower.contains("nvidia") {
            return None;
        }
        // Also check against the list of already detected NVIDIA names
        for nvidia_name in nvidia_names {
            if name.contains(nvidia_name) || nvidia_name.contains(&name) {
                return None;
            }
        }

        let mut gpu = GpuMetrics {
            index,
            name: name.clone(),
            ..Default::default()
        };

        // Determine vendor
        if name_lower.contains("amd") || name_lower.contains("radeon") {
            gpu.vendor = "AMD".to_string();
        } else if name_lower.contains("intel") {
            gpu.vendor = "Intel".to_string();
        } else {
            gpu.vendor = "Unknown".to_string();
        }

        // Extract AdapterRAM (in bytes)
        if let Some(ram_str) = Self::extract_json_number_field(json, "AdapterRAM") {
            gpu.memory_total = ram_str.parse().unwrap_or(0);
        }

        Some(gpu)
    }

    /// Extract a string field from JSON manually
    #[cfg(target_os = "windows")]
    fn extract_json_string_field(json: &str, field: &str) -> Option<String> {
        let pattern = format!("\"{field}\":");
        if let Some(start) = json.find(&pattern) {
            let after_key = &json[start + pattern.len()..];
            // Find the value - can be a string (with quotes) or null
            let trimmed = after_key.trim_start();
            if let Some(stripped) = trimmed.strip_prefix('"') {
                // String value
                if let Some(end) = stripped.find('"') {
                    return Some(stripped[..end].to_string());
                }
            }
        }
        None
    }

    /// Extract a number field from JSON manually
    #[cfg(target_os = "windows")]
    fn extract_json_number_field(json: &str, field: &str) -> Option<String> {
        let pattern = format!("\"{field}\":");
        if let Some(start) = json.find(&pattern) {
            let after_key = &json[start + pattern.len()..];
            let trimmed = after_key.trim_start();
            // Number value - read until comma, }, or whitespace
            let end_pos = trimmed
                .find(|c: char| c == ',' || c == '}' || c.is_whitespace())
                .unwrap_or(trimmed.len());
            let value = &trimmed[..end_pos];
            if value != "null" {
                return Some(value.to_string());
            }
        }
        None
    }

    /// Get GPU usage percentages via Windows Performance Counters
    #[cfg(target_os = "windows")]
    fn get_windows_gpu_usage() -> Option<std::collections::HashMap<usize, f64>> {
        use std::collections::HashMap;

        // Use Get-Counter to get GPU engine utilization
        // Note: This returns data per-engine, we need to aggregate
        let mut cmd = Command::new("powershell");
        cmd.args([
            "-NoProfile",
            "-Command",
            r#"
            try {
                $counters = Get-Counter '\GPU Engine(*engtype_3D)\Utilization Percentage' -ErrorAction SilentlyContinue
                if ($counters) {
                    $counters.CounterSamples | ForEach-Object {
                        "$($_.InstanceName)=$($_.CookedValue)"
                    }
                }
            } catch {}
            "#,
        ]);

        let output = exec_with_timeout(cmd, Duration::from_secs(3))?;
        if !output.status.success() {
            return None;
        }

        let mut usage_map: HashMap<usize, f64> = HashMap::new();
        let stdout = String::from_utf8_lossy(&output.stdout);

        for line in stdout.lines() {
            // Format: "luid_0x00010001_0x00000000_phys_0_eng_0_engtype_3D=15.5"
            if let Some((instance, value)) = line.split_once('=') {
                if let Ok(usage) = value.trim().parse::<f64>() {
                    // Extract GPU index from instance name (phys_X)
                    if let Some(phys_pos) = instance.find("phys_") {
                        let after_phys = &instance[phys_pos + 5..];
                        if let Some(end) = after_phys.find('_') {
                            if let Ok(gpu_index) = after_phys[..end].parse::<usize>() {
                                // Accumulate usage (we'll take max later)
                                let current = usage_map.entry(gpu_index).or_insert(0.0);
                                if usage > *current {
                                    *current = usage;
                                }
                            }
                        }
                    }
                }
            }
        }

        if usage_map.is_empty() {
            None
        } else {
            Some(usage_map)
        }
    }

    // ==================== macOS GPU Collection ====================

    /// Collect GPUs on macOS using system_profiler
    /// nvidia_names: list of already detected NVIDIA GPU names to avoid duplicates
    #[cfg(target_os = "macos")]
    fn collect_macos_gpu(&self, nvidia_names: &[String]) -> Option<Vec<GpuMetrics>> {
        let mut gpus = Vec::new();

        // Step 1: Get GPU info via system_profiler
        let mut cmd = Command::new("system_profiler");
        cmd.args(["SPDisplaysDataType", "-json"]);

        let output = exec_with_timeout(cmd, GPU_COMMAND_TIMEOUT)?;
        if !output.status.success() {
            return None;
        }

        let stdout = String::from_utf8_lossy(&output.stdout);

        // Parse the JSON output to extract GPU information
        // Format: {"SPDisplaysDataType":[{"sppci_model":"Intel UHD Graphics 630",...},...]}
        let mut index = 0u32;

        // Find all GPU entries by looking for sppci_model or chipset_model fields
        let gpu_models: Vec<String> = Self::extract_macos_gpu_models(&stdout);

        for model in gpu_models {
            // Skip if this is an NVIDIA GPU (already detected)
            if model.to_lowercase().contains("nvidia") {
                for nvidia_name in nvidia_names {
                    if model.contains(nvidia_name) || nvidia_name.contains(&model) {
                        continue;
                    }
                }
            }

            let mut gpu = GpuMetrics {
                index,
                name: model.clone(),
                ..Default::default()
            };

            // Determine vendor
            let model_lower = model.to_lowercase();
            if model_lower.contains("amd") || model_lower.contains("radeon") {
                gpu.vendor = "AMD".to_string();
            } else if model_lower.contains("intel") {
                gpu.vendor = "Intel".to_string();
            } else if model_lower.contains("apple")
                || model_lower.contains("m1")
                || model_lower.contains("m2")
                || model_lower.contains("m3")
                || model_lower.contains("m4")
            {
                gpu.vendor = "Apple".to_string();
            } else {
                gpu.vendor = "Unknown".to_string();
            }

            gpus.push(gpu);
            index += 1;
        }

        // Step 2: Try to get power/usage metrics via powermetrics (requires root)
        // This is optional and will silently fail if not running as root
        Self::update_macos_gpu_metrics(&mut gpus);

        if gpus.is_empty() { None } else { Some(gpus) }
    }

    /// Extract GPU model names from macOS system_profiler JSON output
    #[cfg(target_os = "macos")]
    fn extract_macos_gpu_models(json: &str) -> Vec<String> {
        let mut models = Vec::new();

        // Look for "sppci_model" or "chipset_model" fields
        for field in ["sppci_model", "chipset_model", "_name"] {
            let pattern = format!("\"{}\"", field);
            let mut search_pos = 0;

            while let Some(pos) = json[search_pos..].find(&pattern) {
                let abs_pos = search_pos + pos;
                // Find the value after the colon
                if let Some(colon_pos) = json[abs_pos..].find(':') {
                    let after_colon = &json[abs_pos + colon_pos + 1..];
                    let trimmed = after_colon.trim_start();
                    if let Some(stripped) = trimmed.strip_prefix('"') {
                        if let Some(end) = stripped.find('"') {
                            let value = &stripped[..end];
                            // Filter out non-GPU entries
                            if !value.is_empty()
                                && !value.contains("Display")
                                && !value.contains("Displays")
                                && !value.contains("Connection")
                            {
                                if !models.contains(&value.to_string()) {
                                    models.push(value.to_string());
                                }
                            }
                        }
                    }
                }
                search_pos = abs_pos + pattern.len();
            }
        }

        models
    }

    /// Update macOS GPU metrics with powermetrics data (requires root)
    #[cfg(target_os = "macos")]
    fn update_macos_gpu_metrics(gpus: &mut [GpuMetrics]) {
        if gpus.is_empty() {
            return;
        }

        // Try to get GPU power usage via powermetrics
        // This requires root privileges and may fail silently
        let mut cmd = Command::new("powermetrics");
        cmd.args(["--samplers", "gpu_power", "-n", "1", "-i", "500"]);

        if let Some(output) = exec_with_timeout(cmd, Duration::from_secs(2)) {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);

                // Parse powermetrics output for GPU power
                // Format varies but often includes "GPU Power: X.XX W"
                for line in stdout.lines() {
                    if line.contains("GPU Power") || line.contains("GPU Active") {
                        // Extract power value
                        if let Some(power_str) = line.split_whitespace().rev().nth(1) {
                            if let Ok(power) = power_str.parse::<f64>() {
                                if let Some(gpu) = gpus.first_mut() {
                                    gpu.power_watts = power as u32;
                                }
                            }
                        }
                    }
                    // Try to extract GPU busy percentage
                    if line.contains("GPU Active") || line.contains("GPU Busy") {
                        if let Some(pct_pos) = line.rfind('%') {
                            // Find the number before %
                            let before_pct = &line[..pct_pos];
                            if let Some(last_space) =
                                before_pct.rfind(|c: char| c.is_whitespace() || c == ':')
                            {
                                let value_str = before_pct[last_space + 1..].trim();
                                if let Ok(usage) = value_str.parse::<f64>() {
                                    if let Some(gpu) = gpus.first_mut() {
                                        gpu.usage_percent = usage;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

impl Default for GpuCollector {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_mib_to_bytes() {
        assert_eq!(GpuCollector::parse_mib_to_bytes("1024"), 1024 * 1024 * 1024);
        assert_eq!(GpuCollector::parse_mib_to_bytes("512"), 512 * 1024 * 1024);
    }

    #[test]
    fn test_parse_memory_string() {
        assert_eq!(
            GpuCollector::parse_memory_string("1024 MB"),
            1024 * 1024 * 1024
        );
        assert_eq!(
            GpuCollector::parse_memory_string("2 GB"),
            2 * 1024 * 1024 * 1024
        );
    }
}
