use std::process::Stdio;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::AsyncReadExt;
use tokio::process::Command;
use tracing::{info, warn};

use crate::config::Config;
use crate::proto::CommandResult;
use crate::security::PermissionChecker;

/// Read size per chunk when draining a child pipe (bytes). Reading in bounded
/// chunks rather than one giant allocation keeps memory growth predictable for
/// large output.
const READ_CHUNK: usize = 16 * 1024;

/// Hard cap on captured stdout/stderr per command (bytes). A runaway command
/// (e.g. `cat /dev/zero`, `yes`) can produce unbounded output; without a cap the
/// agent would grow until OOM. Output beyond this is dropped and a truncation
/// notice is appended.
const MAX_CAPTURE_BYTES: usize = 1024 * 1024;

/// Drain an async reader into a byte buffer in bounded chunks, stopping once the
/// capture cap is reached. Returns the collected bytes and whether truncation
/// occurred. Continues reading (and discarding) after the cap so the child does
/// not block on a full pipe and can exit cleanly.
async fn read_capped<R>(mut reader: R) -> (Vec<u8>, bool)
where
    R: tokio::io::AsyncRead + Unpin,
{
    let mut out = Vec::new();
    let mut buf = vec![0u8; READ_CHUNK];
    let mut truncated = false;
    loop {
        match reader.read(&mut buf).await {
            Ok(0) => break, // EOF
            Ok(n) => {
                if out.len() < MAX_CAPTURE_BYTES {
                    let remaining = MAX_CAPTURE_BYTES - out.len();
                    let take = n.min(remaining);
                    out.extend_from_slice(&buf[..take]);
                    if take < n {
                        truncated = true;
                    }
                } else {
                    truncated = true;
                }
            }
            Err(_) => break,
        }
    }
    (out, truncated)
}

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

        info!(
            "Executing validated shell command ({} bytes)",
            command.len()
        );

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
    ///
    /// Output handling / PTY limitation: stdout and stderr are drained in bounded
    /// `READ_CHUNK` chunks and capped at `MAX_CAPTURE_BYTES` to keep memory bounded
    /// on runaway commands. This is NOT a real PTY and NOT a true incremental
    /// stream: the child runs without a terminal (so interactive/line-buffered
    /// tools see a pipe, not a tty) and the captured output is delivered as a
    /// SINGLE `CommandResult` once the process exits — there is no per-chunk
    /// flushing to the client mid-run. True incremental streaming would require a
    /// streaming response message in the protocol and corresponding server +
    /// shell_ws.go plumbing (see LOG_STREAM for the existing streaming pattern);
    /// that is out of scope here. The COLUMNS/LINES env vars are exported so
    /// width-aware tools still format correctly despite the absence of a PTY.
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

        // Put the shell in its own process group on Unix. Killing only the shell
        // on timeout leaves grandchildren (for example `sleep 600 & wait`)
        // running as orphaned root processes.
        #[cfg(unix)]
        cmd.process_group(0);

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
            match stdout {
                Some(s) => read_capped(s).await,
                None => (Vec::new(), false),
            }
        });
        let stderr_task = tokio::spawn(async move {
            match stderr {
                Some(s) => read_capped(s).await,
                None => (Vec::new(), false),
            }
        });

        let timeout = Duration::from_secs(timeout_secs);
        let wait_result = tokio::time::timeout(timeout, child.wait()).await;

        let (status, timed_out) = match wait_result {
            Ok(Ok(status)) => (status, false),
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
                terminate_process_group(&mut child);
                match child.wait().await {
                    Ok(status) => (status, true),
                    Err(e) => {
                        stdout_task.abort();
                        stderr_task.abort();
                        return CommandResult {
                            command_id: String::new(),
                            success: false,
                            output: String::new(),
                            error: format!(
                                "Command timed out after {timeout_secs} seconds and could not be reaped: {e}"
                            ),
                            ..Default::default()
                        };
                    }
                }
            }
        };

        let (stdout_buf, stdout_truncated) = stdout_task.await.unwrap_or_default();
        let (stderr_buf, stderr_truncated) = stderr_task.await.unwrap_or_default();

        let success = !timed_out && status.success();
        let mut error = String::from_utf8_lossy(&stderr_buf).into_owned();
        let mut output = String::from_utf8_lossy(&stdout_buf).into_owned();

        // Note when output was capped so the operator knows it is incomplete.
        if stdout_truncated {
            output.push_str(&format!(
                "\n[output truncated at {MAX_CAPTURE_BYTES} bytes]"
            ));
        }
        if stderr_truncated {
            error.push_str(&format!(
                "\n[stderr truncated at {MAX_CAPTURE_BYTES} bytes]"
            ));
        }

        // Surface the numeric exit status so callers can distinguish "command ran
        // and returned non-zero" from "command failed to run". The proto
        // CommandResult has no dedicated exit-code field yet, so we encode it in
        // the error text on failure (e.g. a grep with no matches exits 1 but may
        // print nothing to stderr). When/if the proto gains an `exit_code` field,
        // move this to a structured field and forward it via shell_ws.go.
        if timed_out {
            let timeout_message = format!("Command timed out after {timeout_secs} seconds");
            if error.is_empty() {
                error = timeout_message;
            } else {
                error = format!("{error}\n{timeout_message}");
            }
        } else if !success {
            let code = exit_code_string(&status);
            if error.is_empty() {
                error = format!("Command exited with status {code}");
            } else {
                error = format!("{error}\n(exit status {code})");
            }
        }

        CommandResult {
            command_id: String::new(),
            success,
            output,
            error,
            ..Default::default()
        }
    }
}

