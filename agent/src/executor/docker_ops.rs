use std::process::Command;
use tracing::{debug, error, info};

use crate::proto::{CommandResult, ContainerInfo};

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
            Err(e) => Err(format!("Docker not available: {}", e)),
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
                file_content: vec![],
                processes: vec![],
                containers: vec![],
            };
        }

        // Use docker ps -a with custom format
        match Command::new("docker")
            .args([
                "ps",
                "-a",
                "--format",
                "{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.State}}\t{{.CreatedAt}}",
            ])
            .output()
        {
            Ok(output) if output.status.success() => {
                let stdout = String::from_utf8_lossy(&output.stdout);
                let containers: Vec<ContainerInfo> = stdout
                    .lines()
                    .filter(|line| !line.is_empty())
                    .map(|line| {
                        let parts: Vec<&str> = line.split('\t').collect();
                        ContainerInfo {
                            id: parts.get(0).unwrap_or(&"").to_string(),
                            name: parts.get(1).unwrap_or(&"").to_string(),
                            image: parts.get(2).unwrap_or(&"").to_string(),
                            status: parts.get(3).unwrap_or(&"").to_string(),
                            state: parts.get(4).unwrap_or(&"").to_string(),
                            created: 0, // Parse from parts.get(5) if needed
                        }
                    })
                    .collect();

                CommandResult {
                    command_id: String::new(),
                    success: true,
                    output: format!("Found {} containers", containers.len()),
                    error: String::new(),
                    file_content: vec![],
                    processes: vec![],
                    containers,
                }
            }
            Ok(output) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: String::from_utf8_lossy(&output.stderr).to_string(),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
            },
            Err(e) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: format!("Failed to list containers: {}", e),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
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
        if let Err(e) = self.check_docker() {
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
                    format!("{}\n{}", stdout, stderr)
                };

                CommandResult {
                    command_id: String::new(),
                    success: output.status.success(),
                    output: combined,
                    error: String::new(),
                    file_content: vec![],
                    processes: vec![],
                    containers: vec![],
                }
            }
            Err(e) => CommandResult {
                command_id: String::new(),
                success: false,
                output: String::new(),
                error: format!("Failed to get container logs: {}", e),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
            },
        }
    }

    /// Execute a docker command
    async fn execute_docker_command(&self, action: &str, container: &str) -> CommandResult {
        if let Err(e) = self.check_docker() {
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

        match Command::new("docker").args([action, container]).output() {
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
                error: format!("Failed to {} container: {}", action, e),
                file_content: vec![],
                processes: vec![],
                containers: vec![],
            },
        }
    }
}

impl Default for DockerExecutor {
    fn default() -> Self {
        Self::new()
    }
}
