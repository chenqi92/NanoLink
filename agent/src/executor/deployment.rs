use std::collections::HashMap;
use std::fs;
use std::io::{Read, Write};
use std::path::{Component, Path, PathBuf};
use std::process::{Command, ExitStatus, Stdio};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

use sha2::{Digest, Sha256};
use tracing::{info, warn};
use url::Url;
use uuid::Uuid;

use crate::config::{Config, DeploymentsConfig};
use crate::proto::CommandResult;
use crate::security::validation::validate_service_name;

const MAX_EXTRACTED_ENTRIES: usize = 100_000;
const MAX_EXTRACTED_BYTES: u64 = 2 * 1024 * 1024 * 1024;
const MAX_TOOL_OUTPUT_BYTES: u64 = 1024 * 1024;
const ARCHIVE_TOOL_TIMEOUT: Duration = Duration::from_secs(120);
const SERVICE_TOOL_TIMEOUT: Duration = Duration::from_secs(60);

struct ToolOutput {
    status: ExitStatus,
    stdout: Vec<u8>,
    stderr: Vec<u8>,
}

fn run_tool(command: &mut Command, timeout: Duration) -> Result<ToolOutput, String> {
    command.stdout(Stdio::piped()).stderr(Stdio::piped());
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        command.process_group(0);
    }
    let mut child = command
        .spawn()
        .map_err(|e| format!("Failed to start deployment tool: {e}"))?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| "Deployment tool stdout was not captured".to_string())?;
    let stderr = child
        .stderr
        .take()
        .ok_or_else(|| "Deployment tool stderr was not captured".to_string())?;
    let stdout_task = thread::spawn(move || {
        let mut bytes = Vec::new();
        let _ = stdout
            .take(MAX_TOOL_OUTPUT_BYTES + 1)
            .read_to_end(&mut bytes);
        bytes.truncate(MAX_TOOL_OUTPUT_BYTES as usize);
        bytes
    });
    let stderr_task = thread::spawn(move || {
        let mut bytes = Vec::new();
        let _ = stderr
            .take(MAX_TOOL_OUTPUT_BYTES + 1)
            .read_to_end(&mut bytes);
        bytes.truncate(MAX_TOOL_OUTPUT_BYTES as usize);
        bytes
    });

    let started = Instant::now();
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) if started.elapsed() < timeout => thread::sleep(Duration::from_millis(25)),
            Ok(None) => {
                terminate_tool_process_group(&mut child);
                let _ = child.wait();
                let _ = stdout_task.join();
                let stderr = stderr_task.join().unwrap_or_default();
                let detail = String::from_utf8_lossy(&stderr);
                return Err(format!(
                    "Deployment tool timed out after {} seconds{}{}",
                    timeout.as_secs(),
                    if detail.trim().is_empty() { "" } else { ": " },
                    detail.trim()
                ));
            }
            Err(e) => {
                terminate_tool_process_group(&mut child);
                let _ = child.wait();
                let _ = stdout_task.join();
                let _ = stderr_task.join();
                return Err(format!("Failed to wait for deployment tool: {e}"));
            }
        }
    };
    let stdout = stdout_task.join().unwrap_or_default();
    let stderr = stderr_task.join().unwrap_or_default();
    Ok(ToolOutput {
        status,
        stdout,
        stderr,
    })
}

fn terminate_tool_process_group(child: &mut std::process::Child) {
    #[cfg(unix)]
    {
        use nix::sys::signal::{Signal, killpg};
        use nix::unistd::Pid;

        if let Ok(pid) = i32::try_from(child.id()) {
            let _ = killpg(Pid::from_raw(pid), Signal::SIGKILL);
        }
    }
    let _ = child.kill();
}

pub struct DeploymentExecutor {
    config: Arc<Config>,
}

#[derive(Clone)]
struct DeploymentRequest {
    project_type: String,
    version: String,
    deploy_path: PathBuf,
    service_name: String,
    health_url: String,
    keep_releases: usize,
    artifact_url: Option<String>,
    artifact_sha256: Option<String>,
    artifact_size: Option<u64>,
    artifact_name: Option<String>,
    extract_artifact: bool,
    strip_top_level: bool,
    log_update_url: String,
}

impl DeploymentExecutor {
    pub fn new(config: Arc<Config>) -> Self {
        Self { config }
    }

    pub async fn deploy(&self, params: &HashMap<String, String>) -> CommandResult {
        let cfg = self.config.deployments.clone();
        let params = params.clone();
        let result = tokio::task::spawn_blocking(move || deploy_sync(&cfg, &params)).await;
        command_result(result)
    }

    pub async fn rollback(&self, params: &HashMap<String, String>) -> CommandResult {
        let cfg = self.config.deployments.clone();
        let params = params.clone();
        let result = tokio::task::spawn_blocking(move || rollback_sync(&cfg, &params)).await;
        command_result(result)
    }
}

fn command_result(
    result: Result<Result<Vec<String>, (Vec<String>, String)>, tokio::task::JoinError>,
) -> CommandResult {
    match result {
        Ok(Ok(lines)) => CommandResult {
            command_id: String::new(),
            success: true,
            output: lines.join("\n"),
            error: String::new(),
            ..Default::default()
        },
        Ok(Err((lines, error))) => CommandResult {
            command_id: String::new(),
            success: false,
            output: lines.join("\n"),
            error,
            ..Default::default()
        },
        Err(error) => CommandResult {
            command_id: String::new(),
            success: false,
            output: String::new(),
            error: format!("Deployment worker failed: {error}"),
            ..Default::default()
        },
    }
}

