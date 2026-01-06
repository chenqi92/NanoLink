use std::collections::HashMap;
use sysinfo::Networks;

use crate::config::CollectorConfig;
use crate::proto::NetworkMetrics;
#[allow(unused_imports)]
use crate::utils::safe_command::{DEFAULT_COMMAND_TIMEOUT, exec_with_timeout};
use std::process::Command;
use std::time::Duration;

/// Network metrics collector
pub struct NetworkCollector {
    /// Previous network stats for rate calculation
    prev_stats: HashMap<String, (u64, u64, u64, u64)>, // (rx_bytes, tx_bytes, rx_packets, tx_packets)
    prev_time: Option<std::time::Instant>,
}

impl NetworkCollector {
    pub fn new() -> Self {
        Self {
            prev_stats: HashMap::new(),
            prev_time: None,
        }
    }

    /// Check if interface should skip command execution (virtual/problematic interfaces)
    fn should_skip_command(interface: &str) -> bool {
        let name_lower = interface.to_lowercase();
        name_lower.starts_with("veth")
            || name_lower.starts_with("br-")
            || name_lower.starts_with("docker")
            || name_lower.starts_with("virbr")
    }

    /// Get MAC address for an interface
    #[cfg(target_os = "linux")]
    fn get_mac_address(interface: &str) -> String {
        use std::fs;
        // Use sysfs - this is fast and doesn't spawn subprocesses
        let path = format!("/sys/class/net/{}/address", interface);
        fs::read_to_string(path)
            .map(|s| s.trim().to_uppercase())
            .unwrap_or_default()
    }

    #[cfg(target_os = "macos")]
    fn get_mac_address(interface: &str) -> String {
        if Self::should_skip_command(interface) {
            return String::new();
        }

        let mut cmd = Command::new("ifconfig");
        cmd.arg(interface);

        if let Some(output) = exec_with_timeout(cmd, DEFAULT_COMMAND_TIMEOUT) {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines() {
                if line.contains("ether ") {
                    if let Some(mac) = line.split_whitespace().nth(1) {
                        return mac.to_uppercase();
                    }
                }
            }
        }
        String::new()
    }

    #[cfg(target_os = "windows")]
    fn get_mac_address(interface: &str) -> String {
        // Cache this call - it's slow but returns all interfaces at once
        static MAC_CACHE: std::sync::OnceLock<HashMap<String, String>> = std::sync::OnceLock::new();

        let cache = MAC_CACHE.get_or_init(|| {
            let mut map = HashMap::new();
            let mut cmd = Command::new("getmac");
            cmd.args(["/v", "/fo", "csv"]);

            if let Some(output) = exec_with_timeout(cmd, Duration::from_secs(10)) {
                let stdout = String::from_utf8_lossy(&output.stdout);
                for line in stdout.lines().skip(1) {
                    let parts: Vec<&str> = line.split(',').collect();
                    if parts.len() >= 3 {
                        let name = parts[0].trim_matches('"').to_string();
                        let mac = parts[2].trim_matches('"').to_uppercase();
                        map.insert(name, mac);
                    }
                }
            }
            map
        });

        // Find matching interface
        for (name, mac) in cache.iter() {
            if name.contains(interface) || interface.contains(name) {
                return mac.clone();
            }
        }
        String::new()
    }

    /// Get IP addresses for an interface
    #[cfg(target_os = "linux")]
    fn get_ip_addresses(interface: &str) -> Vec<String> {
        // Skip problematic virtual interfaces
        if Self::should_skip_command(interface) {
            return Vec::new();
        }

        let mut cmd = Command::new("ip");
        cmd.args(["addr", "show", interface]);

        let mut ips = Vec::new();
        if let Some(output) = exec_with_timeout(cmd, Duration::from_secs(2)) {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines() {
                let line = line.trim();
                if line.starts_with("inet ") || line.starts_with("inet6 ") {
                    if let Some(addr) = line.split_whitespace().nth(1) {
                        let ip = addr.split('/').next().unwrap_or(addr);
                        ips.push(ip.to_string());
                    }
                }
            }
        }
        ips
    }

