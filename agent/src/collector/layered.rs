//! Layered metrics collector
//!
//! This module implements a layered approach to metrics collection:
//! - Static: Hardware info sent once on connection
//! - Realtime: CPU/memory/IO sent every second
//! - Periodic: Disk usage, user sessions sent less frequently

use std::sync::Arc;
use std::time::{Duration, Instant};
use sysinfo::{Disks, Networks, System};
use tokio::sync::mpsc;
use tokio::time;
use tracing::{debug, error, info};

use crate::config::Config;
use crate::proto::{
    CpuStaticInfo, DataRequestType, DiskIo, DiskStaticInfo, DiskUsage, GpuStaticInfo, GpuUsage,
    MemoryStaticInfo, MetricsType, NetworkAddressUpdate, NetworkIo, NetworkStaticInfo,
    NpuStaticInfo, NpuUsage, PeriodicData, RealtimeMetrics, StaticInfo,
};

use super::{
    CpuCollector, DiskCollector, GpuCollector, MemoryCollector, NetworkCollector, NpuCollector,
    SessionCollector, SystemInfoCollector,
};

/// Messages that can be sent from the layered collector
#[derive(Debug, Clone)]
pub enum LayeredMetricsMessage {
    /// Static hardware information (sent once on connect)
    Static(StaticInfo),
    /// Realtime metrics (sent every second)
    Realtime(RealtimeMetrics),
    /// Periodic data (sent at configured intervals)
    Periodic(PeriodicData),
    /// Full metrics (sent on request)
    Full(crate::proto::Metrics),
}

/// Request types for on-demand data collection
#[derive(Debug, Clone)]
pub enum DataRequest {
    /// Request static hardware info
    Static,
    /// Request disk usage
    DiskUsage,
    /// Request network info (IPs)
    NetworkInfo,
    /// Request user sessions
    UserSessions,
    /// Request GPU info
    GpuInfo,
    /// Request disk health status
    DiskHealth,
    /// Request full metrics
    Full,
}

impl From<DataRequestType> for DataRequest {
    fn from(t: DataRequestType) -> Self {
        match t {
            DataRequestType::DataRequestStatic => DataRequest::Static,
            DataRequestType::DataRequestDiskUsage => DataRequest::DiskUsage,
            DataRequestType::DataRequestNetworkInfo => DataRequest::NetworkInfo,
            DataRequestType::DataRequestUserSessions => DataRequest::UserSessions,
            DataRequestType::DataRequestGpuInfo => DataRequest::GpuInfo,
            DataRequestType::DataRequestHealth => DataRequest::DiskHealth,
            DataRequestType::DataRequestFull => DataRequest::Full,
        }
    }
}

/// Layered metrics collector
pub struct LayeredCollector {
    config: Arc<Config>,
    system: System,
    disks: Disks,
    networks: Networks,
    hostname: String,

    // Collectors
    cpu_collector: CpuCollector,
    memory_collector: MemoryCollector,
    disk_collector: DiskCollector,
    network_collector: NetworkCollector,
    gpu_collector: GpuCollector,
    npu_collector: NpuCollector,
    session_collector: SessionCollector,
    system_info_collector: SystemInfoCollector,

    // Cached static info
    cached_static_info: Option<StaticInfo>,

    // Last collection times
    last_periodic_disk: Instant,
    last_periodic_session: Instant,
    last_periodic_ip_check: Instant,
    #[allow(dead_code)]
    last_health_check: Instant,

    // Cached IP addresses for change detection
    cached_ip_addresses: Vec<(String, Vec<String>)>,
}

impl LayeredCollector {
    /// Create a new layered collector
    pub fn new(config: Arc<Config>) -> Self {
        let hostname = config.get_hostname();
        let mut system = System::new_all();
        system.refresh_all();

        let now = Instant::now();

        Self {
            config: config.clone(),
            system,
            disks: Disks::new_with_refreshed_list(),
            networks: Networks::new_with_refreshed_list(),
            hostname,
            cpu_collector: CpuCollector::new(),
            memory_collector: MemoryCollector::new(),
            disk_collector: DiskCollector::new(),
            network_collector: NetworkCollector::new(),
            gpu_collector: GpuCollector::new(),
            npu_collector: NpuCollector::new(),
            session_collector: SessionCollector::new(),
            system_info_collector: SystemInfoCollector::with_hostname(
                config.agent.hostname.clone(),
            ),
            cached_static_info: None,
            last_periodic_disk: now,
            last_periodic_session: now,
            last_periodic_ip_check: now,
            last_health_check: now,
            cached_ip_addresses: Vec::new(),
        }
    }

