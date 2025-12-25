use std::sync::Arc;
use tracing::{info, warn};

use crate::buffer::RingBuffer;
use crate::config::Config;
use crate::executor::{
    DockerExecutor, FileExecutor, ProcessExecutor, ServiceExecutor, ShellExecutor, UpdateExecutor,
};
use crate::proto::{Command, CommandResult, CommandType};
use crate::security::PermissionChecker;

/// Handles incoming commands from the server
pub struct MessageHandler {
    #[allow(dead_code)]
    config: Arc<Config>,
    #[allow(dead_code)]
    buffer: Arc<RingBuffer>,
    permission_level: u8,
    permission_checker: PermissionChecker,
    process_executor: ProcessExecutor,
    service_executor: ServiceExecutor,
    file_executor: FileExecutor,
    docker_executor: DockerExecutor,
    shell_executor: ShellExecutor,
    update_executor: UpdateExecutor,
}

impl MessageHandler {
    /// Create a new message handler
    pub fn new(config: Arc<Config>, buffer: Arc<RingBuffer>, permission_level: u8) -> Self {
        Self {
            config: config.clone(),
            buffer,
            permission_level,
            permission_checker: PermissionChecker::new(config.clone()),
            process_executor: ProcessExecutor::new(),
            service_executor: ServiceExecutor::new(),
            file_executor: FileExecutor::new(config.clone()),
            docker_executor: DockerExecutor::new(),
            shell_executor: ShellExecutor::new(config.clone()),
            update_executor: UpdateExecutor::new(config.update.clone()),
        }
    }

    /// Handle a command
    pub async fn handle_command(&self, command: Command) -> CommandResult {
        let command_type =
            CommandType::try_from(command.r#type).unwrap_or(CommandType::Unspecified);

        info!(
            "Received command: {:?} (target: {}, id: {})",
            command_type, command.target, command.command_id
        );

        // Check permission
        if !self
            .permission_checker
            .check_permission(command_type, self.permission_level)
        {
            warn!(
                "Permission denied for command {:?} (required: {}, have: {})",
                command_type,
                self.permission_checker.required_level(command_type),
                self.permission_level
            );
            return CommandResult {
                command_id: command.command_id,
                success: false,
                output: String::new(),
                error: format!(
                    "Permission denied. Required level: {}, your level: {}",
                    self.permission_checker.required_level(command_type),
                    self.permission_level
                ),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
                update_info: None,
            };
        }

        // Execute command
        let result = match command_type {
            // Process management
            CommandType::ProcessList => self.process_executor.list_processes().await,
            CommandType::ProcessKill => {
                self.process_executor
                    .kill_process(&command.target, &command.params)
                    .await
            }

            // Service management
            CommandType::ServiceStart => self.service_executor.start_service(&command.target).await,
            CommandType::ServiceStop => self.service_executor.stop_service(&command.target).await,
            CommandType::ServiceRestart => {
                self.service_executor.restart_service(&command.target).await
            }
            CommandType::ServiceStatus => {
                self.service_executor.service_status(&command.target).await
            }

            // File operations
            CommandType::FileTail => {
                let lines = command
                    .params
                    .get("lines")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(100);
                self.file_executor.tail_file(&command.target, lines).await
            }
            CommandType::FileDownload => self.file_executor.download_file(&command.target).await,
            CommandType::FileUpload => {
                let content = command.params.get("content").map(|s| s.as_bytes().to_vec());
                self.file_executor
                    .upload_file(&command.target, content)
                    .await
            }
            CommandType::FileTruncate => self.file_executor.truncate_file(&command.target).await,

            // Docker operations
            CommandType::DockerList => self.docker_executor.list_containers().await,
            CommandType::DockerStart => self.docker_executor.start_container(&command.target).await,
            CommandType::DockerStop => self.docker_executor.stop_container(&command.target).await,
            CommandType::DockerRestart => {
                self.docker_executor
                    .restart_container(&command.target)
                    .await
            }
            CommandType::DockerLogs => {
                let lines = command
                    .params
                    .get("lines")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(100);
                self.docker_executor
                    .container_logs(&command.target, lines)
                    .await
            }

            // System operations
            CommandType::SystemReboot => self.execute_system_reboot().await,

            // Shell command
            CommandType::ShellExecute => {
                self.shell_executor
                    .execute(&command.target, &command.super_token)
                    .await
            }

            // Agent update commands
            CommandType::AgentCheckUpdate => self.update_executor.check_update().await,
            CommandType::AgentDownloadUpdate => {
                self.update_executor.download_update(&command.params).await
            }
            CommandType::AgentApplyUpdate => {
                self.update_executor.apply_update(&command.params).await
            }
            CommandType::AgentGetVersion => self.update_executor.get_version().await,

            _ => CommandResult {
                command_id: command.command_id.clone(),
                success: false,
                output: String::new(),
                error: format!("Unknown command type: {command_type:?}"),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
                update_info: None,
            },
        };

        CommandResult {
            command_id: command.command_id,
            ..result
        }
    }

    /// Execute system reboot
    async fn execute_system_reboot(&self) -> CommandResult {
        #[cfg(unix)]
        {
            match std::process::Command::new("reboot").output() {
                Ok(output) => CommandResult {
                    command_id: String::new(),
                    success: output.status.success(),
                    output: String::from_utf8_lossy(&output.stdout).to_string(),
                    error: String::from_utf8_lossy(&output.stderr).to_string(),
                    file_content: vec![],
                    processes: vec![],
                    containers: vec![],
                    update_info: None,
                },
                Err(e) => CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: format!("Failed to execute reboot: {}", e),
                    file_content: vec![],
                    processes: vec![],
                    containers: vec![],
                    update_info: None,
                },
            }
        }

        #[cfg(windows)]
        {
            match std::process::Command::new("shutdown")
                .args(["/r", "/t", "0"])
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
                    update_info: None,
                },
                Err(e) => CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: format!("Failed to execute shutdown: {e}"),
                    file_content: vec![],
                    processes: vec![],
                    containers: vec![],
                    update_info: None,
                },
            }
        }
    }
}
