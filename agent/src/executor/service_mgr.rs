use std::process::Command;
use tracing::info;

use crate::proto::CommandResult;
use crate::security::validation::validate_service_name;

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

    /// Get service status. An empty target lists all services (JSON in `output`).
    pub async fn service_status(&self, service_name: &str) -> CommandResult {
        if service_name.trim().is_empty() {
            return self.list_services();
        }
        self.execute_service_command(service_name, ServiceAction::Status)
            .await
    }

    /// List all services as a JSON object {"services":[{name,status,sub,description}]} in `output`.
    fn list_services(&self) -> CommandResult {
        info!("[AUDIT] ServiceList");
        let mut services: Vec<serde_json::Value> = Vec::new();

        #[cfg(target_os = "linux")]
        if let Ok(out) = Command::new("systemctl")
            .args(["list-units", "--type=service", "--all", "--no-pager", "--plain", "--no-legend"])
            .output()
        {
            for line in String::from_utf8_lossy(&out.stdout).lines() {
                let f: Vec<&str> = line.split_whitespace().collect();
                if f.len() < 4 {
                    continue;
                }
                let desc = f[4..].join(" ");
                services.push(serde_json::json!({ "name": f[0], "status": f[2], "sub": f[3], "description": desc }));
            }
        }

        #[cfg(target_os = "macos")]
        if let Ok(out) = Command::new("launchctl").arg("list").output() {
            for (i, line) in String::from_utf8_lossy(&out.stdout).lines().enumerate() {
                if i == 0 {
                    continue; // header
                }
                let f: Vec<&str> = line.split_whitespace().collect();
                if f.len() < 3 {
                    continue;
                }
                let running = f[0] != "-";
                services.push(serde_json::json!({ "name": f[2], "status": if running { "active" } else { "inactive" }, "sub": if running { "running" } else { "dead" }, "description": "" }));
            }
        }

        #[cfg(target_os = "windows")]
        if let Ok(out) = Command::new("sc").args(["query", "type=", "service", "state=", "all"]).output() {
            let text = String::from_utf8_lossy(&out.stdout);
            let mut name = String::new();
            for line in text.lines() {
                let l = line.trim();
                if let Some(rest) = l.strip_prefix("SERVICE_NAME:") {
                    name = rest.trim().to_string();
                } else if l.starts_with("STATE") && !name.is_empty() {
                    let running = l.contains("RUNNING");
                    services.push(serde_json::json!({ "name": name.clone(), "status": if running { "active" } else { "inactive" }, "sub": if running { "running" } else { "stopped" }, "description": "" }));
                    name.clear();
                }
            }
        }

        let payload = serde_json::json!({ "services": services });
        CommandResult {
            command_id: String::new(),
            success: true,
            output: payload.to_string(),
            error: String::new(),
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