fn deploy_sync(
    cfg: &DeploymentsConfig,
    params: &HashMap<String, String>,
) -> Result<Vec<String>, (Vec<String>, String)> {
    let mut logs = Vec::new();
    let req = parse_request(cfg, params, true).map_err(|e| (logs.clone(), e))?;
    logs.push(format!(
        "[done] preflight {} {}",
        req.project_type, req.version
    ));
    send_log_update(&req, &logs);

    let releases = req.deploy_path.join("releases");
    if let Err(e) = fs::create_dir_all(&releases) {
        return fail_with_update(
            &req,
            logs,
            format!("Failed to create releases directory: {e}"),
        );
    }
    if let Err(error) = validate_deploy_path(cfg, &req.deploy_path)
        .and_then(|_| validate_directory_without_links(&releases))
    {
        return fail_with_update(&req, logs, error);
    }
    let release_path = releases.join(&req.version);
    if release_path.exists() {
        return fail_with_update(
            &req,
            logs,
            format!("Release {} already exists", req.version),
        );
    }
    let stage = releases.join(format!(".staging-{}", Uuid::new_v4()));
    if let Err(e) = fs::create_dir(&stage) {
        return fail_with_update(
            &req,
            logs,
            format!("Failed to create staging directory: {e}"),
        );
    }

    let artifact_name = req.artifact_name.as_deref().unwrap_or("artifact");
    let artifact_path = releases.join(format!(".artifact-{}", Uuid::new_v4()));
    let prepare = (|| -> Result<(), String> {
        download_artifact(
            cfg,
            req.artifact_url.as_deref().unwrap_or_default(),
            &artifact_path,
        )?;
        logs.push(format!(
            "[done] download {} bytes",
            fs::metadata(&artifact_path).map(|m| m.len()).unwrap_or(0)
        ));
        send_log_update(&req, &logs);
        verify_artifact(
            &artifact_path,
            req.artifact_size.unwrap_or_default(),
            req.artifact_sha256.as_deref().unwrap_or_default(),
        )?;
        logs.push("[done] verify sha256".to_string());
        send_log_update(&req, &logs);

        if req.project_type == "java" {
            fs::rename(&artifact_path, stage.join("app.jar"))
                .map_err(|e| format!("Failed to stage JAR: {e}"))?;
        } else if !req.extract_artifact {
            fs::rename(&artifact_path, stage.join(artifact_name))
                .map_err(|e| format!("Failed to stage static artifact: {e}"))?;
        } else {
            validate_archive_entries(&artifact_path, artifact_name)?;
            extract_archive(&artifact_path, artifact_name, &stage)?;
            validate_extracted_tree(&stage, cfg.max_artifact_size)?;
            fs::remove_file(&artifact_path)
                .map_err(|e| format!("Failed to remove staged archive: {e}"))?;
            if req.strip_top_level {
                strip_single_top_level(&stage)?;
                validate_extracted_tree(&stage, cfg.max_artifact_size)?;
            }
        }
        fs::rename(&stage, &release_path)
            .map_err(|e| format!("Failed to finalize release: {e}"))?;
        Ok(())
    })();
    if let Err(error) = prepare {
        let _ = fs::remove_file(&artifact_path);
        let _ = fs::remove_dir_all(&stage);
        return fail_with_update(&req, logs, error);
    }
    logs.push(format!("[done] stage {}", release_path.display()));
    send_log_update(&req, &logs);

    let previous = match activate_release(&req.deploy_path, &release_path) {
        Ok(previous) => previous,
        Err(error) => {
            remove_failed_release(&release_path, &mut logs);
            return fail_with_update(&req, logs, error);
        }
    };
    logs.push(format!("[done] activate {}", req.version));
    send_log_update(&req, &logs);

    if let Err(error) = restart_or_reload(&req) {
        if restore_previous(&req, previous.as_deref(), &mut logs) {
            remove_failed_release(&release_path, &mut logs);
        }
        return fail_with_update(&req, logs, error);
    }
    logs.push(format!("[done] service {}", service_action_label(&req)));
    send_log_update(&req, &logs);

    if let Err(error) = check_health(&req.health_url) {
        if restore_previous(&req, previous.as_deref(), &mut logs) {
            remove_failed_release(&release_path, &mut logs);
        }
        return fail_with_update(&req, logs, error);
    }
    logs.push(if req.health_url.is_empty() {
        "[done] health check skipped".to_string()
    } else {
        "[done] health check passed".to_string()
    });
    send_log_update(&req, &logs);

    if let Err(error) = prune_releases(&releases, &release_path, req.keep_releases) {
        warn!("Release cleanup failed: {}", error);
        logs.push(format!("[warn] cleanup: {error}"));
    } else {
        logs.push(format!(
            "[done] retain latest {} releases",
            req.keep_releases
        ));
    }
    info!("Deployment completed: {}", release_path.display());
    send_log_update(&req, &logs);
    Ok(logs)
}