    /// Run the layered collector, sending messages through the provided channel
    pub async fn run(
        mut self,
        tx: mpsc::Sender<LayeredMetricsMessage>,
        mut request_rx: mpsc::Receiver<DataRequest>,
    ) {
        let realtime_interval = Duration::from_millis(self.config.collector.realtime_interval_ms);
        let mut ticker = time::interval(realtime_interval);

        info!(
            "Layered metrics collector started (realtime: {}ms, disk_usage: {}ms, sessions: {}ms)",
            self.config.collector.realtime_interval_ms,
            self.config.collector.disk_usage_interval_ms,
            self.config.collector.session_interval_ms
        );

        // Send initial static info and full metrics
        if self.config.collector.send_initial_full {
            if let Ok(static_info) = self.collect_static_info() {
                if tx
                    .send(LayeredMetricsMessage::Static(static_info))
                    .await
                    .is_err()
                {
                    error!("Failed to send initial static info");
                    return;
                }
            }

            // Also send initial full metrics
            if let Ok(full_metrics) = self.collect_full_metrics(true) {
                if tx
                    .send(LayeredMetricsMessage::Full(full_metrics))
                    .await
                    .is_err()
                {
                    error!("Failed to send initial full metrics");
                    return;
                }
            }
        }

        loop {
            tokio::select! {
                _ = ticker.tick() => {
                    // Collect and send realtime metrics
                    if let Ok(realtime) = self.collect_realtime_metrics() {
                        if tx.send(LayeredMetricsMessage::Realtime(realtime)).await.is_err() {
                            error!("Metrics channel closed");
                            break;
                        }
                    }

                    // Check if periodic data needs to be sent
                    if let Some(periodic) = self.check_and_collect_periodic() {
                        if tx.send(LayeredMetricsMessage::Periodic(periodic)).await.is_err() {
                            error!("Metrics channel closed");
                            break;
                        }
                    }
                }

                Some(request) = request_rx.recv() => {
                    // Handle on-demand data requests
                    self.handle_data_request(request, &tx).await;
                }
            }
        }
    }

    /// Collect static hardware information
    pub fn collect_static_info(&mut self) -> anyhow::Result<StaticInfo> {
        self.system.refresh_all();
        self.disks.refresh(false);
        self.networks.refresh(false);

        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_millis() as u64;

        // CPU static info
        let cpu_info = self
            .cpu_collector
            .collect(&self.system, &self.config.collector);
        let cpu_static = CpuStaticInfo {
            model: cpu_info.model,
            vendor: cpu_info.vendor,
            physical_cores: cpu_info.physical_cores,
            logical_cores: cpu_info.logical_cores,
            architecture: cpu_info.architecture,
            frequency_max_mhz: cpu_info.frequency_max_mhz,
            l1_cache_kb: 0, // TODO: implement cache detection
            l2_cache_kb: 0,
            l3_cache_kb: 0,
        };

        // Memory static info
        let mem_info = self.memory_collector.collect(&self.system);
        let memory_static = MemoryStaticInfo {
            total: mem_info.total,
            swap_total: mem_info.swap_total,
            memory_type: mem_info.memory_type,
            memory_speed_mhz: mem_info.memory_speed_mhz,
            memory_slots: 0, // TODO: implement slot detection
        };

        // Disk static info
        let disk_metrics = self
            .disk_collector
            .collect(&self.disks, &self.config.collector);
        let disks_static: Vec<DiskStaticInfo> = disk_metrics
            .into_iter()
            .map(|d| DiskStaticInfo {
                device: d.device,
                mount_point: d.mount_point,
                fs_type: d.fs_type,
                model: d.model,
                serial: d.serial,
                disk_type: d.disk_type,
                total_bytes: d.total,
                health_status: d.health_status,
            })
            .collect();

        // Network static info
        let net_metrics = self
            .network_collector
            .collect(&self.networks, &self.config.collector);
        let networks_static: Vec<NetworkStaticInfo> = net_metrics
            .into_iter()
            .map(|n| {
                // Cache IP addresses for change detection
                NetworkStaticInfo {
                    interface: n.interface.clone(),
                    mac_address: n.mac_address,
                    ip_addresses: n.ip_addresses,
                    speed_mbps: n.speed_mbps,
                    interface_type: n.interface_type,
                    is_virtual: n.interface.starts_with("docker")
                        || n.interface.starts_with("veth")
                        || n.interface.starts_with("br-"),
                }
            })
            .collect();

        // Update cached IP addresses
        self.cached_ip_addresses = networks_static
            .iter()
            .map(|n| (n.interface.clone(), n.ip_addresses.clone()))
            .collect();

        // GPU static info
        let gpu_metrics = self.gpu_collector.collect();
        let gpus_static: Vec<GpuStaticInfo> = gpu_metrics
            .into_iter()
            .map(|g| GpuStaticInfo {
                index: g.index,
                name: g.name,
                vendor: g.vendor,
                memory_total: g.memory_total,
                driver_version: g.driver_version,
                pcie_generation: g.pcie_generation,
                power_limit_watts: g.power_limit_watts,
            })
            .collect();

        // NPU static info
        let npu_metrics = self.npu_collector.collect();
        let npus_static: Vec<NpuStaticInfo> = npu_metrics
            .into_iter()
            .map(|n| NpuStaticInfo {
                index: n.index,
                name: n.name,
                vendor: n.vendor,
                memory_total: n.memory_total,
                driver_version: n.driver_version,
            })
            .collect();

        // System info
        let system_info = self.system_info_collector.collect();

        let static_info = StaticInfo {
            timestamp,
            cpu: Some(cpu_static),
            memory: Some(memory_static),
            disks: disks_static,
            networks: networks_static,
            gpus: gpus_static,
            npus: npus_static,
            system_info: Some(system_info),
        };

        // Cache the static info
        self.cached_static_info = Some(static_info.clone());

        Ok(static_info)
    }