    #[cfg(target_os = "macos")]
    fn get_ip_addresses(interface: &str) -> Vec<String> {
        if Self::should_skip_command(interface) {
            return Vec::new();
        }

        let mut cmd = Command::new("ifconfig");
        cmd.arg(interface);

        let mut ips = Vec::new();
        if let Some(output) = exec_with_timeout(cmd, DEFAULT_COMMAND_TIMEOUT) {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines() {
                let line = line.trim();
                if line.starts_with("inet ") {
                    if let Some(addr) = line.split_whitespace().nth(1) {
                        ips.push(addr.to_string());
                    }
                } else if line.starts_with("inet6 ") {
                    if let Some(addr) = line.split_whitespace().nth(1) {
                        let ip = addr.split('%').next().unwrap_or(addr);
                        ips.push(ip.to_string());
                    }
                }
            }
        }
        ips
    }

    #[cfg(target_os = "windows")]
    fn get_ip_addresses(interface: &str) -> Vec<String> {
        if Self::should_skip_command(interface) {
            return Vec::new();
        }

        let mut cmd = Command::new("powershell");
        cmd.args([
            "-Command",
            &format!(
                "Get-NetIPAddress -InterfaceAlias '*{interface}*' | Select-Object -ExpandProperty IPAddress"
            ),
        ]);

        let mut ips = Vec::new();
        if let Some(output) = exec_with_timeout(cmd, Duration::from_secs(5)) {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines() {
                let ip = line.trim();
                if !ip.is_empty() {
                    ips.push(ip.to_string());
                }
            }
        }
        ips
    }

    /// Get link speed in Mbps
    #[cfg(target_os = "linux")]
    fn get_link_speed(interface: &str) -> u64 {
        use std::fs;
        // Use sysfs - fast, no subprocess
        let speed_path = format!("/sys/class/net/{}/speed", interface);
        fs::read_to_string(speed_path)
            .ok()
            .and_then(|s| s.trim().parse().ok())
            .unwrap_or(0)
    }

    #[cfg(target_os = "macos")]
    fn get_link_speed(interface: &str) -> u64 {
        if Self::should_skip_command(interface) {
            return 0;
        }

        let mut cmd = Command::new("networksetup");
        cmd.args(["-getMedia", interface]);

        if let Some(output) = exec_with_timeout(cmd, DEFAULT_COMMAND_TIMEOUT) {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines() {
                if line.contains("Speed:") {
                    if let Some(speed_part) = line.split(':').nth(1) {
                        let speed_str: String =
                            speed_part.chars().take_while(|c| c.is_numeric()).collect();
                        if let Ok(speed) = speed_str.parse() {
                            return speed;
                        }
                    }
                }
            }
        }
        0
    }

    #[cfg(target_os = "windows")]
    fn get_link_speed(interface: &str) -> u64 {
        if Self::should_skip_command(interface) {
            return 0;
        }

        let mut cmd = Command::new("powershell");
        cmd.args([
            "-Command",
            &format!("(Get-NetAdapter -Name '*{interface}*').LinkSpeed"),
        ]);

        if let Some(output) = exec_with_timeout(cmd, Duration::from_secs(5)) {
            let stdout = String::from_utf8_lossy(&output.stdout);
            let speed_str = stdout.trim();
            if speed_str.contains("Gbps") {
                let num: u64 = speed_str
                    .split_whitespace()
                    .next()
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(0);
                return num * 1000;
            } else if speed_str.contains("Mbps") {
                return speed_str
                    .split_whitespace()
                    .next()
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(0);
            }
        }
        0
    }