fn terminate_process_group(child: &mut tokio::process::Child) {
    #[cfg(unix)]
    if let Some(pid) = child.id() {
        use nix::sys::signal::{Signal, killpg};
        use nix::unistd::Pid;

        if let Ok(pid) = i32::try_from(pid) {
            let _ = killpg(Pid::from_raw(pid), Signal::SIGKILL);
        }
    }
    let _ = child.start_kill();
}

/// Render a process exit status as a stable string: the numeric exit code if the
/// process exited normally, or a `signal:N` marker on Unix when it was killed by
/// a signal (where `code()` is `None`).
fn exit_code_string(status: &std::process::ExitStatus) -> String {
    if let Some(code) = status.code() {
        return code.to_string();
    }
    #[cfg(unix)]
    {
        use std::os::unix::process::ExitStatusExt;
        if let Some(sig) = status.signal() {
            return format!("signal:{sig}");
        }
    }
    "unknown".to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn executor() -> ShellExecutor {
        ShellExecutor::new(Arc::new(Config::sample()))
    }

    #[tokio::test]
    async fn captures_stdout_stderr_and_exit_status() {
        let command = if cfg!(windows) {
            "set /p =out<nul & set /p =err<nul 1>&2 & exit /b 7"
        } else {
            "printf out; printf err >&2; exit 7"
        };
        let result = executor().run(command, 5, 0, 0).await;

        assert!(!result.success);
        assert_eq!(result.output.trim_end(), "out");
        assert!(result.error.contains("err"));
        assert!(result.error.contains("exit status 7"));
    }

    #[tokio::test]
    async fn timeout_preserves_partial_output() {
        let command = if cfg!(windows) {
            "set /p =before-timeout<nul & ping -n 6 127.0.0.1 >nul"
        } else {
            "printf before-timeout; sleep 5"
        };
        let result = executor().run(command, 1, 0, 0).await;

        assert!(!result.success);
        assert_eq!(result.output.trim_end(), "before-timeout");
        assert!(result.error.contains("timed out after 1 seconds"));
    }

    #[tokio::test]
    async fn caps_runaway_output() {
        let command = if cfg!(windows) {
            "powershell -NoProfile -NonInteractive -EncodedCommand WwBDAG8AbgBzAG8AbABlAF0AOgA6AE8AdQB0AC4AVwByAGkAdABlACgAJwB4ACcAIAAqACAAMQAxADAAMAAwADAAMAApAA=="
        } else {
            "yes x | head -c 1100000"
        };
        let result = executor().run(command, 5, 0, 0).await;

        assert!(result.success);
        assert!(
            result
                .output
                .contains("[output truncated at 1048576 bytes]")
        );
        assert!(result.output.len() < 1_049_000);
    }
}
