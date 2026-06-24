use std::process::Stdio;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::AsyncReadExt;
use tokio::process::Command;
use tracing::{info, warn};

use crate::config::Config;
use crate::proto::CommandResult;
use crate::security::PermissionChecker;

/// Shell command executor with security controls
pub struct ShellExecutor {
    config: Arc<Config>,
    permission_checker: PermissionChecker,
}

impl ShellExecutor {
    /// Create a new shell executor
    pub fn new(config: Arc<Config>) -> Self {
        Self {
            permission_checker: PermissionChecker::new(config.clone()),
            config,
        }
    }

    /// Execute a shell command. cols/rows carry the client terminal size (0 if
    /// unknown) so the spawned process can export COLUMNS/LINES.
    pub async fn execute(
        &self,
        command: &str,
        super_token: &str,
        cols: u16,
        rows: u16,
    ) -> CommandResult {
        // Check permissions
        if let Err(e) = self
            .permission_checker
            .check_shell_command(command, super_token)
        {
            warn!("Shell command denied: {} - {}", command, e);
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: e,
                ..Default::default()
            };
        }

        info!("Executing shell command: {}", command);

        let timeout_secs = self.config.shell.timeout_seconds;
        let result = self.run(command, timeout_secs, cols, rows).await;

        if result.success {
            info!("Shell command completed successfully");
        } else {
            warn!("Shell command failed: {}", result.error);
        }

        result
    }

    /// Spawn the platform shell, concurrently drain stdout/stderr, and wait with timeout.
    ///
    /// Concurrent draining is required: with synchronous read-after-wait, a command whose
    /// output exceeds the OS pipe buffer (~64KB on Linux) blocks the child on its next
    /// write, the child never exits, and we hit the timeout branch even though the work
    /// itself was fine. Using async streams lets the OS hand us bytes as they arrive.
    async fn run(&self, command: &str, timeout_secs: u64, cols: u16, rows: u16) -> CommandResult {
        let mut cmd = if cfg!(windows) {
            let mut c = Command::new("cmd");
            c.args(["/C", command]);
            c
        } else {
            let mut c = Command::new("sh");
            c.args(["-c", command]);
            c
        };

        // Export the client terminal size so width-aware tools (ls, ps, top)
        // format their output correctly even without a real PTY.
        if cols > 0 {
            cmd.env("COLUMNS", cols.to_string());
        }
        if rows > 0 {
            cmd.env("LINES", rows.to_string());
        }

        let mut child = match cmd
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true)
            .spawn()
        {
            Ok(child) => child,
            Err(e) => {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: format!("Failed to spawn shell: {e}"),
                    ..Default::default()
                };
            }
        };

        let stdout = child.stdout.take();
        let stderr = child.stderr.take();

        let stdout_task = tokio::spawn(async move {
            let mut buf = Vec::new();
            if let Some(mut s) = stdout {
                let _ = s.read_to_end(&mut buf).await;
            }
            buf
        });
        let stderr_task = tokio::spawn(async move {
            let mut buf = Vec::new();
            if let Some(mut s) = stderr {
                let _ = s.read_to_end(&mut buf).await;
            }
            buf
        });

        let timeout = Duration::from_secs(timeout_secs);
        let wait_result = tokio::time::timeout(timeout, child.wait()).await;

        let status = match wait_result {
            Ok(Ok(status)) => status,
            Ok(Err(e)) => {
                stdout_task.abort();
                stderr_task.abort();
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: format!("Failed to wait for process: {e}"),
                    ..Default::default()
                };
            }
            Err(_) => {
                let _ = child.start_kill();
                let _ = child.wait().await;
                stdout_task.abort();
                stderr_task.abort();
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: format!("Command timed out after {timeout_secs} seconds"),
                    ..Default::default()
                };
            }
        };

        let stdout_buf = stdout_task.await.unwrap_or_default();
        let stderr_buf = stderr_task.await.unwrap_or_default();

        CommandResult {
            command_id: String::new(),
            success: status.success(),
            output: String::from_utf8_lossy(&stdout_buf).into_owned(),
            error: String::from_utf8_lossy(&stderr_buf).into_owned(),
            ..Default::default()
        }
    }
}
