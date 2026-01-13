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

        if self.nvidia_available {
            if let Some(nvidia_gpus) = self.collect_nvidia() {
                gpus.extend(nvidia_gpus);
            }
        }

        if self.amd_available {
            if let Some(amd_gpus) = self.collect_amd() {
                gpus.extend(amd_gpus);
            }
        }

        if let Some(intel_gpus) = self.collect_intel() {
            gpus.extend(intel_gpus);
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

    fn collect_amd(&self) -> Option<Vec<GpuMetrics>> {
        #[cfg(target_os = "linux")]
        {
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
        #[cfg(not(target_os = "linux"))]
        {
            None
        }
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

    fn collect_intel(&self) -> Option<Vec<GpuMetrics>> {
        #[cfg(target_os = "linux")]
        {
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
        #[cfg(not(target_os = "linux"))]
        {
            None
        }
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
        if let Some(val) = line.split(':').nth(1) {
            Some(val.trim().to_string())
        } else {
            None
        }
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
                            if let Some(end_pos) =
                                engines_section[start..].find(|c: char| c == ',' || c == '}')
                            {
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
                    if let Some(end_pos) = line[start..].find(|c: char| c == ',' || c == '}') {
                        if let Some(val_str) = line.get(start..start + end_pos) {
                            gpu.clock_core_mhz = val_str.trim().parse().unwrap_or(0);
                        }
                    }
                }

                // Extract power if available
                if let Some(power_pos) = line.find("\"power\"") {
                    if let Some(gpu_power_pos) = line[power_pos..].find("\"GPU\":") {
                        let start = power_pos + gpu_power_pos + 6;
                        if let Some(end_pos) = line[start..].find(|c: char| c == ',' || c == '}') {
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
                            for gt_entry in fs::read_dir(&gt_path).ok()?.flatten() {
                                let gt_name = gt_entry.file_name();
                                if gt_name
                                    .to_str()
                                    .map(|s| s.starts_with("gt"))
                                    .unwrap_or(false)
                                {
                                    let freq_path = gt_entry.path().join("gt_cur_freq_mhz");
                                    if let Ok(freq) = fs::read_to_string(&freq_path) {
                                        gpu.clock_core_mhz = freq.trim().parse().unwrap_or(0);
                                        break;
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