    /// Collect realtime metrics (lightweight, for frequent sending)
    pub fn collect_realtime_metrics(&mut self) -> anyhow::Result<RealtimeMetrics> {
        self.system.refresh_cpu_all();
        self.system.refresh_memory();
        self.disks.refresh(false);
        self.networks.refresh(false);

        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_millis() as u64;

        // CPU realtime
        let cpu = self
            .cpu_collector
            .collect(&self.system, &self.config.collector);

        // Memory realtime
        let mem = self.memory_collector.collect(&self.system);

        // Disk IO (not usage)
        let disk_metrics = self
            .disk_collector
            .collect(&self.disks, &self.config.collector);
        let disk_io: Vec<DiskIo> = disk_metrics
            .into_iter()
            .map(|d| DiskIo {
                device: d.device,
                read_bytes_sec: d.read_bytes_sec,
                write_bytes_sec: d.write_bytes_sec,
                read_iops: d.read_iops,
                write_iops: d.write_iops,
            })
            .collect();

        // Network IO (not addresses)
        let net_metrics = self
            .network_collector
            .collect(&self.networks, &self.config.collector);
        let network_io: Vec<NetworkIo> = net_metrics
            .into_iter()
            .map(|n| NetworkIo {
                interface: n.interface,
                rx_bytes_sec: n.rx_bytes_sec,
                tx_bytes_sec: n.tx_bytes_sec,
                rx_packets_sec: n.rx_packets_sec,
                tx_packets_sec: n.tx_packets_sec,
                is_up: n.is_up,
            })
            .collect();

        // GPU usage (not static info)
        let gpu_metrics = self.gpu_collector.collect();
        let gpu_usage: Vec<GpuUsage> = gpu_metrics
            .into_iter()
            .map(|g| GpuUsage {
                index: g.index,
                usage_percent: g.usage_percent,
                memory_used: g.memory_used,
                temperature: g.temperature,
                power_watts: g.power_watts,
                clock_core_mhz: g.clock_core_mhz,
                encoder_usage: g.encoder_usage,
                decoder_usage: g.decoder_usage,
            })
            .collect();

        // NPU usage
        let npu_metrics = self.npu_collector.collect();
        let npu_usage: Vec<NpuUsage> = npu_metrics
            .into_iter()
            .map(|n| NpuUsage {
                index: n.index,
                usage_percent: n.usage_percent,
                memory_used: n.memory_used,
                temperature: n.temperature,
                power_watts: n.power_watts,
            })
            .collect();

        // Load average
        let load_average = self.get_load_average();

        Ok(RealtimeMetrics {
            timestamp,
            cpu_usage_percent: cpu.usage_percent,
            cpu_per_core: cpu.per_core_usage,
            cpu_temperature: cpu.temperature,
            cpu_frequency_mhz: cpu.frequency_mhz,
            memory_used: mem.used,
            memory_cached: mem.cached,
            swap_used: mem.swap_used,
            disk_io,
            network_io,
            load_average,
            gpu_usage,
            npu_usage,
        })
    }

