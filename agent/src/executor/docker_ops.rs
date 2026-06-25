use std::process::Command;
use tracing::info;

use crate::proto::{CommandResult, ContainerInfo};
use crate::security::validation::validate_container_name;

/// Parse docker's `{{.CreatedAt}}` ("2006-01-02 15:04:05 -0700 MST") into a Unix
/// timestamp in seconds, or None when it can't be parsed.
fn parse_docker_created(s: &str) -> Option<u64> {
    let mut it = s.split_whitespace();
    let date = it.next()?;
    let time = it.next()?;
    let offset = it.next().unwrap_or("+0000");
    let dt = format!("{date} {time} {offset}");
    chrono::DateTime::parse_from_str(&dt, "%Y-%m-%d %H:%M:%S %z")
        .ok()
        .map(|d| d.timestamp().max(0) as u64)
}

/// Parse a docker size string like "12.3MiB" / "1.5GB" into bytes.
fn parse_mem_size(s: &str) -> u64 {
    let s = s.trim();
    let pos = s.find(|c: char| c.is_alphabetic()).unwrap_or(s.len());
    let (num, unit) = s.split_at(pos);
    let val: f64 = num.trim().parse().unwrap_or(0.0);
    let mult = match unit.trim().to_lowercase().as_str() {
        "b" => 1.0,
        "kb" | "kib" => 1024.0,
        "mb" | "mib" => 1024.0 * 1024.0,
        "gb" | "gib" => 1024.0 * 1024.0 * 1024.0,
        "tb" | "tib" => 1024.0 * 1024.0 * 1024.0 * 1024.0,
        _ => 1.0,
    };
    (val * mult) as u64
}

/// Collect live CPU%/memory per container via `docker stats --no-stream`,
/// keyed by short container ID. Returns (cpu_percent, mem_bytes, mem_limit_bytes).
fn container_stats() -> std::collections::HashMap<String, (f64, u64, u64)> {
    let mut out = std::collections::HashMap::new();
    if let Ok(output) = Command::new("docker")
        .args([
            "stats",
            "--no-stream",
            "--format",
            "{{.ID}}\t{{.CPUPerc}}\t{{.MemUsage}}",
        ])
        .output()
    {
        if output.status.success() {
            for line in String::from_utf8_lossy(&output.stdout).lines() {
                let parts: Vec<&str> = line.split('\t').collect();
                if parts.len() < 3 {
                    continue;
                }
                let id = parts[0].trim().to_string();
                let cpu: f64 = parts[1].trim().trim_end_matches('%').parse().unwrap_or(0.0);
                // MemUsage looks like "12.3MiB / 1GiB"
                let mut mem_it = parts[2].split('/');
                let used = mem_it.next().map(parse_mem_size).unwrap_or(0);
                let limit = mem_it.next().map(parse_mem_size).unwrap_or(0);
                out.insert(id, (cpu, used, limit));
            }
        }
    }
    out
}

/// Docker operations executor
pub struct DockerExecutor;

impl DockerExecutor {
    /// Create a new docker executor
    pub fn new() -> Self {
        Self
    }

