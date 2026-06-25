use std::process::Command;
use tracing::info;

use crate::proto::{CommandResult, ServiceInfo};
use crate::security::validation::validate_service_name;

/// Format a duration in seconds as a short uptime string (e.g. "3d4h").
#[cfg(target_os = "linux")]
fn fmt_uptime(secs: u64) -> String {
    let d = secs / 86400;
    let h = (secs % 86400) / 3600;
    let m = (secs % 3600) / 60;
    if d > 0 {
        format!("{d}d{h}h")
    } else if h > 0 {
        format!("{h}h{m}m")
    } else {
        format!("{m}m")
    }
}

/// Batch-query systemd for per-unit uptime + restart count in one `systemctl
/// show` call. Uptime is derived from the monotonic active-enter timestamp and
/// /proc/uptime so no timezone parsing is needed. Returns name -> (uptime, restarts).
#[cfg(target_os = "linux")]
fn systemd_runtime(names: &[String]) -> std::collections::HashMap<String, (String, i32)> {
    let mut out = std::collections::HashMap::new();
    if names.is_empty() {
        return out;
    }
    let boot_secs: f64 = std::fs::read_to_string("/proc/uptime")
        .ok()
        .and_then(|s| s.split_whitespace().next().map(|v| v.to_string()))
        .and_then(|v| v.parse().ok())
        .unwrap_or(0.0);

    let mut args: Vec<String> = vec![
        "show".into(),
        "-p".into(),
        "Id,NRestarts,ActiveEnterTimestampMonotonic".into(),
    ];
    args.extend(names.iter().cloned());

    let uptime_for = |mono: u64| -> String {
        if mono > 0 && boot_secs > 0.0 {
            let secs = (boot_secs - (mono as f64 / 1_000_000.0)).max(0.0) as u64;
            fmt_uptime(secs)
        } else {
            String::new()
        }
    };

    if let Ok(o) = Command::new("systemctl").args(&args).output() {
        if o.status.success() {
            let text = String::from_utf8_lossy(&o.stdout);
            let mut id = String::new();
            let mut nr: i32 = 0;
            let mut mono: u64 = 0;
            for line in text.lines() {
                if line.is_empty() {
                    if !id.is_empty() {
                        out.insert(std::mem::take(&mut id), (uptime_for(mono), nr));
                    }
                    nr = 0;
                    mono = 0;
                } else if let Some(v) = line.strip_prefix("Id=") {
                    id = v.to_string();
                } else if let Some(v) = line.strip_prefix("NRestarts=") {
                    nr = v.trim().parse().unwrap_or(0);
                } else if let Some(v) = line.strip_prefix("ActiveEnterTimestampMonotonic=") {
                    mono = v.trim().parse().unwrap_or(0);
                }
            }
            if !id.is_empty() {
                out.insert(id, (uptime_for(mono), nr));
            }
        }
    }
    out
}

/// Service management executor
pub struct ServiceExecutor;

impl ServiceExecutor {
    /// Create a new service executor
    pub fn new() -> Self {
        Self
    }

    /// Helper to create an error CommandResult
    fn error_result(error: String) -> CommandResult {
        CommandResult {
            command_id: String::new(),
            success: false,
            output: String::new(),
            error,
            ..Default::default()
        }
    }

    /// Start a service
    pub async fn start_service(&self, service_name: &str) -> CommandResult {
        self.execute_service_command(service_name, ServiceAction::Start)
            .await
    }

    /// Stop a service
    pub async fn stop_service(&self, service_name: &str) -> CommandResult {
        self.execute_service_command(service_name, ServiceAction::Stop)
            .await
    }

    /// Restart a service
    pub async fn restart_service(&self, service_name: &str) -> CommandResult {
        self.execute_service_command(service_name, ServiceAction::Restart)
            .await
    }

