//! Async command execution utilities
//!
//! Provides async subprocess execution with:
//! - Automatic spawn_blocking to avoid blocking async runtime
//! - Configurable timeouts per command type
//! - Unified error handling and logging
//!
//! Note: This module is prepared for future async migration.
//! Currently collectors use safe_command for sync execution with timeout.

#![allow(dead_code)]

use std::process::{Command, Stdio};
use std::time::Duration;
use tracing::{debug, warn};

/// Command timeout presets for different types of operations
#[derive(Debug, Clone, Copy)]
#[allow(dead_code)]
#[derive(Default)]
pub enum CommandTimeout {
    /// Fast commands like `who`, `ip addr` - 3 seconds
    #[default]
    Fast,
    /// Medium commands like `dmidecode`, `lshw` - 10 seconds
    Medium,
    /// Slow commands like `nvidia-smi` under load - 15 seconds
    Slow,
    /// Custom timeout
    Custom(Duration),
}

impl CommandTimeout {
    pub fn as_duration(&self) -> Duration {
        match self {
            CommandTimeout::Fast => Duration::from_secs(3),
            CommandTimeout::Medium => Duration::from_secs(10),
            CommandTimeout::Slow => Duration::from_secs(15),
            CommandTimeout::Custom(d) => *d,
        }
    }
}

/// Result of an async command execution
#[derive(Debug)]
pub enum CommandResult {
    /// Command completed successfully
    Success(String),
    /// Command returned non-zero exit code
    Failed(i32, String),
    /// Command timed out
    Timeout,
    /// Command not found or failed to start
    NotFound,
    /// Other error
    Error(String),
}

impl CommandResult {
    /// Get output if successful
    pub fn ok(self) -> Option<String> {
        match self {
            CommandResult::Success(s) => Some(s),
            _ => None,
        }
    }

    /// Check if successful
    pub fn is_success(&self) -> bool {
        matches!(self, CommandResult::Success(_))
    }
}

/// Execute a command asynchronously with timeout
///
/// This function:
/// 1. Runs the command in a blocking thread pool (spawn_blocking)
/// 2. Applies timeout protection
/// 3. Returns structured result
///
/// # Example
/// ```ignore
/// let result = run_command_async("nvidia-smi", &["--query-gpu=name"], CommandTimeout::Slow).await;
/// if let CommandResult::Success(output) = result {
///     println!("GPU: {}", output);
/// }
/// ```
pub async fn run_command_async(
    program: &str,
    args: &[&str],
    timeout: CommandTimeout,
) -> CommandResult {
    let program = program.to_string();
    let program_for_log = program.clone();
    let args: Vec<String> = args.iter().map(|s| s.to_string()).collect();
    let timeout_duration = timeout.as_duration();

    debug!(
        "Running command: {} {:?} (timeout: {:?})",
        program, args, timeout_duration
    );

    // Use tokio's timeout + spawn_blocking
    let result = tokio::time::timeout(
        timeout_duration,
        tokio::task::spawn_blocking(move || {
            execute_command_sync(&program, &args, timeout_duration)
        }),
    )
    .await;

    match result {
        Ok(Ok(cmd_result)) => cmd_result,
        Ok(Err(e)) => {
            warn!("spawn_blocking failed: {}", e);
            CommandResult::Error(e.to_string())
        }
        Err(_) => {
            warn!(
                "Command '{}' timed out after {:?}",
                program_for_log, timeout_duration
            );
            CommandResult::Timeout
        }
    }
}

/// Synchronous command execution with internal timeout
///
/// This runs in the blocking thread pool and has its own timeout mechanism
/// as a fallback in case the outer tokio timeout doesn't catch it.
fn execute_command_sync(program: &str, args: &[String], timeout: Duration) -> CommandResult {
    let mut cmd = Command::new(program);
    cmd.args(args);
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());

    let mut child = match cmd.spawn() {
        Ok(child) => child,
        Err(e) => {
            if e.kind() == std::io::ErrorKind::NotFound {
                return CommandResult::NotFound;
            }
            return CommandResult::Error(format!("Failed to spawn: {e}"));
        }
    };

    let start = std::time::Instant::now();

    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                // Process exited
                let stdout = child
                    .stdout
                    .take()
                    .map(|mut s| {
                        use std::io::Read;
                        let mut buf = String::new();
                        let _ = s.read_to_string(&mut buf);
                        buf
                    })
                    .unwrap_or_default();

                if status.success() {
                    return CommandResult::Success(stdout);
                } else {
                    let code = status.code().unwrap_or(-1);
                    return CommandResult::Failed(code, stdout);
                }
            }
            Ok(None) => {
                // Still running
                if start.elapsed() > timeout {
                    let _ = child.kill();
                    let _ = child.wait();
                    return CommandResult::Timeout;
                }
                std::thread::sleep(Duration::from_millis(50));
            }
            Err(e) => {
                return CommandResult::Error(format!("try_wait failed: {e}"));
            }
        }
    }
}

/// Convenience function for fast commands
pub async fn run_fast(program: &str, args: &[&str]) -> Option<String> {
    run_command_async(program, args, CommandTimeout::Fast)
        .await
        .ok()
}

/// Convenience function for medium-speed commands
pub async fn run_medium(program: &str, args: &[&str]) -> Option<String> {
    run_command_async(program, args, CommandTimeout::Medium)
        .await
        .ok()
}

/// Convenience function for slow commands
pub async fn run_slow(program: &str, args: &[&str]) -> Option<String> {
    run_command_async(program, args, CommandTimeout::Slow)
        .await
        .ok()
}

/// Check if a program exists and is executable
pub async fn command_exists(program: &str) -> bool {
    run_command_async(program, &["--version"], CommandTimeout::Fast)
        .await
        .is_success()
        || run_command_async(program, &["--help"], CommandTimeout::Fast)
            .await
            .is_success()
}

/// Check if a program exists by running a specific check command
pub async fn check_command(program: &str, check_args: &[&str]) -> bool {
    run_command_async(program, check_args, CommandTimeout::Fast)
        .await
        .is_success()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_run_command_success() {
        #[cfg(unix)]
        {
            let result = run_command_async("echo", &["hello"], CommandTimeout::Fast).await;
            assert!(matches!(result, CommandResult::Success(s) if s.contains("hello")));
        }
        #[cfg(windows)]
        {
            let result =
                run_command_async("cmd", &["/c", "echo", "hello"], CommandTimeout::Fast).await;
            assert!(result.is_success());
        }
    }

    #[tokio::test]
    async fn test_run_command_not_found() {
        let result = run_command_async("nonexistent_cmd_12345", &[], CommandTimeout::Fast).await;
        assert!(matches!(result, CommandResult::NotFound));
    }

    #[tokio::test]
    async fn test_command_timeout() {
        #[cfg(unix)]
        {
            let result = run_command_async(
                "sleep",
                &["10"],
                CommandTimeout::Custom(Duration::from_millis(100)),
            )
            .await;
            assert!(matches!(result, CommandResult::Timeout));
        }
    }

    #[tokio::test]
    async fn test_convenience_functions() {
        #[cfg(unix)]
        {
            let output = run_fast("echo", &["test"]).await;
            assert!(output.is_some());
        }
    }
}
