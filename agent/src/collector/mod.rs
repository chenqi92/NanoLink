mod cpu;
mod disk;
mod gpu;
mod memory;
mod network;
mod system;

use std::sync::Arc;
use std::time::Duration;
use sysinfo::{Disks, Networks, System};
use tokio::time;
use tracing::{debug, error, info};

use crate::buffer::RingBuffer;
use crate::config::Config;
use crate::proto::Metrics;

pub use cpu::CpuCollector;
pub use disk::DiskCollector;
pub use gpu::GpuCollector;
pub use memory::MemoryCollector;
pub use network::NetworkCollector;
pub use system::SystemInfoCollector;

/// System metrics collector
///
/// Collects CPU, memory, disk, network, GPU metrics at configurable intervals.
pub struct MetricsCollector {
    config: Arc<Config>,
    buffer: Arc<RingBuffer>,
    system: System,
    disks: Disks,
    networks: Networks,
    hostname: String,
    cpu_collector: CpuCollector,
    memory_collector: MemoryCollector,
    disk_collector: DiskCollector,
    network_collector: NetworkCollector,
    gpu_collector: GpuCollector,
    system_info_collector: SystemInfoCollector,
}

impl MetricsCollector {
    /// Create a new metrics collector
    pub fn new(config: Arc<Config>, buffer: Arc<RingBuffer>) -> Self {
        let hostname = config.get_hostname();
        let mut system = System::new_all();
        system.refresh_all();

        Self {
            config,
            buffer,
            system,
            disks: Disks::new_with_refreshed_list(),
            networks: Networks::new_with_refreshed_list(),
            hostname,
            cpu_collector: CpuCollector::new(),
            memory_collector: MemoryCollector::new(),
            disk_collector: DiskCollector::new(),
            network_collector: NetworkCollector::new(),
            gpu_collector: GpuCollector::new(),
            system_info_collector: SystemInfoCollector::new(),
        }
    }

    /// Run the metrics collector loop
    pub async fn run(mut self) {
        let interval = Duration::from_millis(self.config.collector.cpu_interval_ms);
        let mut ticker = time::interval(interval);

        info!(
            "Metrics collector started (interval: {}ms)",
            self.config.collector.cpu_interval_ms
        );

        loop {
            ticker.tick().await;

            match self.collect_metrics() {
                Ok(metrics) => {
                    debug!(
                        "Collected metrics: CPU={:.1}%, MEM={:.1}%, GPUs={}",
                        metrics.cpu.as_ref().map(|c| c.usage_percent).unwrap_or(0.0),
                        metrics
                            .memory
                            .as_ref()
                            .map(|m| {
                                if m.total > 0 {
                                    (m.used as f64 / m.total as f64) * 100.0
                                } else {
                                    0.0
                                }
                            })
                            .unwrap_or(0.0),
                        metrics.gpus.len()
                    );
                    self.buffer.push(metrics);
                }
                Err(e) => {
                    error!("Failed to collect metrics: {}", e);
                }
            }
        }
    }

    /// Collect all metrics
    fn collect_metrics(&mut self) -> anyhow::Result<Metrics> {
        // Refresh system info
        self.system.refresh_cpu_all();
        self.system.refresh_memory();

        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_millis() as u64;

        // Collect CPU metrics
        let cpu = self
            .cpu_collector
            .collect(&self.system, &self.config.collector);

        // Collect memory metrics
        let memory = self.memory_collector.collect(&self.system);

        // Collect disk metrics
        self.disks.refresh();
        let disks = self
            .disk_collector
            .collect(&self.disks, &self.config.collector);

        // Collect network metrics
        self.networks.refresh();
        let networks = self
            .network_collector
            .collect(&self.networks, &self.config.collector);

        // Collect GPU metrics
        let gpu_metrics = self.gpu_collector.collect();
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

        // Collect system info
        let system_info = self.system_info_collector.collect();

        // Get load average (Unix only)
        let load_average = self.get_load_average();

        Ok(Metrics {
            timestamp,
            cpu: Some(cpu),
            memory: Some(memory),
            disks,
            networks,
            load_average,
            hostname: self.hostname.clone(),
            gpus,
            system_info: Some(system_info),
        })
    }

    /// Get system load average (Unix only)
    #[cfg(unix)]
    fn get_load_average(&self) -> Vec<f64> {
        let load = System::load_average();
        vec![load.one, load.five, load.fifteen]
    }

    #[cfg(windows)]
    fn get_load_average(&self) -> Vec<f64> {
        // Windows doesn't have load average, return empty
        vec![]
    }
}