fn rollback_sync(
    cfg: &DeploymentsConfig,
    params: &HashMap<String, String>,
) -> Result<Vec<String>, (Vec<String>, String)> {
    let mut logs = Vec::new();
    let req = parse_request(cfg, params, false).map_err(|e| (logs.clone(), e))?;
    logs.push(format!("[done] preflight rollback {}", req.version));
    let release_path = req.deploy_path.join("releases").join(&req.version);
    if !release_path.is_dir()
        || fs::symlink_metadata(&release_path)
            .is_ok_and(|metadata| metadata.file_type().is_symlink())
    {
        return fail(
            logs,
            format!("Release {} is not present on this agent", req.version),
        );
    }
    let previous = match activate_release(&req.deploy_path, &release_path) {
        Ok(previous) => previous,
        Err(error) => return fail(logs, error),
    };
    logs.push(format!("[done] activate {}", req.version));
    if let Err(error) = restart_or_reload(&req) {
        let _ = restore_previous(&req, previous.as_deref(), &mut logs);
        return fail(logs, error);
    }
    logs.push(format!("[done] service {}", service_action_label(&req)));
    if let Err(error) = check_health(&req.health_url) {
        let _ = restore_previous(&req, previous.as_deref(), &mut logs);
        return fail(logs, error);
    }
    logs.push(if req.health_url.is_empty() {
        "[done] health check skipped".to_string()
    } else {
        "[done] health check passed".to_string()
    });
    info!("Rollback completed: {}", release_path.display());
    Ok(logs)
}

fn parse_request(
    cfg: &DeploymentsConfig,
    params: &HashMap<String, String>,
    require_artifact: bool,
) -> Result<DeploymentRequest, String> {
    if !cfg.enabled {
        return Err("Application deployment is disabled in agent configuration".to_string());
    }
    let project_type = required(params, "project_type")?.to_lowercase();
    if project_type != "java" && project_type != "static" {
        return Err("project_type must be java or static".to_string());
    }
    let version = required(params, "version")?;
    if version.len() > 64
        || !version
            .chars()
            .enumerate()
            .all(|(i, c)| c.is_ascii_alphanumeric() || (i > 0 && matches!(c, '.' | '_' | '-')))
    {
        return Err("Invalid release version".to_string());
    }
    let deploy_path = PathBuf::from(required(params, "deploy_path")?);
    validate_deploy_path(cfg, &deploy_path)?;
    let service_name = params
        .get("service_name")
        .map(|s| s.trim().to_string())
        .unwrap_or_default();
    if project_type == "java" && service_name.is_empty() {
        return Err("service_name is required for Java deployments".to_string());
    }
    if !service_name.is_empty() {
        validate_service_name(&service_name)?;
    }
    let health_url = params
        .get("health_url")
        .map(|s| s.trim().to_string())
        .unwrap_or_default();
    if !health_url.is_empty() {
        validate_http_url(&health_url)?;
    }
    let keep_releases = params
        .get("keep_releases")
        .and_then(|s| s.parse::<usize>().ok())
        .unwrap_or(5)
        .clamp(2, 50);
    let extract_artifact = extract_artifact_flag(params)?;
    let strip_top_level = optional_bool(params, "strip_top_level", false)?;
    if project_type == "java" && (!extract_artifact || strip_top_level) {
        return Err(
            "extract_artifact/strip_top_level are only configurable for static deployments"
                .to_string(),
        );
    }
    if strip_top_level && !extract_artifact {
        return Err("strip_top_level requires extract_artifact=true".to_string());
    }

    let (artifact_url, artifact_sha256, artifact_size, artifact_name) = if require_artifact {
        let url = required(params, "artifact_url")?;
        validate_http_url(&url)?;
        let checksum = required(params, "artifact_sha256")?.to_lowercase();
        if checksum.len() != 64 || !checksum.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err("Invalid artifact SHA-256".to_string());
        }
        let size = required(params, "artifact_size")?
            .parse::<u64>()
            .map_err(|_| "Invalid artifact size".to_string())?;
        if size == 0 || size > cfg.max_artifact_size {
            return Err("Artifact size exceeds the configured limit".to_string());
        }
        let name = required(params, "artifact_name")?;
        validate_artifact_name(&project_type, &name)?;
        (Some(url), Some(checksum), Some(size), Some(name))
    } else {
        (None, None, None, None)
    };
    let log_update_url = params
        .get("log_update_url")
        .map(|value| value.trim().to_string())
        .unwrap_or_default();
    if require_artifact && !log_update_url.is_empty() {
        validate_http_url(&log_update_url)?;
    }

    Ok(DeploymentRequest {
        project_type,
        version,
        deploy_path,
        service_name,
        health_url,
        keep_releases,
        artifact_url,
        artifact_sha256,
        artifact_size,
        artifact_name,
        extract_artifact,
        strip_top_level,
        log_update_url,
    })
}

fn required(params: &HashMap<String, String>, name: &str) -> Result<String, String> {
    params
        .get(name)
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty())
        .ok_or_else(|| format!("Missing deployment parameter: {name}"))
}

fn optional_bool(
    params: &HashMap<String, String>,
    name: &str,
    default: bool,
) -> Result<bool, String> {
    match params
        .get(name)
        .map(|value| value.trim().to_ascii_lowercase())
    {
        None => Ok(default),
        Some(value) if matches!(value.as_str(), "true" | "1" | "yes") => Ok(true),
        Some(value) if matches!(value.as_str(), "false" | "0" | "no") => Ok(false),
        Some(_) => Err(format!("Invalid boolean deployment parameter: {name}")),
    }
}