    /// Check if periodic data needs to be collected and return it
    fn check_and_collect_periodic(&mut self) -> Option<PeriodicData> {
        let now = Instant::now();
        let mut has_data = false;
        let mut periodic = PeriodicData {
            timestamp: 0,
            disk_usage: Vec::new(),
            user_sessions: Vec::new(),
            network_updates: Vec::new(),
        };

        // Check disk usage interval
        let disk_interval = Duration::from_millis(self.config.collector.disk_usage_interval_ms);
        if now.duration_since(self.last_periodic_disk) >= disk_interval {
            self.last_periodic_disk = now;
            self.disks.refresh(false);

            let disk_metrics = self
                .disk_collector
                .collect(&self.disks, &self.config.collector);
            periodic.disk_usage = disk_metrics
                .into_iter()
                .map(|d| DiskUsage {
                    device: d.device,
                    mount_point: d.mount_point,
                    total: d.total,
                    used: d.used,
                    available: d.available,
                    temperature: d.temperature,
                })
                .collect();
            has_data = true;
            debug!(
                "Collected periodic disk usage: {} disks",
                periodic.disk_usage.len()
            );
        }

        // Check session interval
        let session_interval = Duration::from_millis(self.config.collector.session_interval_ms);
        if now.duration_since(self.last_periodic_session) >= session_interval {
            self.last_periodic_session = now;

            let sessions = self.session_collector.collect();
            periodic.user_sessions = sessions
                .into_iter()
                .map(|s| crate::proto::UserSession {
                    username: s.username,
                    tty: s.tty,
                    login_time: s.login_time,
                    remote_host: s.remote_host,
                    idle_seconds: s.idle_seconds,
                    session_type: s.session_type,
                })
                .collect();
            has_data = true;
            debug!(
                "Collected periodic user sessions: {} sessions",
                periodic.user_sessions.len()
            );
        }

        // Check IP address changes
        let ip_interval = Duration::from_millis(self.config.collector.ip_check_interval_ms);
        if now.duration_since(self.last_periodic_ip_check) >= ip_interval {
            self.last_periodic_ip_check = now;
            self.networks.refresh(false);

            let net_metrics = self
                .network_collector
                .collect(&self.networks, &self.config.collector);

            // Check for IP changes
            for net in &net_metrics {
                let cached = self
                    .cached_ip_addresses
                    .iter()
                    .find(|(iface, _)| iface == &net.interface);

                let ip_changed = match cached {
                    Some((_, cached_ips)) => cached_ips != &net.ip_addresses,
                    None => true, // New interface
                };

                if ip_changed {
                    periodic.network_updates.push(NetworkAddressUpdate {
                        interface: net.interface.clone(),
                        ip_addresses: net.ip_addresses.clone(),
                        is_up: net.is_up,
                    });
                }
            }

            // Update cache
            if !periodic.network_updates.is_empty() {
                self.cached_ip_addresses = net_metrics
                    .iter()
                    .map(|n| (n.interface.clone(), n.ip_addresses.clone()))
                    .collect();
                has_data = true;
                debug!(
                    "Detected IP changes on {} interfaces",
                    periodic.network_updates.len()
                );
            }
        }

        if has_data {
            periodic.timestamp = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_millis() as u64)
                .unwrap_or(0);
            Some(periodic)
        } else {
            None
        }
    }

    /// Collect full metrics (all data)
    pub fn collect_full_metrics(
        &mut self,
        is_initial: bool,
    ) -> anyhow::Result<crate::proto::Metrics> {
        self.system.refresh_all();
        self.disks.refresh(false);
        self.networks.refresh(false);

        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_millis() as u64;

        // Collect all metrics
        let cpu = self
            .cpu_collector
            .collect(&self.system, &self.config.collector);
        let memory = self.memory_collector.collect(&self.system);
        let disks = self
            .disk_collector
            .collect(&self.disks, &self.config.collector);
        let networks = self
            .network_collector
            .collect(&self.networks, &self.config.collector);
        let gpu_metrics = self.gpu_collector.collect();
        let npu_metrics = self.npu_collector.collect();
        let sessions = self.session_collector.collect();
        let system_info = self.system_info_collector.collect();
        let load_average = self.get_load_average();

        let gpus: Vec<_> = gpu_metrics
            .into_iter()
            .map(|g| crate::proto::GpuMetrics {
                index: g.index,
                name: g.name,
                vendor: g.vendor,
                usage_percent: g.usage_percent,
                memory_total: g.memory_total,
                memory_used: g.memory_used,
                temperature: g.temperature,
                fan_speed_percent: g.fan_speed_percent,
                power_watts: g.power_watts,
                power_limit_watts: g.power_limit_watts,
                clock_core_mhz: g.clock_core_mhz,
                clock_memory_mhz: g.clock_memory_mhz,
                driver_version: g.driver_version,
                pcie_generation: g.pcie_generation,
                encoder_usage: g.encoder_usage,
                decoder_usage: g.decoder_usage,
            })
            .collect();

        let npus: Vec<_> = npu_metrics
            .into_iter()
            .map(|n| crate::proto::NpuMetrics {
                index: n.index,
                name: n.name,
                vendor: n.vendor,
                usage_percent: n.usage_percent,
                memory_total: n.memory_total,
                memory_used: n.memory_used,
                temperature: n.temperature,
                power_watts: n.power_watts,
                driver_version: n.driver_version,
            })
            .collect();

        let user_sessions: Vec<_> = sessions
            .into_iter()
            .map(|s| crate::proto::UserSession {
                username: s.username,
                tty: s.tty,
                login_time: s.login_time,
                remote_host: s.remote_host,
                idle_seconds: s.idle_seconds,
                session_type: s.session_type,
            })
            .collect();

        Ok(crate::proto::Metrics {
            timestamp,
            cpu: Some(cpu),
            memory: Some(memory),
            disks,
            networks,
            load_average,
            hostname: self.hostname.clone(),
            gpus,
            system_info: Some(system_info),
            user_sessions,
            npus,
            metrics_type: MetricsType::MetricsFull as i32,
            is_initial,
        })
    }

    /// Handle a data request from the server
    async fn handle_data_request(
        &mut self,
        request: DataRequest,
        tx: &mpsc::Sender<LayeredMetricsMessage>,
    ) {
        match request {
            DataRequest::Static => {
                if let Ok(static_info) = self.collect_static_info() {
                    let _ = tx.send(LayeredMetricsMessage::Static(static_info)).await;
                }
            }
            DataRequest::DiskUsage => {
                self.disks.refresh(false);
                let disk_metrics = self
                    .disk_collector
                    .collect(&self.disks, &self.config.collector);
                let disk_usage: Vec<DiskUsage> = disk_metrics
                    .into_iter()
                    .map(|d| DiskUsage {
                        device: d.device,
                        mount_point: d.mount_point,
                        total: d.total,
                        used: d.used,
                        available: d.available,
                        temperature: d.temperature,
                    })
                    .collect();

                let periodic = PeriodicData {
                    timestamp: std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .map(|d| d.as_millis() as u64)
                        .unwrap_or(0),
                    disk_usage,
                    user_sessions: Vec::new(),
                    network_updates: Vec::new(),
                };
                let _ = tx.send(LayeredMetricsMessage::Periodic(periodic)).await;
            }
            DataRequest::NetworkInfo => {
                if let Ok(static_info) = self.collect_static_info() {
                    let _ = tx.send(LayeredMetricsMessage::Static(static_info)).await;
                }
            }
            DataRequest::UserSessions => {
                let sessions = self.session_collector.collect();
                let user_sessions: Vec<_> = sessions
                    .into_iter()
                    .map(|s| crate::proto::UserSession {
                        username: s.username,
                        tty: s.tty,
                        login_time: s.login_time,
                        remote_host: s.remote_host,
                        idle_seconds: s.idle_seconds,
                        session_type: s.session_type,
                    })
                    .collect();

                let periodic = PeriodicData {
                    timestamp: std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .map(|d| d.as_millis() as u64)
                        .unwrap_or(0),
                    disk_usage: Vec::new(),
                    user_sessions,
                    network_updates: Vec::new(),
                };
                let _ = tx.send(LayeredMetricsMessage::Periodic(periodic)).await;
            }
            DataRequest::GpuInfo | DataRequest::DiskHealth => {
                // These return static info
                if let Ok(static_info) = self.collect_static_info() {
                    let _ = tx.send(LayeredMetricsMessage::Static(static_info)).await;
                }
            }
            DataRequest::Full => {
                if let Ok(full_metrics) = self.collect_full_metrics(false) {
                    let _ = tx.send(LayeredMetricsMessage::Full(full_metrics)).await;
                }
            }
        }
    }

    /// Get system load average (Unix only)
    #[cfg(unix)]
    fn get_load_average(&self) -> Vec<f64> {
        let load = System::load_average();
        vec![load.one, load.five, load.fifteen]
    }

    #[cfg(windows)]
    fn get_load_average(&self) -> Vec<f64> {
        vec![]
    }
}
