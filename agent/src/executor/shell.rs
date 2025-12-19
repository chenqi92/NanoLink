use std::process::Command;
use std::sync::Arc;
use std::time::Duration;
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

    /// Execute a shell command
    pub async fn execute(&self, command: &str, super_token: &str) -> CommandResult {
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
                file_content: vec![],
                processes: vec![],
                containers: vec![],
            };
        }

        // Log the command execution
        info!("Executing shell command: {}", command);

        // Execute with timeout
        let timeout_secs = self.config.shell.timeout_seconds;

        #[cfg(unix)]
        let result = self.execute_unix(command, timeout_secs);

        #[cfg(windows)]
        let result = self.execute_windows(command, timeout_secs);

        // Log the result
        if result.success {
            info!("Shell command completed successfully");
        } else {
            warn!("Shell command failed: {}", result.error);
        }

        result
    }

    /// Execute command on Unix systems
    #[cfg(unix)]
    fn execute_unix(&self, command: &str, timeout_secs: u64) -> CommandResult {
        use std::io::Read;
        use std::process::Stdio;

        let mut child = match Command::new("sh")
            .args(["-c", command])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
        {
            Ok(child) => child,
            Err(e) => {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: format!("Failed to spawn shell: {}", e),
                    file_content: vec![],
                    processes: vec![],
                    containers: vec![],
                }
            }
        };

        // Wait with timeout
        let timeout = Duration::from_secs(timeout_secs);
        let start = std::time::Instant::now();

        loop {
            match child.try_wait() {
                Ok(Some(status)) => {
                    // Process finished
                    let mut stdout = String::new();
                    let mut stderr = String::new();

                    if let Some(mut out) = child.stdout.take() {
                        let _ = out.read_to_string(&mut stdout);
                    }
                    if let Some(mut err) = child.stderr.take() {
                        let _ = err.read_to_string(&mut stderr);
                    }

                    return CommandResult {
                        command_id: String::new(),
                        success: status.success(),
                        output: stdout,
                        error: stderr,
                        file_content: vec![],
                        processes: vec![],
                        containers: vec![],
                    };
                }
                Ok(None) => {
                    // Still running
                    if start.elapsed() > timeout {
                        // Timeout - kill the process
                        let _ = child.kill();
                        return CommandResult {
                            command_id: String::new(),
                            success: false,
                            output: String::new(),
                            error: format!("Command timed out after {} seconds", timeout_secs),
                            file_content: vec![],
                            processes: vec![],
                            containers: vec![],
                        };
                    }
                    std::thread::sleep(Duration::from_millis(100));
                }
                Err(e) => {
                    return CommandResult {
                        command_id: String::new(),
                        success: false,
                        output: String::new(),
                        error: format!("Failed to wait for process: {}", e),
                        file_content: vec![],
                        processes: vec![],
                        containers: vec![],
                    }
                }
            }
        }
    }

    /// Execute command on Windows systems
    #[cfg(windows)]
    fn execute_windows(&self, command: &str, timeout_secs: u64) -> CommandResult {
        use std::io::Read;
        use std::process::Stdio;

        let mut child = match Command::new("cmd")
            .args(["/C", command])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
        {
            Ok(child) => child,
            Err(e) => {
                return CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: format!("Failed to spawn shell: {}", e),
                    file_content: vec![],
                    processes: vec![],
                    containers: vec![],
                }
            }
        };

        // Wait with timeout
        let timeout = Duration::from_secs(timeout_secs);
        let start = std::time::Instant::now();

        loop {
            match child.try_wait() {
                Ok(Some(status)) => {
                    // Process finished
                    let mut stdout = String::new();
                    let mut stderr = String::new();

                    if let Some(mut out) = child.stdout.take() {
                        let _ = out.read_to_string(&mut stdout);
                    }
                    if let Some(mut err) = child.stderr.take() {
                        let _ = err.read_to_string(&mut stderr);
                    }

                    return CommandResult {
                        command_id: String::new(),
                        success: status.success(),
                        output: stdout,
                        error: stderr,
                        file_content: vec![],
                        processes: vec![],
                        containers: vec![],
                    };
                }
                Ok(None) => {
                    // Still running
                    if start.elapsed() > timeout {
                        // Timeout - kill the process
                        let _ = child.kill();
                        return CommandResult {
                            command_id: String::new(),
                            success: false,
                            output: String::new(),
                            error: format!("Command timed out after {} seconds", timeout_secs),
                            file_content: vec![],
                            processes: vec![],
                            containers: vec![],
                        };
                    }
                    std::thread::sleep(Duration::from_millis(100));
                }
                Err(e) => {
                    return CommandResult {
                        command_id: String::new(),
                        success: false,
                        output: String::new(),
                        error: format!("Failed to wait for process: {}", e),
                        file_content: vec![],
                        processes: vec![],
                        containers: vec![],
                    }
                }
            }
        }
    }
}