    /// Determine interface type
    fn get_interface_type(interface: &str) -> String {
        let name_lower = interface.to_lowercase();

        if name_lower == "lo" || name_lower == "loopback" || name_lower.contains("loopback") {
            return "loopback".to_string();
        }

        if name_lower.starts_with("eth")
            || name_lower.starts_with("en")
            || name_lower.starts_with("eno")
            || name_lower.starts_with("enp")
            || name_lower.contains("ethernet")
        {
            return "ethernet".to_string();
        }

        if name_lower.starts_with("wl")
            || name_lower.starts_with("wlan")
            || name_lower.contains("wi-fi")
            || name_lower.contains("wireless")
        {
            return "wifi".to_string();
        }

        if name_lower.starts_with("veth")
            || name_lower.starts_with("docker")
            || name_lower.starts_with("br-")
            || name_lower.starts_with("virbr")
            || name_lower.starts_with("vmnet")
            || name_lower.starts_with("vbox")
        {
            return "virtual".to_string();
        }

        if name_lower.starts_with("tun") || name_lower.starts_with("tap") {
            return "tunnel".to_string();
        }

        if name_lower.starts_with("bond") {
            return "bond".to_string();
        }

        "unknown".to_string()
    }

    /// Check if interface is up
    #[cfg(target_os = "linux")]
    fn is_interface_up(interface: &str) -> bool {
        use std::fs;
        // Use sysfs - fast, no subprocess
        let operstate_path = format!("/sys/class/net/{}/operstate", interface);
        fs::read_to_string(operstate_path)
            .map(|s| s.trim() == "up")
            .unwrap_or(true)
    }

    #[cfg(not(target_os = "linux"))]
    fn is_interface_up(_interface: &str) -> bool {
        true
    }

    /// Collect network metrics
    pub fn collect(
        &mut self,
        networks: &Networks,
        _config: &CollectorConfig,
    ) -> Vec<NetworkMetrics> {
        let now = std::time::Instant::now();
        let elapsed = self
            .prev_time
            .map(|t| now.duration_since(t).as_secs_f64())
            .unwrap_or(1.0);

        let mut metrics = Vec::new();

        for (interface_name, data) in networks.list() {
            let interface_type = Self::get_interface_type(interface_name);

            let rx_bytes = data.received();
            let tx_bytes = data.transmitted();
            let rx_packets = data.packets_received();
            let tx_packets = data.packets_transmitted();

            // Calculate rates
            let (rx_bytes_sec, tx_bytes_sec, rx_packets_sec, tx_packets_sec) =
                if let Some((prev_rx, prev_tx, prev_rx_p, prev_tx_p)) =
                    self.prev_stats.get(interface_name)
                {
                    let rx_rate = ((rx_bytes.saturating_sub(*prev_rx)) as f64 / elapsed) as u64;
                    let tx_rate = ((tx_bytes.saturating_sub(*prev_tx)) as f64 / elapsed) as u64;
                    let rx_p_rate =
                        ((rx_packets.saturating_sub(*prev_rx_p)) as f64 / elapsed) as u64;
                    let tx_p_rate =
                        ((tx_packets.saturating_sub(*prev_tx_p)) as f64 / elapsed) as u64;
                    (rx_rate, tx_rate, rx_p_rate, tx_p_rate)
                } else {
                    (0, 0, 0, 0)
                };

            self.prev_stats.insert(
                interface_name.clone(),
                (rx_bytes, tx_bytes, rx_packets, tx_packets),
            );

            let is_up = Self::is_interface_up(interface_name);
            let mac_address = Self::get_mac_address(interface_name);
            let ip_addresses = Self::get_ip_addresses(interface_name);
            let speed_mbps = Self::get_link_speed(interface_name);

            metrics.push(NetworkMetrics {
                interface: interface_name.clone(),
                rx_bytes_sec,
                tx_bytes_sec,
                rx_packets_sec,
                tx_packets_sec,
                is_up,
                mac_address,
                ip_addresses,
                speed_mbps,
                interface_type,
            });
        }

        self.prev_time = Some(now);

        metrics
    }
}

impl Default for NetworkCollector {
    fn default() -> Self {
        Self::new()
    }
}
