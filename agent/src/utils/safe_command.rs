//! Safe command execution utilities
//!
//! Provides timeout-protected subprocess execution to prevent blocking.

#![allow(dead_code)]

use std::process::{Command, Output, Stdio};
use std::time::Duration;
use tracing::warn;

/// Default timeout for subprocess commands
pub const DEFAULT_COMMAND_TIMEOUT: Duration = Duration::from_secs(5);

/// Execute a command with a timeout
///
/// Returns None if the command fails to start or times out with no output.
/// For streaming commands, partial output is returned even on timeout.
/// This prevents hanging subprocesses from blocking the async runtime.
pub fn exec_with_timeout(mut cmd: Command, timeout: Duration) -> Option<Output> {
    cmd.stdout(Stdio::piped()).stderr(Stdio::piped());

    let mut child = match cmd.spawn() {
        Ok(child) => child,
        Err(e) => {
            // Command not found or failed to start - this is fine, just return None
            if e.kind() != std::io::ErrorKind::NotFound {
                warn!("Failed to spawn command: {}", e);
            }
            return None;
        }
    };

    let start = std::time::Instant::now();

    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                // Process exited
                if status.success() {
                    // Collect output
                    let stdout = child
                        .stdout
                        .take()
                        .map(|mut s| {
                            use std::io::Read;
                            let mut buf = Vec::new();
                            let _ = s.read_to_end(&mut buf);
                            buf
                        })
                        .unwrap_or_default();

                    let stderr = child
                        .stderr
                        .take()
                        .map(|mut s| {
                            use std::io::Read;
                            let mut buf = Vec::new();
                            let _ = s.read_to_end(&mut buf);
                            buf
                        })
                        .unwrap_or_default();

                    return Some(Output {
                        status,
                        stdout,
                        stderr,
                    });
                } else {
                    return None;
                }
            }
            Ok(None) => {
                // Still running
                if start.elapsed() > timeout {
                    // Timeout - kill first, then read output
                    // This is critical: read_to_end() blocks until EOF.
                    // For streaming commands, we must kill first to close the pipe.
                    let _ = child.kill();
                    let _ = child.wait(); // Reap the zombie

                    // Now read output after process is terminated
                    let stdout = child
                        .stdout
                        .take()
                        .map(|mut s| {
                            use std::io::Read;
                            let mut buf = Vec::new();
                            let _ = s.read_to_end(&mut buf);
                            buf
                        })
                        .unwrap_or_default();

                    let stderr = child
                        .stderr
                        .take()
                        .map(|mut s| {
                            use std::io::Read;
                            let mut buf = Vec::new();
                            let _ = s.read_to_end(&mut buf);
                            buf
                        })
                        .unwrap_or_default();

                    // If we got some output, return it with a fake success status
                    // This is important for streaming commands like intel_gpu_top
                    if !stdout.is_empty() {
                        use std::os::unix::process::ExitStatusExt;
                        return Some(Output {
                            status: std::process::ExitStatus::from_raw(0),
                            stdout,
                            stderr,
                        });
                    }

                    warn!("Command timed out after {:?}, killed", timeout);
                    return None;
                }
                std::thread::sleep(Duration::from_millis(50));
            }
            Err(_) => return None,
        }
    }
}

/// Execute a command with the default timeout (5 seconds)
pub fn exec_safe(cmd: Command) -> Option<Output> {
    exec_with_timeout(cmd, DEFAULT_COMMAND_TIMEOUT)
}

/// Create a command and execute it safely with timeout
///
/// This is a convenience macro/function for the common case.
#[inline]
pub fn run_command(program: &str, args: &[&str]) -> Option<String> {
    let mut cmd = Command::new(program);
    cmd.args(args);

    exec_safe(cmd).map(|output| String::from_utf8_lossy(&output.stdout).to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_exec_safe_success() {
        #[cfg(unix)]
        {
            let result = run_command("echo", &["hello"]);
            assert!(result.is_some());
            assert!(result.unwrap().contains("hello"));
        }
        #[cfg(windows)]
        {
            let result = run_command("cmd", &["/c", "echo", "hello"]);
            assert!(result.is_some());
        }
    }

    #[test]
    fn test_exec_command_not_found() {
        let result = run_command("nonexistent_command_12345", &[]);
        assert!(result.is_none());
    }

    #[test]
    fn test_exec_timeout() {
        #[cfg(unix)]
        {
            let mut cmd = Command::new("sleep");
            cmd.arg("10");
            let result = exec_with_timeout(cmd, Duration::from_millis(100));
            assert!(result.is_none());
        }
    }
}
