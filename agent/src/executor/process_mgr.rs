use std::collections::HashMap;
use sysinfo::{Pid, System, ProcessRefreshKind, ProcessesToUpdate};
use tracing::{debug, error, info};

use crate::proto::{CommandResult, ProcessInfo};

/// Process management executor
pub struct ProcessExecutor {
    system: System,
}

impl ProcessExecutor {
    /// Create a new process executor
    pub fn new() -> Self {
        Self {
            system: System::new_all(),
        }
    }

    /// List all processes
    pub async fn list_processes(&self) -> CommandResult {
        let mut system = System::new();
        system.refresh_processes(ProcessesToUpdate::All, true);

        let processes: Vec<ProcessInfo> = system
            .processes()
            .iter()
            .map(|(pid, process)| ProcessInfo {
                pid: pid.as_u32(),
                name: process.name().to_string_lossy().to_string(),
                user: process
                    .user_id()
                    .map(|u| u.to_string())
                    .unwrap_or_default(),
                cpu_percent: process.cpu_usage() as f64,
                memory_bytes: process.memory(),
                status: format!("{:?}", process.status()),
                start_time: process.start_time(),
            })
            .collect();

        CommandResult {
            command_id: String::new(),
            success: true,
            output: format!("Found {} processes", processes.len()),
            error: String::new(),
            file_content: vec![],
            processes,
            containers: vec![],
        }
    }

    /// Kill a process by PID or name
    pub async fn kill_process(
        &self,
        target: &str,
        params: &HashMap<String, String>,
    ) -> CommandResult {
        let signal = params
            .get("signal")
            .map(|s| s.as_str())
            .unwrap_or("KILL");

        // Try to parse as PID first
        if let Ok(pid) = target.parse::<u32>() {
            return self.kill_by_pid(pid, signal).await;
        }

        // Otherwise kill by name
        self.kill_by_name(target, signal).await
    }

    /// Kill process by PID
    async fn kill_by_pid(&self, pid: u32, signal: &str) -> CommandResult {
        #[cfg(unix)]
        {
            use std::process::Command;

            let sig = match signal.to_uppercase().as_str() {
                "TERM" | "SIGTERM" | "15" => "TERM",
                "KILL" | "SIGKILL" | "9" => "KILL",
                "HUP" | "SIGHUP" | "1" => "HUP",
                "INT" | "SIGINT" | "2" => "INT",
                _ => "KILL",
            };

            match Command::new("kill")
                .args(["-s", sig, &pid.to_string()])
                .output()
            {
                Ok(output) => CommandResult {
                    command_id: String::new(),
                    success: output.status.success(),
                    output: format!("Sent {} signal to process {}", sig, pid),
                    error: String::from_utf8_lossy(&output.stderr).to_string(),
                    file_content: vec![],
                    processes: vec![],
                    containers: vec![],
                },
                Err(e) => CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: format!("Failed to kill process: {}", e),
                    file_content: vec![],
                    processes: vec![],
                    containers: vec![],
                },
            }
        }

        #[cfg(windows)]
        {
            use std::process::Command;

            match Command::new("taskkill")
                .args(["/PID", &pid.to_string(), "/F"])
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
                    error: format!("Failed to kill process: {}", e),
                    file_content: vec![],
                    processes: vec![],
                    containers: vec![],
                },
            }
        }
    }

    /// Kill process by name
    async fn kill_by_name(&self, name: &str, signal: &str) -> CommandResult {
        #[cfg(unix)]
        {
            use std::process::Command;

            let sig = match signal.to_uppercase().as_str() {
                "TERM" | "SIGTERM" | "15" => "TERM",
                "KILL" | "SIGKILL" | "9" => "KILL",
                _ => "KILL",
            };

            match Command::new("pkill")
                .args(["-", sig, name])
                .output()
            {
                Ok(output) => CommandResult {
                    command_id: String::new(),
                    success: output.status.success(),
                    output: format!("Sent {} signal to processes named '{}'", sig, name),
                    error: String::from_utf8_lossy(&output.stderr).to_string(),
                    file_content: vec![],
                    processes: vec![],
                    containers: vec![],
                },
                Err(e) => CommandResult {
                    command_id: String::new(),
                    success: false,
                    output: String::new(),
                    error: format!("Failed to kill process: {}", e),
                    file_content: vec![],
                    processes: vec![],
                    containers: vec![],
                },
            }
        }

        #[cfg(windows)]
        {
            use std::process::Command;

            match Command::new("taskkill")
                .args(["/IM", name, "/F"])
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
                    error: format!("Failed to kill process: {}", e),
                    file_content: vec![],
                    processes: vec![],
                    containers: vec![],
                },
            }
        }
    }
}

impl Default for ProcessExecutor {
    fn default() -> Self {
        Self::new()
    }
}