fn extract_artifact_flag(params: &HashMap<String, String>) -> Result<bool, String> {
    if params.contains_key("extract_artifact") {
        optional_bool(params, "extract_artifact", true)
    } else if params.contains_key("extract") {
        optional_bool(params, "extract", true)
    } else {
        optional_bool(params, "extract_archive", true)
    }
}

fn validate_deploy_path(cfg: &DeploymentsConfig, target: &Path) -> Result<(), String> {
    if !target.is_absolute()
        || target
            .components()
            .any(|c| matches!(c, Component::ParentDir | Component::CurDir))
    {
        return Err("Deployment path must be a normalized absolute path".to_string());
    }
    for raw_root in &cfg.allowed_roots {
        let root = Path::new(raw_root);
        if !root.is_absolute() || !target.starts_with(root) || target == root {
            continue;
        }
        validate_directory_without_links(root).map_err(|error| {
            format!(
                "Deployment allowed root {} is unsafe: {error}",
                root.display()
            )
        })?;

        let mut current = root.to_path_buf();
        if let Ok(relative) = target.strip_prefix(root) {
            for component in relative.components() {
                current.push(component.as_os_str());
                match fs::symlink_metadata(&current) {
                    Ok(metadata) if metadata.file_type().is_symlink() => {
                        return Err(format!(
                            "Deployment path contains a symbolic link: {}",
                            current.display()
                        ));
                    }
                    Ok(metadata) if !metadata.is_dir() => {
                        return Err(format!(
                            "Deployment path component is not a directory: {}",
                            current.display()
                        ));
                    }
                    Ok(_) => {}
                    Err(error) if error.kind() == std::io::ErrorKind::NotFound => break,
                    Err(error) => {
                        return Err(format!(
                            "Failed to inspect deployment path {}: {error}",
                            current.display()
                        ));
                    }
                }
            }
        }
        return Ok(());
    }
    Err("Deployment path is outside deployments.allowed_roots".to_string())
}

fn validate_directory_without_links(path: &Path) -> Result<(), String> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|e| format!("Failed to inspect directory {}: {e}", path.display()))?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        return Err(format!(
            "Directory must exist and must not be a symbolic link: {}",
            path.display()
        ));
    }
    Ok(())
}

fn validate_http_url(raw: &str) -> Result<(), String> {
    let parsed = Url::parse(raw).map_err(|_| "Invalid HTTP URL".to_string())?;
    if !matches!(parsed.scheme(), "http" | "https")
        || parsed.host_str().is_none()
        || !parsed.username().is_empty()
        || parsed.password().is_some()
    {
        return Err(
            "Only absolute HTTP(S) URLs without embedded credentials are allowed".to_string(),
        );
    }
    Ok(())
}

fn validate_artifact_name(project_type: &str, name: &str) -> Result<(), String> {
    let lower = name.to_lowercase();
    if Path::new(name).file_name().and_then(|v| v.to_str()) != Some(name) {
        return Err("Invalid artifact name".to_string());
    }
    if project_type == "java" && !lower.ends_with(".jar") {
        return Err("Java deployments require a .jar artifact".to_string());
    }
    if project_type == "static"
        && !lower.ends_with(".zip")
        && !lower.ends_with(".tar")
        && !lower.ends_with(".tar.gz")
        && !lower.ends_with(".tgz")
    {
        return Err(
            "Static deployments require a .zip, .tar, .tar.gz, or .tgz artifact".to_string(),
        );
    }
    Ok(())
}