    /// Get service status for a single service.
    pub async fn service_status(&self, service_name: &str) -> CommandResult {
        self.execute_service_command(service_name, ServiceAction::Status)
            .await
    }

    /// List all services as structured ServiceInfo entries (SERVICE_LIST).
    pub async fn list_services(&self) -> CommandResult {
        info!("[AUDIT] ServiceList");
        let mut services: Vec<ServiceInfo> = Vec::new();

        #[cfg(target_os = "linux")]
        if let Ok(out) = Command::new("systemctl")
            .args([
                "list-units",
                "--type=service",
                "--all",
                "--no-pager",
                "--plain",
                "--no-legend",
            ])
            .output()
        {
            for line in String::from_utf8_lossy(&out.stdout).lines() {
                let f: Vec<&str> = line.split_whitespace().collect();
                if f.len() < 4 {
                    continue;
                }
                services.push(ServiceInfo {
                    name: f[0].to_string(),
                    status: f[2].to_string(),
                    sub_state: f[3].to_string(),
                    description: f.get(4..).map(|s| s.join(" ")).unwrap_or_default(),
                    uptime: String::new(),
                    restarts: 0,
                });
            }
            // Enrich with uptime + restart count in a single systemctl show call.
            let names: Vec<String> = services.iter().map(|s| s.name.clone()).collect();
            let rt = systemd_runtime(&names);
            for s in services.iter_mut() {
                if let Some((up, nr)) = rt.get(&s.name) {
                    s.uptime = up.clone();
                    s.restarts = *nr;
                }
            }
        }

        #[cfg(target_os = "macos")]
        if let Ok(out) = Command::new("launchctl").arg("list").output() {
            for (i, line) in String::from_utf8_lossy(&out.stdout).lines().enumerate() {
                if i == 0 {
                    continue; // header: PID Status Label
                }
                let f: Vec<&str> = line.split_whitespace().collect();
                if f.len() < 3 {
                    continue;
                }
                let running = f[0] != "-";
                services.push(ServiceInfo {
                    name: f[2].to_string(),
                    status: if running { "active" } else { "inactive" }.to_string(),
                    sub_state: if running { "running" } else { "dead" }.to_string(),
                    description: String::new(),
                    uptime: String::new(),
                    restarts: 0,
                });
            }
        }

        #[cfg(target_os = "windows")]
        if let Ok(out) = Command::new("sc")
            .args(["query", "type=", "service", "state=", "all"])
            .output()
        {
            let text = String::from_utf8_lossy(&out.stdout);
            let mut name = String::new();
            for line in text.lines() {
                let l = line.trim();
                if let Some(rest) = l.strip_prefix("SERVICE_NAME:") {
                    name = rest.trim().to_string();
                } else if l.starts_with("STATE") && !name.is_empty() {
                    let running = l.contains("RUNNING");
                    services.push(ServiceInfo {
                        name: std::mem::take(&mut name),
                        status: if running { "active" } else { "inactive" }.to_string(),
                        sub_state: if running { "running" } else { "stopped" }.to_string(),
                        description: String::new(),
                        uptime: String::new(),
                        restarts: 0,
                    });
                }
            }
        }

        CommandResult {
            command_id: String::new(),
            success: true,
            output: format!("{} services", services.len()),
            error: String::new(),
            services,
            ..Default::default()
        }
    }

    /// Execute a service command
    async fn execute_service_command(
        &self,
        service_name: &str,
        action: ServiceAction,
    ) -> CommandResult {
        // Validate service name to prevent command injection
        if let Err(e) = validate_service_name(service_name) {
            return Self::error_result(e);
        }

        info!("[AUDIT] Service {:?}: {}", action, service_name);
        #[cfg(target_os = "linux")]
        {
            self.execute_systemctl(service_name, action)
        }

        #[cfg(target_os = "macos")]
        {
            self.execute_launchctl(service_name, action)
        }

        #[cfg(target_os = "windows")]
        {
            self.execute_sc(service_name, action)
        }
    }

