use std::process::Command;

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

pub struct GpuCollector {
    nvidia_available: bool,
    amd_available: bool,
    driver_version: String,
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

        Self {
            nvidia_available,
            amd_available,
            driver_version,
        }
    }

    fn check_nvidia_available() -> bool {
        #[cfg(target_os = "windows")]
        {
            Command::new("nvidia-smi")
                .arg("--query-gpu=name")
                .arg("--format=csv,noheader")
                .output()
                .map(|o| o.status.success())
                .unwrap_or(false)
        }
        #[cfg(not(target_os = "windows"))]
        {
            Command::new("nvidia-smi")
                .arg("--query-gpu=name")
                .arg("--format=csv,noheader")
                .output()
                .map(|o| o.status.success())
                .unwrap_or(false)
        }
    }

    fn check_amd_available() -> bool {
        #[cfg(target_os = "linux")]
        {
            Command::new("rocm-smi")
                .arg("--showproductname")
                .output()
                .map(|o| o.status.success())
                .unwrap_or(false)
        }
        #[cfg(not(target_os = "linux"))]
        {
            false
        }
    }

    fn get_nvidia_driver_version() -> Option<String> {
        let output = Command::new("nvidia-smi")
            .arg("--query-gpu=driver_version")
            .arg("--format=csv,noheader")
            .output()
            .ok()?;

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

        // Try to detect Intel integrated graphics
        if let Some(intel_gpus) = self.collect_intel() {
            gpus.extend(intel_gpus);
        }

        gpus
    }

    fn collect_nvidia(&self) -> Option<Vec<GpuMetrics>> {
        // Query all needed GPU info in one call for efficiency
        let output = Command::new("nvidia-smi")
            .args([
                "--query-gpu=index,name,utilization.gpu,memory.total,memory.used,temperature.gpu,fan.speed,power.draw,power.limit,clocks.current.graphics,clocks.current.memory,pcie.link.gen.current,pcie.link.width.current,utilization.encoder,utilization.decoder",
                "--format=csv,noheader,nounits"
            ])
            .output()
            .ok()?;

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
                    pcie_generation: format!("Gen{} x{}", pcie_gen, pcie_width),
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

            // Get GPU list
            let list_output = Command::new("rocm-smi")
                .arg("--showproductname")
                .output()
                .ok()?;

            if !list_output.status.success() {
                return None;
            }

            // Parse GPU names
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

            // Get detailed metrics for each GPU
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
        if let Ok(output) = Command::new("rocm-smi")
            .args(["-d", &index.to_string(), "--showuse"])
            .output()
        {
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
        if let Ok(output) = Command::new("rocm-smi")
            .args(["-d", &index.to_string(), "--showmeminfo", "vram"])
            .output()
        {
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
        if let Ok(output) = Command::new("rocm-smi")
            .args(["-d", &index.to_string(), "--showtemp"])
            .output()
        {
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
        if let Ok(output) = Command::new("rocm-smi")
            .args(["-d", &index.to_string(), "--showfan"])
            .output()
        {
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
        if let Ok(output) = Command::new("rocm-smi")
            .args(["-d", &index.to_string(), "--showpower"])
            .output()
        {
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
        if let Ok(output) = Command::new("rocm-smi")
            .args(["-d", &index.to_string(), "--showclocks"])
            .output()
        {
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
            // Check for Intel GPU via sysfs
            use std::fs;
            use std::path::Path;

            let drm_path = Path::new("/sys/class/drm");
            if !drm_path.exists() {
                return None;
            }

            let mut gpus = Vec::new();
            let mut index = 0u32;

            if let Ok(entries) = fs::read_dir(drm_path) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    let name = path.file_name()?.to_str()?;

                    if name.starts_with("card") && !name.contains('-') {
                        let device_path = path.join("device");
                        let vendor_path = device_path.join("vendor");

                        if let Ok(vendor) = fs::read_to_string(&vendor_path) {
                            // Intel vendor ID is 0x8086
                            if vendor.trim() == "0x8086" {
                                let mut gpu = GpuMetrics {
                                    index,
                                    vendor: "Intel".to_string(),
                                    ..Default::default()
                                };

                                // Try to get product name
                                if let Ok(product) =
                                    fs::read_to_string(device_path.join("product_name"))
                                {
                                    gpu.name = product.trim().to_string();
                                } else {
                                    gpu.name = "Intel Integrated Graphics".to_string();
                                }

                                // Try intel_gpu_top for usage (if available)
                                if let Ok(output) = Command::new("intel_gpu_top")
                                    .args(["-l", "-s", "100"])
                                    .output()
                                {
                                    if output.status.success() {
                                        let stdout = String::from_utf8_lossy(&output.stdout);
                                        for line in stdout.lines().skip(1).take(1) {
                                            let parts: Vec<&str> =
                                                line.split_whitespace().collect();
                                            if parts.len() > 1 {
                                                gpu.usage_percent = parts[1]
                                                    .trim_end_matches('%')
                                                    .parse()
                                                    .unwrap_or(0.0);
                                            }
                                        }
                                    }
                                }

                                gpus.push(gpu);
                                index += 1;
                            }
                        }
                    }
                }
            }

            if gpus.is_empty() {
                None
            } else {
                Some(gpus)
            }
        }
        #[cfg(target_os = "windows")]
        {
            // On Windows, try to detect Intel GPU via WMI
            // This is a simplified version - full implementation would use WMI bindings
            None
        }
        #[cfg(target_os = "macos")]
        {
            // macOS doesn't have traditional GPU monitoring for Intel integrated
            None
        }
    }

    fn parse_mib_to_bytes(mib_str: &str) -> u64 {
        let mib: f64 = mib_str.parse().unwrap_or(0.0);
        (mib * 1024.0 * 1024.0) as u64
    }

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