fn download_artifact(cfg: &DeploymentsConfig, url: &str, dest: &Path) -> Result<(), String> {
    let dest = dest
        .to_str()
        .ok_or_else(|| "Artifact path is not valid UTF-8".to_string())?;
    #[cfg(unix)]
    let output = run_tool(
        Command::new("curl").args([
            "-fL",
            "--silent",
            "--show-error",
            "--connect-timeout",
            "15",
            "--max-filesize",
            &cfg.max_artifact_size.to_string(),
            "--max-time",
            &cfg.timeout_seconds.to_string(),
            "-o",
            dest,
            url,
        ]),
        Duration::from_secs(cfg.timeout_seconds),
    )?;

    #[cfg(windows)]
    let output = run_tool(
        Command::new("powershell").args([
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri $args[0] -OutFile $args[1]",
            url,
            dest,
        ]),
        Duration::from_secs(cfg.timeout_seconds),
    )?;

    if !output.status.success() {
        return Err(format!(
            "Artifact download failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    let size = fs::metadata(dest)
        .map_err(|e| format!("Failed to inspect downloaded artifact: {e}"))?
        .len();
    if size == 0 || size > cfg.max_artifact_size {
        let _ = fs::remove_file(dest);
        return Err("Downloaded artifact exceeds the configured limit".to_string());
    }
    Ok(())
}

fn verify_artifact(path: &Path, expected_size: u64, expected_hash: &str) -> Result<(), String> {
    let mut file = fs::File::open(path).map_err(|e| format!("Failed to open artifact: {e}"))?;
    let size = file
        .metadata()
        .map_err(|e| format!("Failed to inspect artifact: {e}"))?
        .len();
    if size != expected_size {
        return Err(format!(
            "Artifact size mismatch: expected {expected_size}, received {size}"
        ));
    }
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 64 * 1024];
    loop {
        let read = file
            .read(&mut buffer)
            .map_err(|e| format!("Failed to hash artifact: {e}"))?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    let actual = format!("{:x}", hasher.finalize());
    if actual != expected_hash {
        return Err("Artifact SHA-256 mismatch".to_string());
    }
    Ok(())
}

fn validate_archive_entries(artifact: &Path, name: &str) -> Result<(), String> {
    #[cfg(not(unix))]
    {
        let _ = (artifact, name);
        return Err("Static archive deployment is currently supported on Unix agents".to_string());
    }
    #[cfg(unix)]
    {
        let output = if name.to_lowercase().ends_with(".zip") {
            run_tool(
                Command::new("unzip").args(["-Z1"]).arg(artifact),
                ARCHIVE_TOOL_TIMEOUT,
            )
        } else if name.to_lowercase().ends_with(".tar") {
            run_tool(
                Command::new("tar").args(["-tf"]).arg(artifact),
                ARCHIVE_TOOL_TIMEOUT,
            )
        } else {
            run_tool(
                Command::new("tar").args(["-tzf"]).arg(artifact),
                ARCHIVE_TOOL_TIMEOUT,
            )
        }
        .map_err(|e| format!("Failed to inspect archive: {e}"))?;
        if !output.status.success() {
            return Err(format!(
                "Archive inspection failed: {}",
                String::from_utf8_lossy(&output.stderr).trim()
            ));
        }
        for line in String::from_utf8_lossy(&output.stdout).lines() {
            let entry = Path::new(line);
            if entry.is_absolute()
                || entry.components().any(|c| {
                    matches!(
                        c,
                        Component::ParentDir | Component::RootDir | Component::Prefix(_)
                    )
                })
            {
                return Err(format!("Archive contains unsafe path: {line}"));
            }
        }
        Ok(())
    }
}

fn extract_archive(artifact: &Path, name: &str, stage: &Path) -> Result<(), String> {
    #[cfg(not(unix))]
    {
        let _ = (artifact, name, stage);
        return Err("Static archive deployment is currently supported on Unix agents".to_string());
    }
    #[cfg(unix)]
    {
        let output = if name.to_lowercase().ends_with(".zip") {
            run_tool(
                Command::new("unzip")
                    .arg("-q")
                    .arg(artifact)
                    .arg("-d")
                    .arg(stage),
                ARCHIVE_TOOL_TIMEOUT,
            )
        } else if name.to_lowercase().ends_with(".tar") {
            run_tool(
                Command::new("tar")
                    .arg("--extract")
                    .arg("--file")
                    .arg(artifact)
                    .arg("--directory")
                    .arg(stage)
                    .arg("--no-same-owner")
                    .arg("--no-same-permissions"),
                ARCHIVE_TOOL_TIMEOUT,
            )
        } else {
            run_tool(
                Command::new("tar")
                    .arg("--extract")
                    .arg("--gzip")
                    .arg("--file")
                    .arg(artifact)
                    .arg("--directory")
                    .arg(stage)
                    .arg("--no-same-owner")
                    .arg("--no-same-permissions"),
                ARCHIVE_TOOL_TIMEOUT,
            )
        }
        .map_err(|e| format!("Failed to extract archive: {e}"))?;
        if !output.status.success() {
            return Err(format!(
                "Artifact extraction failed: {}",
                String::from_utf8_lossy(&output.stderr).trim()
            ));
        }
        Ok(())
    }
}

fn validate_extracted_tree(root: &Path, compressed_limit: u64) -> Result<(), String> {
    let mut pending = vec![root.to_path_buf()];
    let mut entries = 0usize;
    let mut total_bytes = 0u64;
    let byte_limit = compressed_limit.saturating_mul(10).min(MAX_EXTRACTED_BYTES);
    while let Some(directory) = pending.pop() {
        for entry in fs::read_dir(&directory)
            .map_err(|e| format!("Failed to validate extracted content: {e}"))?
        {
            let entry = entry.map_err(|e| format!("Failed to validate extracted content: {e}"))?;
            let metadata = fs::symlink_metadata(entry.path())
                .map_err(|e| format!("Failed to validate extracted content: {e}"))?;
            entries = entries.saturating_add(1);
            if entries > MAX_EXTRACTED_ENTRIES {
                return Err(format!(
                    "Archive expands to more than {MAX_EXTRACTED_ENTRIES} entries"
                ));
            }
            if metadata.file_type().is_symlink() {
                return Err(format!(
                    "Archive links are not allowed: {}",
                    entry.path().display()
                ));
            }
            if metadata.is_dir() {
                pending.push(entry.path());
            } else if metadata.is_file() {
                total_bytes = total_bytes.saturating_add(metadata.len());
                if total_bytes > byte_limit {
                    return Err(format!(
                        "Archive expands beyond the configured limit ({byte_limit} bytes)"
                    ));
                }
            } else {
                return Err(format!(
                    "Archive contains a special file: {}",
                    entry.path().display()
                ));
            }
        }
    }
    Ok(())
}

fn strip_single_top_level(stage: &Path) -> Result<(), String> {
    let entries = fs::read_dir(stage)
        .map_err(|e| format!("Failed to inspect extracted top-level directory: {e}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Failed to inspect extracted top-level directory: {e}"))?;
    if entries.len() != 1 {
        return Err(
            "strip_top_level requires the archive to contain exactly one top-level directory"
                .to_string(),
        );
    }
    let top = entries[0].path();
    let metadata = fs::symlink_metadata(&top)
        .map_err(|e| format!("Failed to inspect extracted top-level entry: {e}"))?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        return Err(
            "strip_top_level requires the archive to contain exactly one top-level directory"
                .to_string(),
        );
    }
    let children = fs::read_dir(&top)
        .map_err(|e| format!("Failed to read extracted top-level directory: {e}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Failed to read extracted top-level directory: {e}"))?;
    for child in children {
        let destination = stage.join(child.file_name());
        fs::rename(child.path(), &destination).map_err(|e| {
            format!(
                "Failed to strip top-level directory into {}: {e}",
                destination.display()
            )
        })?;
    }
    fs::remove_dir(&top).map_err(|e| format!("Failed to remove top-level directory: {e}"))?;
    Ok(())
}

#[cfg(unix)]
fn activate_release(deploy_path: &Path, release_path: &Path) -> Result<Option<PathBuf>, String> {
    use std::os::unix::fs::symlink;

    validate_directory_without_links(release_path)?;
    let releases = deploy_path.join("releases");
    let releases = fs::canonicalize(&releases)
        .map_err(|e| format!("Failed to resolve releases directory: {e}"))?;
    let release = fs::canonicalize(release_path)
        .map_err(|e| format!("Failed to resolve release directory: {e}"))?;
    if !release.starts_with(&releases) || release == releases {
        return Err("Release path escapes the deployment releases directory".to_string());
    }

    let current = deploy_path.join("current");
    let previous = fs::read_link(&current).ok();
    match fs::symlink_metadata(&current) {
        Ok(metadata) if !metadata.file_type().is_symlink() => {
            return Err("Deployment current path exists but is not a symbolic link".to_string());
        }
        Ok(_) => {}
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(format!("Failed to inspect current release link: {error}")),
    }
    if let Some(previous_path) = previous.as_deref() {
        let candidate = if previous_path.is_absolute() {
            previous_path.to_path_buf()
        } else {
            deploy_path.join(previous_path)
        };
        let resolved = fs::canonicalize(&candidate)
            .map_err(|e| format!("Current release link is invalid: {e}"))?;
        if !resolved.starts_with(&releases) || resolved == releases {
            return Err(
                "Current release link escapes the deployment releases directory".to_string(),
            );
        }
    }
    let next = deploy_path.join(format!(".current-{}", Uuid::new_v4()));
    symlink(release_path, &next).map_err(|e| format!("Failed to create release link: {e}"))?;
    if let Err(e) = fs::rename(&next, &current) {
        let _ = fs::remove_file(&next);
        return Err(format!("Failed to atomically activate release: {e}"));
    }
    Ok(previous)
}

#[cfg(not(unix))]
fn activate_release(_deploy_path: &Path, _release_path: &Path) -> Result<Option<PathBuf>, String> {
    Err("Atomic application activation is currently supported on Unix agents".to_string())
}

fn restart_or_reload(req: &DeploymentRequest) -> Result<(), String> {
    if req.service_name.is_empty() {
        return Ok(());
    }
    #[cfg(not(unix))]
    return Err("Deployment service activation is currently supported on Unix agents".to_string());
    #[cfg(unix)]
    {
        if req.project_type == "static" && req.service_name.to_lowercase().starts_with("nginx") {
            let test = run_tool(Command::new("nginx").arg("-t"), SERVICE_TOOL_TIMEOUT)
                .map_err(|e| format!("Failed to validate nginx config: {e}"))?;
            if !test.status.success() {
                return Err(format!(
                    "nginx -t failed: {}",
                    String::from_utf8_lossy(&test.stderr).trim()
                ));
            }
        }
        let action = if req.project_type == "static" {
            "reload"
        } else {
            "restart"
        };
        let output = run_tool(
            Command::new("systemctl").args([action, "--", &req.service_name]),
            SERVICE_TOOL_TIMEOUT,
        )
        .map_err(|e| format!("Failed to run systemctl: {e}"))?;
        if !output.status.success() {
            return Err(format!(
                "systemctl {action} failed: {}",
                String::from_utf8_lossy(&output.stderr).trim()
            ));
        }
        Ok(())
    }
}

fn service_action_label(req: &DeploymentRequest) -> &'static str {
    if req.service_name.is_empty() {
        "skipped"
    } else if req.project_type == "static" {
        "reloaded"
    } else {
        "restarted"
    }
}

fn check_health(url: &str) -> Result<(), String> {
    if url.is_empty() {
        return Ok(());
    }
    for attempt in 1..=10 {
        let status = run_tool(
            Command::new("curl").args(["-fsS", "--connect-timeout", "3", "--max-time", "10", url]),
            Duration::from_secs(12),
        );
        if status.is_ok_and(|output| output.status.success()) {
            return Ok(());
        }
        if attempt < 10 {
            thread::sleep(Duration::from_secs(2));
        }
    }
    Err(format!("Health check failed after 10 attempts: {url}"))
}

fn restore_previous(
    req: &DeploymentRequest,
    previous: Option<&Path>,
    logs: &mut Vec<String>,
) -> bool {
    let Some(previous) = previous else {
        let current = req.deploy_path.join("current");
        return match fs::remove_file(&current) {
            Ok(()) => {
                logs.push("[done] automatic rollback cleared first activation".to_string());
                true
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                logs.push("[done] automatic rollback found no active release".to_string());
                true
            }
            Err(error) => {
                logs.push(format!(
                    "[warn] automatic rollback could not clear activation: {error}"
                ));
                false
            }
        };
    };
    match activate_release(&req.deploy_path, previous) {
        Ok(_) => {
            let restart = restart_or_reload(req);
            if let Err(error) = restart {
                logs.push(format!(
                    "[warn] previous release restored but service failed: {error}"
                ));
            } else {
                logs.push("[done] automatic rollback restored previous release".to_string());
            }
            true
        }
        Err(error) => {
            logs.push(format!("[warn] automatic rollback failed: {error}"));
            false
        }
    }
}

fn remove_failed_release(release_path: &Path, logs: &mut Vec<String>) {
    match fs::remove_dir_all(release_path) {
        Ok(()) => logs.push("[done] removed failed release for safe retry".to_string()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => logs.push(format!("[warn] failed release cleanup: {error}")),
    }
}

fn prune_releases(releases: &Path, current: &Path, keep: usize) -> Result<(), String> {
    let mut entries = fs::read_dir(releases)
        .map_err(|e| format!("Failed to list releases: {e}"))?
        .filter_map(Result::ok)
        .filter(|e| e.file_type().is_ok_and(|t| t.is_dir() && !t.is_symlink()))
        .filter(|e| e.path() != current)
        .collect::<Vec<_>>();
    entries.sort_by_key(|e| {
        std::cmp::Reverse(
            e.metadata()
                .and_then(|m| m.modified())
                .unwrap_or(std::time::SystemTime::UNIX_EPOCH),
        )
    });
    for entry in entries.into_iter().skip(keep.saturating_sub(1)) {
        fs::remove_dir_all(entry.path()).map_err(|e| {
            format!(
                "Failed to remove old release {}: {e}",
                entry.path().display()
            )
        })?;
    }
    Ok(())
}

fn fail<T>(logs: Vec<String>, error: String) -> Result<T, (Vec<String>, String)> {
    Err((logs, error))
}

fn fail_with_update<T>(
    req: &DeploymentRequest,
    mut logs: Vec<String>,
    error: String,
) -> Result<T, (Vec<String>, String)> {
    logs.push(format!("[error] {error}"));
    send_log_update(req, &logs);
    Err((logs, error))
}

fn send_log_update(req: &DeploymentRequest, logs: &[String]) {
    if req.log_update_url.is_empty() {
        return;
    }
    let mut body = logs.join("\n");
    const MAX_LOG: usize = 256 * 1024;
    if body.len() > MAX_LOG {
        let mut boundary = MAX_LOG;
        while boundary > 0 && !body.is_char_boundary(boundary) {
            boundary -= 1;
        }
        body.truncate(boundary);
    }
    let mut command = if cfg!(windows) {
        let mut cmd = Command::new("powershell");
        cmd.args([
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "$body=[Console]::In.ReadToEnd(); Invoke-WebRequest -Method Put -ContentType 'text/plain' -Body $body -TimeoutSec 5 -Uri $args[0] | Out-Null",
            &req.log_update_url,
        ]);
        cmd
    } else {
        let mut cmd = Command::new("curl");
        cmd.args([
            "-f",
            "--silent",
            "--show-error",
            "--connect-timeout",
            "2",
            "--max-time",
            "5",
            "-X",
            "PUT",
            "-H",
            "Content-Type: text/plain; charset=utf-8",
            "--data-binary",
            "@-",
            &req.log_update_url,
        ]);
        cmd
    };
    command
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    if let Ok(mut child) = command.spawn() {
        if let Some(mut stdin) = child.stdin.take() {
            let _ = stdin.write_all(body.as_bytes());
        }
        let _ = child.wait();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deploy_path_must_be_below_an_allowed_root() {
        let base = std::env::temp_dir().join(format!("nanolink-deploy-test-{}", Uuid::new_v4()));
        let root = base.join("apps");
        let target = root.join("demo");
        let sibling = base.join("apps2").join("demo");
        fs::create_dir_all(&root).unwrap();
        let cfg = DeploymentsConfig {
            enabled: true,
            allowed_roots: vec![root.to_string_lossy().into_owned()],
            max_artifact_size: 1024,
            timeout_seconds: 30,
        };
        assert!(validate_deploy_path(&cfg, &target).is_ok());
        assert!(validate_deploy_path(&cfg, &sibling).is_err());
        assert!(validate_deploy_path(&cfg, &root).is_err());
        fs::remove_dir_all(base).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn deploy_path_rejects_symlink_escape() {
        use std::os::unix::fs::symlink;

        let base = std::env::temp_dir().join(format!("nanolink-deploy-link-{}", Uuid::new_v4()));
        let root = base.join("apps");
        let outside = base.join("outside");
        fs::create_dir_all(&root).unwrap();
        fs::create_dir_all(&outside).unwrap();
        symlink(&outside, root.join("linked")).unwrap();
        let cfg = DeploymentsConfig {
            enabled: true,
            allowed_roots: vec![root.to_string_lossy().into_owned()],
            max_artifact_size: 1024,
            timeout_seconds: 30,
        };

        let error = validate_deploy_path(&cfg, &root.join("linked/app")).unwrap_err();
        assert!(error.contains("symbolic link"));
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn extracted_tree_enforces_expanded_size_limit() {
        let root = std::env::temp_dir().join(format!("nanolink-expand-test-{}", Uuid::new_v4()));
        fs::create_dir_all(&root).unwrap();
        fs::write(root.join("large.bin"), vec![0u8; 32]).unwrap();

        assert!(validate_extracted_tree(&root, 4).is_ok());
        assert!(validate_extracted_tree(&root, 3).is_err());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn deployment_extract_flags_are_backward_compatible() {
        let params = HashMap::new();
        assert!(extract_artifact_flag(&params).unwrap());
        assert!(!optional_bool(&params, "strip_top_level", false).unwrap());

        let legacy = HashMap::from([("extract".to_string(), "false".to_string())]);
        assert!(!extract_artifact_flag(&legacy).unwrap());

        let project_legacy = HashMap::from([("extract_archive".to_string(), "false".to_string())]);
        assert!(!extract_artifact_flag(&project_legacy).unwrap());

        let conflicting = HashMap::from([
            ("extract".to_string(), "false".to_string()),
            ("extract_artifact".to_string(), "true".to_string()),
        ]);
        assert!(extract_artifact_flag(&conflicting).unwrap());

        let invalid_canonical = HashMap::from([
            ("extract".to_string(), "true".to_string()),
            ("extract_artifact".to_string(), "invalid".to_string()),
        ]);
        assert!(extract_artifact_flag(&invalid_canonical).is_err());
    }

    #[test]
    fn strips_exactly_one_top_level_directory() {
        let stage = std::env::temp_dir().join(format!("nanolink-strip-test-{}", Uuid::new_v4()));
        let top = stage.join("dist");
        fs::create_dir_all(&top).unwrap();
        fs::write(top.join("index.html"), b"ok").unwrap();

        strip_single_top_level(&stage).unwrap();
        assert_eq!(fs::read(stage.join("index.html")).unwrap(), b"ok");
        assert!(!top.exists());
        fs::remove_dir_all(stage).unwrap();
    }

    #[test]
    fn validates_artifact_type() {
        assert!(validate_artifact_name("java", "service.jar").is_ok());
        assert!(validate_artifact_name("java", "service.zip").is_err());
        assert!(validate_artifact_name("static", "site.tar.gz").is_ok());
        assert!(validate_artifact_name("static", "site.tar").is_ok());
        assert!(validate_artifact_name("static", "../site.zip").is_err());
    }

    #[cfg(unix)]
    #[test]
    fn extracts_tar_and_tar_gz_with_safe_options() {
        let root = std::env::temp_dir().join(format!("nanolink-tar-test-{}", Uuid::new_v4()));
        let source = root.join("source");
        fs::create_dir_all(&source).unwrap();
        fs::write(source.join("index.html"), b"ok").unwrap();

        for (name, gzip) in [("site.tar", false), ("site.tar.gz", true)] {
            let archive = root.join(name);
            let mut create = Command::new("tar");
            create.arg(if gzip { "-czf" } else { "-cf" });
            let status = create
                .arg(&archive)
                .arg("-C")
                .arg(&source)
                .arg(".")
                .status()
                .unwrap();
            assert!(status.success());

            let stage = root.join(format!("stage-{name}"));
            fs::create_dir(&stage).unwrap();
            extract_archive(&archive, name, &stage).unwrap();
            assert_eq!(fs::read(stage.join("index.html")).unwrap(), b"ok");
        }
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn extraction_protocol_prefers_canonical_key_and_accepts_legacy_alias() {
        let root = std::env::temp_dir().join(format!("nanolink-deploy-test-{}", Uuid::new_v4()));
        fs::create_dir_all(&root).unwrap();
        let target = root.join("site");
        let cfg = DeploymentsConfig {
            enabled: true,
            allowed_roots: vec![root.to_string_lossy().into_owned()],
            max_artifact_size: 1024,
            timeout_seconds: 30,
        };
        let mut params = HashMap::from([
            ("project_type".into(), "static".into()),
            ("version".into(), "1.0.0".into()),
            ("deploy_path".into(), target.to_string_lossy().into_owned()),
            ("artifact_url".into(), "https://example.com/site.tar".into()),
            ("artifact_sha256".into(), "a".repeat(64)),
            ("artifact_size".into(), "12".into()),
            ("artifact_name".into(), "site.tar".into()),
            ("extract_artifact".into(), "false".into()),
            ("extract".into(), "true".into()),
            ("strip_top_level".into(), "false".into()),
        ]);
        let request = parse_request(&cfg, &params, true).expect("canonical request");
        assert!(!request.extract_artifact);
        params.remove("extract_artifact");
        let request = parse_request(&cfg, &params, true).expect("legacy request");
        assert!(request.extract_artifact);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn rejects_embedded_url_credentials() {
        assert!(validate_http_url("https://example.com/a.jar?token=x").is_ok());
        assert!(validate_http_url("https://user:pass@example.com/a.jar").is_err());
        assert!(validate_http_url("file:///tmp/a.jar").is_err());
    }
}