    /// Execute systemctl command (Linux)
    #[cfg(target_os = "linux")]
    fn execute_systemctl(&self, service_name: &str, action: ServiceAction) -> CommandResult {
        let action_str = match action {
            ServiceAction::Start => "start",
            ServiceAction::Stop => "stop",
            ServiceAction::Restart => "restart",
            ServiceAction::Status => "status",
        };

        match Command::new("systemctl")
            .args([action_str, service_name])
            .output()
        {
            Ok(output) => CommandResult {
                command_id: String::new(),
                success: output.status.success(),
                output: String::from_utf8_lossy(&output.stdout).to_string(),
                error: String::from_utf8_lossy(&output.stderr).to_string(),
                ..Default::default()
            },
            Err(e) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: format!("Failed to execute systemctl: {}", e),
                ..Default::default()
            },
        }
    }

    /// Execute launchctl command (macOS)
    #[cfg(target_os = "macos")]
    fn execute_launchctl(&self, service_name: &str, action: ServiceAction) -> CommandResult {
        let (cmd, args) = match action {
            ServiceAction::Start => ("launchctl", vec!["load", "-w", service_name]),
            ServiceAction::Stop => ("launchctl", vec!["unload", "-w", service_name]),
            ServiceAction::Restart => {
                // macOS doesn't have native restart, do stop then start
                let _stop_result = Command::new("launchctl")
                    .args(["unload", "-w", service_name])
                    .output();

                return match Command::new("launchctl")
                    .args(["load", "-w", service_name])
                    .output()
                {
                    Ok(output) => CommandResult {
                        command_id: String::new(),
                        success: output.status.success(),
                        output: String::from_utf8_lossy(&output.stdout).to_string(),
                        error: String::from_utf8_lossy(&output.stderr).to_string(),
                        ..Default::default()
                    },
                    Err(e) => CommandResult {
                        command_id: String::new(),
                        success: false,
                        output: String::new(),
                        error: format!("Failed to restart service: {}", e),
                        ..Default::default()
                    },
                };
            }
            ServiceAction::Status => ("launchctl", vec!["list", service_name]),
        };

        match Command::new(cmd).args(&args).output() {
            Ok(output) => CommandResult {
                command_id: String::new(),
                success: output.status.success(),
                output: String::from_utf8_lossy(&output.stdout).to_string(),
                error: String::from_utf8_lossy(&output.stderr).to_string(),
                ..Default::default()
            },
            Err(e) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: format!("Failed to execute launchctl: {}", e),
                ..Default::default()
            },
        }
    }

    /// Execute sc command (Windows)
    #[cfg(target_os = "windows")]
    fn execute_sc(&self, service_name: &str, action: ServiceAction) -> CommandResult {
        let action_str = match action {
            ServiceAction::Start => "start",
            ServiceAction::Stop => "stop",
            ServiceAction::Restart => {
                // Windows doesn't have native restart, do stop then start
                let _ = Command::new("sc").args(["stop", service_name]).output();

                // Wait a moment for the service to stop
                std::thread::sleep(std::time::Duration::from_secs(2));

                "start"
            }
            ServiceAction::Status => "query",
        };

        match Command::new("sc").args([action_str, service_name]).output() {
            Ok(output) => CommandResult {
                command_id: String::new(),
                success: output.status.success(),
                output: String::from_utf8_lossy(&output.stdout).to_string(),
                error: String::from_utf8_lossy(&output.stderr).to_string(),
                ..Default::default()
            },
            Err(e) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: format!("Failed to execute sc: {e}"),
                ..Default::default()
            },
        }
    }
}

impl Default for ServiceExecutor {
    fn default() -> Self {
        Self::new()
    }
}

/// Service action types
#[derive(Debug)]
enum ServiceAction {
    Start,
    Stop,
    Restart,
    Status,
}
