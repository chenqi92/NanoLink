use std::sync::Arc;
use std::sync::OnceLock;

use chrono::Utc;
use regex::Regex;
use tracing::{info, warn};

use crate::buffer::RingBuffer;
use crate::config::Config;
use crate::executor::{
    BuildExecutor, ConfigManager, DeploymentExecutor, DockerExecutor, FileExecutor, HealthExecutor,
    LogExecutor, PackageManager, ProcessExecutor, ScriptExecutor, ServiceExecutor, ShellExecutor,
    UpdateExecutor,
};
use crate::management::audit::{AuditState, CommandAuditEntry};
use crate::proto::{Command, CommandResult, CommandType};
use crate::security::{PermissionChecker, remote_read_only_allows};

/// Truncate a string to at most `max` characters (char-boundary safe) for audit
/// fields, so a large target/error cannot bloat the audit log.
fn truncate_for_audit(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        s.to_string()
    } else {
        s.chars().take(max).collect()
    }
}

fn redact_shell_secrets(command: &str) -> String {
    static SECRET_FLAGS: OnceLock<Regex> = OnceLock::new();
    static SECRET_ENV: OnceLock<Regex> = OnceLock::new();
    let flags = SECRET_FLAGS.get_or_init(|| {
        Regex::new(r"(?i)(--(?:password|token|secret|api[-_]?key)(?:=|\s+))\S+")
            .expect("BUG: invalid secret flag regex")
    });
    let env = SECRET_ENV.get_or_init(|| {
        Regex::new(r"(?i)\b([A-Z0-9_]*(?:PASSWORD|TOKEN|SECRET|API_KEY))=\S+")
            .expect("BUG: invalid secret env regex")
    });
    let redacted = flags.replace_all(command, "$1[REDACTED]");
    env.replace_all(&redacted, "$1=[REDACTED]").into_owned()
}

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
    log_executor: LogExecutor,
    script_executor: ScriptExecutor,
    config_manager: ConfigManager,
    package_manager: PackageManager,
    health_executor: HealthExecutor,
    deployment_executor: DeploymentExecutor,
    build_executor: BuildExecutor,
    audit: Arc<AuditState>,
}

