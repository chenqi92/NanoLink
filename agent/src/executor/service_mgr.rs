use std::process::Command;
use tracing::{debug, error, info};

use crate::proto::CommandResult;

/// Service management executor
pub struct ServiceExecutor;

impl ServiceExecutor {
    /// Create a new service executor
    pub fn new() -> Self {
        Self
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

    /// Get service status
    pub async fn service_status(&self, service_name: &str) -> CommandResult {
        self.execute_service_command(service_name, ServiceAction::Status)
            .await
    }

    /// Execute a service command
    async fn execute_service_command(
        &self,
        service_name: &str,
        action: ServiceAction,
    ) -> CommandResult {
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
                file_content: vec![],
                processes: vec![],
                containers: vec![],
            },
            Err(e) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: format!("Failed to execute systemctl: {}", e),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
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
                let stop_result = Command::new("launchctl")
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
                        file_content: vec![],
                        processes: vec![],
                        containers: vec![],
                    },
                    Err(e) => CommandResult {
                        command_id: String::new(),
                        success: false,
                        output: String::new(),
                        error: format!("Failed to restart service: {}", e),
                        file_content: vec![],
                        processes: vec![],
                        containers: vec![],
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
                file_content: vec![],
                processes: vec![],
                containers: vec![],
            },
            Err(e) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: format!("Failed to execute launchctl: {}", e),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
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

        match Command::new("sc")
            .args([action_str, service_name])
            .output()
        {
            Ok(output) => CommandResult {
                command_id: String::new(),
                success: output.status.success(),
                output: String::from_utf8_lossy(&output.stdout).to_string(),
                error: String::from_utf8_lossy(&output.stderr).to_string(),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
            },
            Err(e) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: format!("Failed to execute sc: {}", e),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
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
enum ServiceAction {
    Start,
    Stop,
    Restart,
    Status,
}