    /// Check if Docker is available
    fn check_docker(&self) -> Result<(), String> {
        match Command::new("docker").arg("--version").output() {
            Ok(output) if output.status.success() => Ok(()),
            Ok(_) => Err("Docker command failed".to_string()),
            Err(e) => Err(format!("Docker not available: {e}")),
        }
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

    /// List all containers
    pub async fn list_containers(&self) -> CommandResult {
        if let Err(e) = self.check_docker() {
            return CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: e,
                ..Default::default()
            };
        }

        // Use docker ps -a with custom format
        match Command::new("docker")
            .args([
                "ps",
                "-a",
                "--format",
                "{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.State}}\t{{.CreatedAt}}\t{{.Ports}}\t{{.Networks}}",
            ])
            .output()
        {
            Ok(output) if output.status.success() => {
                let stdout = String::from_utf8_lossy(&output.stdout);
                // Live CPU/MEM per running container (best-effort; empty if docker stats fails).
                let stats = container_stats();
                let containers: Vec<ContainerInfo> = stdout
                    .lines()
                    .filter(|line| !line.is_empty())
                    .map(|line| {
                        let parts: Vec<&str> = line.split('\t').collect();
                        let id = parts.first().unwrap_or(&"").to_string();
                        let st = stats.get(id.as_str());
                        ContainerInfo {
                            id: id.clone(),
                            name: parts.get(1).unwrap_or(&"").to_string(),
                            image: parts.get(2).unwrap_or(&"").to_string(),
                            status: parts.get(3).unwrap_or(&"").to_string(),
                            state: parts.get(4).unwrap_or(&"").to_string(),
                            created: parts
                                .get(5)
                                .and_then(|s| parse_docker_created(s))
                                .unwrap_or(0),
                            cpu_percent: st.map(|s| s.0).unwrap_or(0.0),
                            memory_bytes: st.map(|s| s.1).unwrap_or(0),
                            memory_limit: st.map(|s| s.2).unwrap_or(0),
                            ports: parts.get(6).unwrap_or(&"").to_string(),
                            network: parts.get(7).unwrap_or(&"").to_string(),
                        }
                    })
                    .collect();

                CommandResult {
                    command_id: String::new(),
                    success: true,
                    output: format!("Found {} containers", containers.len()),
                    error: String::new(),
                    containers,
                    ..Default::default()
                }
            }
            Ok(output) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: String::from_utf8_lossy(&output.stderr).to_string(),
                ..Default::default()
            },
            Err(e) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: format!("Failed to list containers: {e}"),
                ..Default::default()
            },
        }
    }

    /// Start a container
    pub async fn start_container(&self, container: &str) -> CommandResult {
        self.execute_docker_command("start", container).await
    }

    /// Stop a container
    pub async fn stop_container(&self, container: &str) -> CommandResult {
        self.execute_docker_command("stop", container).await
    }

    /// Restart a container
    pub async fn restart_container(&self, container: &str) -> CommandResult {
        self.execute_docker_command("restart", container).await
    }

    /// Get container logs
    pub async fn container_logs(&self, container: &str, lines: usize) -> CommandResult {
        // Validate container name/ID
        if let Err(e) = validate_container_name(container) {
            return Self::error_result(e);
        }

        if let Err(e) = self.check_docker() {
            return Self::error_result(e);
        }

        info!("[AUDIT] DockerLogs: {} (last {} lines)", container, lines);

        match Command::new("docker")
            .args(["logs", "--tail", &lines.to_string(), container])
            .output()
        {
            Ok(output) => {
                // Docker logs often go to stderr
                let stdout = String::from_utf8_lossy(&output.stdout);
                let stderr = String::from_utf8_lossy(&output.stderr);
                let combined = if stdout.is_empty() {
                    stderr.to_string()
                } else if stderr.is_empty() {
                    stdout.to_string()
                } else {
                    format!("{stdout}\n{stderr}")
                };

                CommandResult {
                    command_id: String::new(),
                    success: output.status.success(),
                    output: combined,
                    error: String::new(),
                    ..Default::default()
                }
            }
            Err(e) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: format!("Failed to get container logs: {e}"),
                ..Default::default()
            },
        }
    }

    /// Execute a docker command
    async fn execute_docker_command(&self, action: &str, container: &str) -> CommandResult {
        // Validate container name/ID
        if let Err(e) = validate_container_name(container) {
            return Self::error_result(e);
        }

        if let Err(e) = self.check_docker() {
            return Self::error_result(e);
        }

        info!("[AUDIT] Docker {}: {}", action, container);

        match Command::new("docker").args([action, container]).output() {
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
                error: format!("Failed to {action} container: {e}"),
                ..Default::default()
            },
        }
    }
}

impl Default for DockerExecutor {
    fn default() -> Self {
        Self::new()
    }
}