impl MessageHandler {
    /// Create a new message handler
    pub fn new(config: Arc<Config>, buffer: Arc<RingBuffer>, permission_level: u8) -> Self {
        let mut command_audit_config = config.management.audit.clone();
        command_audit_config.enabled |= config.logging.audit_enabled;
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
            log_executor: LogExecutor::new(),
            script_executor: ScriptExecutor::new(config.clone()),
            config_manager: ConfigManager::new(config.clone()),
            package_manager: PackageManager::new(config.clone()),
            health_executor: HealthExecutor::new(),
            deployment_executor: DeploymentExecutor::new(config.clone()),
            build_executor: BuildExecutor::new(config.clone()),
            // Structured, rotating, flushed audit trail for privileged commands
            // (separate file from the HTTP management API audit to avoid two
            // writers contending for one file). Gated by config.audit.enabled.
            audit: Arc::new(AuditState::new(command_audit_config, "command-audit.log")),
        }
    }

    /// Record a privileged command in the structured audit log.
    async fn audit_command(
        &self,
        command_type: CommandType,
        target: &str,
        success: bool,
        error: Option<String>,
    ) {
        let audit_target = if command_type == CommandType::ShellExecute {
            redact_shell_secrets(target)
        } else {
            target.to_string()
        };
        self.audit
            .write_command_entry(&CommandAuditEntry {
                ts: Utc::now().to_rfc3339(),
                event: "command",
                command: format!("{command_type:?}"),
                target: truncate_for_audit(&audit_target, 256),
                permission: self.permission_level,
                success,
                error: error.map(|e| truncate_for_audit(&e, 256)),
            })
            .await;
    }

    /// Handle a command
    pub async fn handle_command(&self, command: Command) -> CommandResult {
        let command_type =
            CommandType::try_from(command.r#type).unwrap_or(CommandType::Unspecified);

        if self.config.agent.remote_read_only && !remote_read_only_allows(command_type) {
            warn!(
                "Rejected command {:?}: remote read-only mode is enabled",
                command_type
            );
            return CommandResult {
                command_id: command.command_id,
                success: false,
                error:
                    "Command is unavailable because this NAS Agent enforces remote read-only mode"
                        .to_string(),
                ..Default::default()
            };
        }

        if command_type == CommandType::ShellExecute {
            info!(
                "Received shell command (bytes: {}, id: {})",
                command.target.len(),
                command.command_id
            );
        } else {
            info!(
                "Received command: {:?} (target: {}, id: {})",
                command_type, command.target, command.command_id
            );
        }

        let required_level = self.permission_checker.required_level(command_type);

        // Check permission
        if !self
            .permission_checker
            .check_permission(command_type, self.permission_level)
        {
            warn!(
                "Permission denied for command {:?} (required: {}, have: {})",
                command_type, required_level, self.permission_level
            );
            self.audit_command(
                command_type,
                &command.target,
                false,
                Some(format!(
                    "permission denied (required {}, have {})",
                    required_level, self.permission_level
                )),
            )
            .await;
            return CommandResult {
                command_id: command.command_id,
                success: false,
                output: String::new(),
                error: format!(
                    "Permission denied. Required level: {}, your level: {}",
                    self.permission_checker.required_level(command_type),
                    self.permission_level
                ),
                ..Default::default()
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
            CommandType::ServiceList => self.service_executor.list_services().await,

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
            CommandType::FileList => self.file_executor.list_directory(&command.target).await,

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

            // Soft restart of the agent's OWN process (host stays up).
            CommandType::AgentProcessRestart => self.execute_agent_process_restart().await,

            // Shell command
            CommandType::ShellExecute => {
                let cols = command
                    .params
                    .get("cols")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(0);
                let rows = command
                    .params
                    .get("rows")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(0);
                self.shell_executor
                    .execute(&command.target, &command.super_token, cols, rows)
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

            // Log query commands
            CommandType::ServiceLogs => self.log_executor.get_service_logs(&command.params).await,
            CommandType::SystemLogs => self.log_executor.get_system_logs(&command.params).await,
            CommandType::AuditLogs => self.log_executor.get_audit_logs(&command.params).await,

            // Script execution commands
            CommandType::ScriptList => self.script_executor.list_scripts(&command.params).await,
            CommandType::ScriptExecute => {
                self.script_executor.execute_script(&command.params).await
            }

            // Config management commands
            CommandType::ConfigRead => self.config_manager.read_config(&command.params).await,
            CommandType::ConfigWrite => self.config_manager.write_config(&command.params).await,
            CommandType::ConfigValidate => {
                self.config_manager.validate_config(&command.params).await
            }
            CommandType::ConfigRollback => {
                self.config_manager.rollback_config(&command.params).await
            }
            CommandType::ConfigListBackups => {
                self.config_manager.list_backups(&command.params).await
            }

            // Package management commands
            CommandType::PackageList => self.package_manager.list_packages(&command.params).await,
            CommandType::PackageCheckUpdates => {
                self.package_manager.check_updates(&command.params).await
            }
            CommandType::PackageUpdate => {
                self.package_manager.update_package(&command.params).await
            }
            CommandType::PackageInstall => {
                self.package_manager.install_package(&command.params).await
            }
            CommandType::SystemUpdate => self.package_manager.system_update(&command.params).await,

            // Health / connectivity probes
            CommandType::ConnectivityTest | CommandType::HealthCheck => {
                self.health_executor
                    .connectivity_test(&command.target, &command.params)
                    .await
            }

            // Structured application deployment
            CommandType::DeployExecute => self.deployment_executor.deploy(&command.params).await,
            CommandType::DeployRollback => self.deployment_executor.rollback(&command.params).await,
            CommandType::BuildExecute => self.build_executor.execute(&command.params).await,
            CommandType::BuildCancel => self.build_executor.cancel(&command.target),
            CommandType::BuildGitStatus => self.build_executor.git_status().await,

            _ => CommandResult {
                command_id: command.command_id.clone(),
                success: false,
                output: String::new(),
                error: format!("Unknown command type: {command_type:?}"),
                ..Default::default()
            },
        };

        // Audit privileged (level >= 1) operations: file writes, service/docker
        // control, shell, config writes, package updates, reboot, scripts.
        // Read-only queries (level 0) are skipped to keep the trail signal-dense.
        if required_level >= 1 {
            let err = if result.error.is_empty() {
                None
            } else {
                Some(result.error.clone())
            };
            self.audit_command(command_type, &command.target, result.success, err)
                .await;
        }

        if command_type == CommandType::AgentApplyUpdate && result.success {
            Self::schedule_soft_restart();
        }

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
                    ..Default::default()
                },
                Err(e) => CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: format!("Failed to execute reboot: {}", e),
                    ..Default::default()
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
                    ..Default::default()
                },
                Err(e) => CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: format!("Failed to execute shutdown: {e}"),
                    ..Default::default()
                },
            }
        }
    }

    /// Gracefully restart the agent's OWN process WITHOUT rebooting the host.
    ///
    /// Behavior (platform-aware, best-effort):
    ///   1. We return a successful `CommandResult` immediately so the server (and
    ///      the issuing UI session) receives confirmation before this process
    ///      goes away — the gRPC stream that carries the result lives in the same
    ///      process we are about to kill.
    ///   2. A detached background task waits a short grace period (so the result
    ///      flushes over the wire), then performs the actual restart.
    ///
    /// Restart strategy (chosen by `is_supervised()`):
    ///   - If the agent runs under a service supervisor (systemd `Restart=`,
    ///     Windows SCM failure-action, launchd `KeepAlive`), a clean
    ///     `process::exit(0)` is enough: the supervisor respawns us. This is the
    ///     normal production path and does NOT touch the host. We deliberately do
    ///     NOT also spawn a fallback here, so a supervisor never briefly runs two
    ///     agents.
    ///   - As a fallback for standalone / foreground runs (no supervisor), we
    ///     first spawn a fresh, detached copy of the current binary with the same
    ///     CLI arguments, then exit. The child keeps running after the parent dies.
    ///
    /// This intentionally avoids `systemctl restart` / SCM stop+start of the host
    /// service (which `restart_agent_service()` in main.rs does for the
    /// interactive CLI path): that would kill us before the result is flushed and
    /// is heavier than a self re-exec. The host is never rebooted.
    async fn execute_agent_process_restart(&self) -> CommandResult {
        info!("[AUDIT] AgentProcessRestart requested - scheduling soft self-restart");
        Self::schedule_soft_restart();

        CommandResult {
            command_id: String::new(),
            success: true,
            output: "Agent process restart scheduled (host not affected).".to_string(),
            error: String::new(),
            ..Default::default()
        }
    }

    fn schedule_soft_restart() {
        // Give the gRPC sender enough time to flush the successful command result
        // before the process exits and systemd (or the standalone fallback)
        // starts the replacement binary.
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(800)).await;
            Self::soft_restart_process();
        });
    }

    /// Best-effort detection of whether this process runs under a service
    /// supervisor that will respawn it after a clean exit. Conservative and
    /// platform-guarded: a false negative only re-introduces the (already
    /// server-deduped) transient double-spawn, while a false positive could
    /// leave a manually-run agent down — so we only return `true` on signals
    /// that are specific to a supervisor.
    ///
    ///   - Linux: systemd sets `INVOCATION_ID` for every unit it starts and
    ///     `NOTIFY_SOCKET` for `Type=notify` units. Either implies a unit that
    ///     a `Restart=` policy can respawn.
    ///   - macOS: launchd exposes `XPC_SERVICE_NAME` for jobs it launches; the
    ///     literal `0` value means "not under launchd", so we exclude it.
    ///   - Windows: detecting SCM ownership cheaply is not reliable from inside
    ///     the process, so we conservatively assume NOT supervised and keep the
    ///     spawn-then-exit fallback.
    fn is_supervised() -> bool {
        #[cfg(target_os = "linux")]
        {
            return std::env::var_os("INVOCATION_ID").is_some()
                || std::env::var_os("NOTIFY_SOCKET").is_some();
        }

        #[cfg(target_os = "macos")]
        {
            return match std::env::var("XPC_SERVICE_NAME") {
                Ok(name) => !name.is_empty() && name != "0",
                Err(_) => false,
            };
        }

        #[cfg(not(any(target_os = "linux", target_os = "macos")))]
        {
            false
        }
    }

    /// Perform the actual soft restart.
    ///
    /// If a service supervisor is detected, exit cleanly ONLY and let the
    /// supervisor respawn us — spawning a fallback here would briefly run two
    /// agents (supervisor's instance + our detached child). Otherwise (interactive
    /// / foreground / no supervisor) spawn a detached copy of ourselves first so a
    /// manually-run agent still comes back, then exit. Does not return.
    fn soft_restart_process() -> ! {
        if Self::is_supervised() {
            info!(
                "Soft restart: service supervisor detected; exiting cleanly and letting the supervisor respawn (no fallback spawn)"
            );
            std::process::exit(0);
        }

        // No supervisor detected: launch a detached fresh instance so
        // standalone/foreground runs still come back up. Failure here is
        // non-fatal.
        info!(
            "Soft restart: no service supervisor detected; spawning a detached replacement before exit"
        );
        match std::env::current_exe() {
            Ok(exe) => {
                let args: Vec<String> = std::env::args().skip(1).collect();
                let mut cmd = std::process::Command::new(exe);
                cmd.args(&args);
                // The replacement starts before this process exits, so allow it
                // to wait briefly for the per-config instance lock to be released.
                cmd.env(crate::instance_lock::RESTART_WAIT_ENV, "10000");

                #[cfg(windows)]
                {
                    use std::os::windows::process::CommandExt;
                    // DETACHED_PROCESS (0x00000008): the child does not share the
                    // parent's console and survives parent exit.
                    cmd.creation_flags(0x0000_0008);
                }

                match cmd.spawn() {
                    Ok(_) => info!("Spawned detached agent instance for soft restart"),
                    Err(e) => warn!(
                        "Failed to spawn detached agent instance ({e}); relying on service supervisor to respawn"
                    ),
                }
            }
            Err(e) => warn!(
                "Failed to resolve current_exe for soft restart ({e}); relying on service supervisor to respawn"
            ),
        }

        info!("Exiting current agent process for soft restart");
        std::process::exit(0);
    }
}

#[cfg(test)]
mod audit_tests {
    use super::*;

    #[test]
    fn shell_audit_redacts_common_secret_forms() {
        let command = "TOKEN=abc curl --api-key xyz --password=hidden https://example.com";
        let redacted = redact_shell_secrets(command);
        assert!(!redacted.contains("abc"));
        assert!(!redacted.contains("xyz"));
        assert!(!redacted.contains("hidden"));
        assert!(redacted.contains("TOKEN=[REDACTED]"));
    }
}
