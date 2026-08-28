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
use crate::executor::remote::{RemoteSession, shell_quote};
use crate::proto::CommandResult;
use crate::security::validation::validate_service_name;

const MAX_EXTRACTED_ENTRIES: usize = 100_000;
const MAX_EXTRACTED_BYTES: u64 = 2 * 1024 * 1024 * 1024;
const MAX_TOOL_OUTPUT_BYTES: u64 = 1024 * 1024;
#[cfg(unix)]
const ARCHIVE_TOOL_TIMEOUT: Duration = Duration::from_secs(120);
#[cfg(unix)]
const SERVICE_TOOL_TIMEOUT: Duration = Duration::from_secs(60);

struct ToolOutput {
    status: ExitStatus,
    #[cfg_attr(not(unix), allow(dead_code))]
    stdout: Vec<u8>,
    stderr: Vec<u8>,
}

struct DownloadOutcome {
    size: u64,
    resumed_from: u64,
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
    deployment_mode: String,
    remote_params: HashMap<String, String>,
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

    pub async fn execute_remote_script(&self, params: &HashMap<String, String>) -> CommandResult {
        let cfg = self.config.deployments.clone();
        let params = params.clone();
        let result = tokio::task::spawn_blocking(move || remote_script_sync(&cfg, &params)).await;
        command_result(result)
    }
}

type DeploymentWorkResult = Result<Vec<String>, (Vec<String>, String)>;
type DeploymentJoinResult = Result<DeploymentWorkResult, tokio::task::JoinError>;

fn command_result(result: DeploymentJoinResult) -> CommandResult {
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

    if req.deployment_mode == "ssh" {
        return deploy_remote_sync(cfg, &req, logs);
    }

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
    // The checksum is immutable release metadata, so it is also a safe,
    // deterministic identity for an interrupted download. Keeping the partial
    // file across deployment attempts lets a newly dispatched task continue
    // after an Agent restart or a longer network outage.
    let artifact_path = releases.join(format!(
        ".artifact-{}.part",
        req.artifact_sha256.as_deref().unwrap_or_default()
    ));
    let prepare = (|| -> Result<(), String> {
        let download = download_artifact(
            cfg,
            req.artifact_url.as_deref().unwrap_or_default(),
            &artifact_path,
            req.artifact_size.unwrap_or_default(),
        )?;
        logs.push(if download.resumed_from > 0 {
            format!(
                "[done] download {} bytes (resumed from byte {})",
                download.size, download.resumed_from
            )
        } else {
            format!("[done] download {} bytes", download.size)
        });
        send_log_update(&req, &logs);
        if let Err(error) = verify_artifact(
            &artifact_path,
            req.artifact_size.unwrap_or_default(),
            req.artifact_sha256.as_deref().unwrap_or_default(),
        ) {
            // A partial transfer is useful for a later Range request; a file
            // that reached the advertised size but failed integrity checks is
            // not and must never be reused.
            let _ = fs::remove_file(&artifact_path);
            return Err(error);
        }
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
        // Deliberately retain a regular partial artifact. A later deployment of
        // the same immutable release resumes it using HTTP Range. Successful
        // staging moves/removes this file, and integrity failures remove it
        // above before returning.
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
    if req.deployment_mode == "ssh" {
        return rollback_remote_sync(cfg, &req, logs);
    }
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

fn deploy_remote_sync(
    cfg: &DeploymentsConfig,
    req: &DeploymentRequest,
    mut logs: Vec<String>,
) -> DeploymentWorkResult {
    let work_dir = std::env::temp_dir().join(format!("nanolink-remote-deploy-{}", Uuid::new_v4()));
    if let Err(error) = fs::create_dir(&work_dir) {
        return fail_with_update(
            req,
            logs,
            format!("Failed to create remote deployment workspace: {error}"),
        );
    }
    let artifact_path = work_dir.join("artifact.part");
    let result = (|| -> Result<Vec<String>, String> {
        let download = download_artifact(
            cfg,
            req.artifact_url.as_deref().unwrap_or_default(),
            &artifact_path,
            req.artifact_size.unwrap_or_default(),
        )?;
        logs.push(format!("[done] download {} bytes", download.size));
        send_log_update(req, &logs);
        verify_artifact(
            &artifact_path,
            req.artifact_size.unwrap_or_default(),
            req.artifact_sha256.as_deref().unwrap_or_default(),
        )?;
        logs.push("[done] verify sha256".to_string());
        send_log_update(req, &logs);

        if req.project_type == "static" && req.extract_artifact {
            validate_archive_entries(
                &artifact_path,
                req.artifact_name.as_deref().unwrap_or_default(),
            )?;
            logs.push("[done] inspect archive paths".to_string());
            send_log_update(req, &logs);
        }

        let remote = RemoteSession::connect(
            &deployment_remote_params(req)?,
            Duration::from_secs(cfg.timeout_seconds),
        )?;
        logs.push("[done] ssh connect and authenticate".to_string());
        send_log_update(req, &logs);

        let transfer_id = Uuid::new_v4();
        let remote_artifact = format!("/tmp/nanolink-{transfer_id}-artifact");
        remote.upload_file(&artifact_path, &remote_artifact)?;
        logs.push(format!("[done] upload {} bytes over sftp", download.size));
        send_log_update(req, &logs);

        let deploy_path = req.deploy_path.to_string_lossy();
        let releases = format!("{deploy_path}/releases");
        let release_path = format!("{releases}/{}", req.version);
        let stage = format!("{releases}/.staging-{transfer_id}");
        let current = format!("{deploy_path}/current");
        let switch = format!("{deploy_path}/.current-{transfer_id}");
        let prepare = format!(
            "set -eu; mkdir -p {releases}; test ! -e {release}; rm -rf {stage}; mkdir {stage}",
            releases = shell_quote(&releases),
            release = shell_quote(&release_path),
            stage = shell_quote(&stage),
        );
        if let Err(error) = remote.exec_privileged(&prepare) {
            let _ = remote.exec(&format!("rm -f {}", shell_quote(&remote_artifact)));
            return Err(error);
        }

        let stage_result =
            stage_remote_artifact(&remote, req, &remote_artifact, &stage).and_then(|_| {
                remote.exec_privileged(&format!(
                    "set -eu; mv {} {}",
                    shell_quote(&stage),
                    shell_quote(&release_path)
                ))
            });
        if let Err(error) = stage_result {
            let _ = remote.exec(&format!("rm -f {}", shell_quote(&remote_artifact)));
            let _ = remote.exec_privileged(&format!("rm -rf {}", shell_quote(&stage)));
            return Err(error);
        }
        logs.push(format!("[done] stage {release_path}"));
        send_log_update(req, &logs);

        let previous = remote
            .exec(&format!(
                "readlink {} 2>/dev/null || true",
                shell_quote(&current)
            ))?
            .trim()
            .to_string();
        activate_remote_release(&remote, &release_path, &switch, &current)?;
        logs.push(format!("[done] activate {}", req.version));
        send_log_update(req, &logs);

        if let Err(error) = restart_remote_service(&remote, req) {
            restore_remote_release(
                &remote,
                req,
                &previous,
                &switch,
                &current,
                &release_path,
                &mut logs,
            );
            return Err(error);
        }
        logs.push(format!("[done] service {}", service_action_label(req)));
        send_log_update(req, &logs);

        if let Err(error) = check_remote_health(&remote, &req.health_url) {
            restore_remote_release(
                &remote,
                req,
                &previous,
                &switch,
                &current,
                &release_path,
                &mut logs,
            );
            return Err(error);
        }
        logs.push(if req.health_url.is_empty() {
            "[done] health check skipped".to_string()
        } else {
            "[done] health check passed".to_string()
        });
        send_log_update(req, &logs);

        match prune_remote_releases(&remote, &releases, &release_path, req.keep_releases) {
            Ok(()) => logs.push(format!(
                "[done] retain latest {} releases",
                req.keep_releases
            )),
            Err(error) => logs.push(format!("[warn] cleanup: {error}")),
        }
        send_log_update(req, &logs);
        Ok(logs.clone())
    })();
    let _ = fs::remove_dir_all(&work_dir);
    match result {
        Ok(lines) => Ok(lines),
        Err(error) => fail_with_update(req, logs, error),
    }
}

fn rollback_remote_sync(
    cfg: &DeploymentsConfig,
    req: &DeploymentRequest,
    mut logs: Vec<String>,
) -> DeploymentWorkResult {
    let remote = RemoteSession::connect(
        &deployment_remote_params(req).map_err(|e| (logs.clone(), e))?,
        Duration::from_secs(cfg.timeout_seconds),
    )
    .map_err(|e| (logs.clone(), e))?;
    logs.push("[done] ssh connect and authenticate".to_string());
    let deploy_path = req.deploy_path.to_string_lossy();
    let release_path = format!("{deploy_path}/releases/{}", req.version);
    let current = format!("{deploy_path}/current");
    let switch = format!("{deploy_path}/.current-{}", Uuid::new_v4());
    remote
        .exec(&format!("test -d {}", shell_quote(&release_path)))
        .map_err(|_| {
            (
                logs.clone(),
                format!(
                    "Release {} is not present on the remote target",
                    req.version
                ),
            )
        })?;
    let previous = remote
        .exec(&format!(
            "readlink {} 2>/dev/null || true",
            shell_quote(&current)
        ))
        .map_err(|e| (logs.clone(), e))?
        .trim()
        .to_string();
    if let Err(error) = activate_remote_release(&remote, &release_path, &switch, &current) {
        return fail(logs, error);
    }
    logs.push(format!("[done] activate {}", req.version));
    if let Err(error) = restart_remote_service(&remote, req) {
        restore_remote_release(&remote, req, &previous, &switch, &current, "", &mut logs);
        return fail(logs, error);
    }
    logs.push(format!("[done] service {}", service_action_label(req)));
    if let Err(error) = check_remote_health(&remote, &req.health_url) {
        restore_remote_release(&remote, req, &previous, &switch, &current, "", &mut logs);
        return fail(logs, error);
    }
    logs.push(if req.health_url.is_empty() {
        "[done] health check skipped".to_string()
    } else {
        "[done] health check passed".to_string()
    });
    Ok(logs)
}

fn remote_script_sync(
    cfg: &DeploymentsConfig,
    params: &HashMap<String, String>,
) -> DeploymentWorkResult {
    let mut logs = Vec::new();
    if !cfg.enabled {
        return fail(
            logs,
            "Application deployment is disabled in agent configuration".to_string(),
        );
    }
    let content = params
        .get("script_content")
        .filter(|value| !value.trim().is_empty())
        .cloned()
        .ok_or_else(|| {
            (
                logs.clone(),
                "Missing remote environment script content".to_string(),
            )
        })?;
    if content.len() > 256 * 1024 || content.contains('\0') {
        return fail(
            logs,
            "Remote environment script is invalid or too large".to_string(),
        );
    }
    let timeout = params
        .get("script_timeout_seconds")
        .and_then(|value| value.parse::<u64>().ok())
        .unwrap_or(600)
        .clamp(1, 3600);
    let remote = RemoteSession::connect(params, Duration::from_secs(timeout + 30))
        .map_err(|e| (logs.clone(), e))?;
    logs.push("[done] ssh connect and authenticate".to_string());
    let remote_script = format!("/tmp/nanolink-{}-environment.sh", Uuid::new_v4());
    remote
        .upload_content(content.as_bytes(), &remote_script)
        .map_err(|e| (logs.clone(), e))?;
    logs.push("[done] upload environment script".to_string());
    let command = format!("timeout {timeout} sh {}", shell_quote(&remote_script));
    let result = remote.exec_privileged(&command);
    let _ = remote.exec(&format!("rm -f {}", shell_quote(&remote_script)));
    match result {
        Ok(output) => {
            logs.push("[done] execute environment script".to_string());
            if !output.trim().is_empty() {
                logs.push(output.trim().to_string());
            }
            Ok(logs)
        }
        Err(error) => fail(logs, error),
    }
}

fn deployment_remote_params(req: &DeploymentRequest) -> Result<HashMap<String, String>, String> {
    if req.remote_params.is_empty() {
        return Err("Remote deployment connection parameters are unavailable".to_string());
    }
    Ok(req.remote_params.clone())
}

fn stage_remote_artifact(
    remote: &RemoteSession,
    req: &DeploymentRequest,
    remote_artifact: &str,
    stage: &str,
) -> Result<String, String> {
    let artifact_name = req.artifact_name.as_deref().unwrap_or("artifact");
    let command = if req.project_type == "java" {
        format!(
            "set -eu; mv {} {}/app.jar",
            shell_quote(remote_artifact),
            shell_quote(stage)
        )
    } else if !req.extract_artifact {
        format!(
            "set -eu; mv {} {}/{}",
            shell_quote(remote_artifact),
            shell_quote(stage),
            shell_quote(artifact_name)
        )
    } else {
        let extract = if artifact_name.to_ascii_lowercase().ends_with(".zip") {
            format!(
                "timeout 120 unzip -q {} -d {}",
                shell_quote(remote_artifact),
                shell_quote(stage)
            )
        } else if artifact_name.to_ascii_lowercase().ends_with(".tar.gz")
            || artifact_name.to_ascii_lowercase().ends_with(".tgz")
        {
            format!(
                "timeout 120 tar -xzf {} -C {}",
                shell_quote(remote_artifact),
                shell_quote(stage)
            )
        } else {
            format!(
                "timeout 120 tar -xf {} -C {}",
                shell_quote(remote_artifact),
                shell_quote(stage)
            )
        };
        let strip = if req.strip_top_level {
            let stripped = format!("{stage}.stripped");
            format!(
                "; count=$(find {stage} -mindepth 1 -maxdepth 1 -print | wc -l); test \"$count\" -eq 1; first=$(find {stage} -mindepth 1 -maxdepth 1 -print -quit); test -d \"$first\"; mkdir {stripped}; cp -a \"$first\"/. {stripped}/; rm -rf {stage}; mv {stripped} {stage}",
                stage = shell_quote(stage),
                stripped = shell_quote(&stripped),
            )
        } else {
            String::new()
        };
        format!(
            "set -eu; {extract}; rm -f {artifact}; test -z \"$(find {stage} -xdev -type l -print -quit)\"; entries=$(find {stage} -xdev -mindepth 1 -print | wc -l); test \"$entries\" -le {max_entries}; bytes=$(du -sb -- {stage} | cut -f1); test \"$bytes\" -le {max_bytes}{strip}",
            artifact = shell_quote(remote_artifact),
            stage = shell_quote(stage),
            max_entries = MAX_EXTRACTED_ENTRIES,
            max_bytes = MAX_EXTRACTED_BYTES,
        )
    };
    remote.exec_privileged(&command)
}

fn activate_remote_release(
    remote: &RemoteSession,
    release_path: &str,
    switch: &str,
    current: &str,
) -> Result<(), String> {
    remote.exec_privileged(&format!(
        "set -eu; ln -sfn {} {}; mv -Tf {} {}",
        shell_quote(release_path),
        shell_quote(switch),
        shell_quote(switch),
        shell_quote(current),
    ))?;
    Ok(())
}

fn restart_remote_service(remote: &RemoteSession, req: &DeploymentRequest) -> Result<(), String> {
    if req.service_name.is_empty() {
        return Ok(());
    }
    if req.project_type == "static" && req.service_name.to_ascii_lowercase().starts_with("nginx") {
        remote.exec_privileged("nginx -t")?;
    }
    let action = if req.project_type == "static" {
        "reload"
    } else {
        "restart"
    };
    remote.exec_privileged(&format!(
        "systemctl {action} -- {}",
        shell_quote(&req.service_name),
    ))?;
    Ok(())
}

fn check_remote_health(remote: &RemoteSession, url: &str) -> Result<(), String> {
    if url.is_empty() {
        return Ok(());
    }
    let command = format!(
        "curl -fsS --connect-timeout 3 --max-time 10 -- {} >/dev/null",
        shell_quote(url)
    );
    let mut last_error = String::new();
    for attempt in 1..=10 {
        match remote.exec(&command) {
            Ok(_) => return Ok(()),
            Err(error) => last_error = error,
        }
        if attempt < 10 {
            thread::sleep(Duration::from_secs(2));
        }
    }
    Err(format!(
        "Remote health check failed after 10 attempts: {last_error}"
    ))
}

fn restore_remote_release(
    remote: &RemoteSession,
    req: &DeploymentRequest,
    previous: &str,
    switch: &str,
    current: &str,
    failed_release: &str,
    logs: &mut Vec<String>,
) {
    let restore = if previous.is_empty() {
        remote.exec_privileged(&format!("rm -f {}", shell_quote(current)))
    } else {
        activate_remote_release(remote, previous, switch, current).map(|_| String::new())
    };
    if restore.is_ok() {
        let _ = restart_remote_service(remote, req);
        logs.push("[warn] restored previous remote release".to_string());
        if !failed_release.is_empty() {
            let _ = remote.exec_privileged(&format!("rm -rf {}", shell_quote(failed_release)));
        }
    } else {
        logs.push("[warn] failed to restore previous remote release".to_string());
    }
}

fn prune_remote_releases(
    remote: &RemoteSession,
    releases: &str,
    current: &str,
    keep: usize,
) -> Result<(), String> {
    // GNU find is available on the Linux targets supported by systemd deploys.
    // Paths are read after the first space so a normal path containing spaces
    // remains intact; newlines are rejected by deploy-path validation.
    remote.exec_privileged(&format!(
        "set -eu; find {releases} -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\\n' | sort -nr | tail -n +{start} | while IFS=' ' read -r stamp old; do test \"$old\" = {current} || rm -rf -- \"$old\"; done",
        releases = shell_quote(releases),
        current = shell_quote(current),
        start = keep + 1,
    ))?;
    Ok(())
}

fn validate_remote_deploy_path(target: &Path) -> Result<(), String> {
    let raw = target.to_string_lossy();
    if !raw.starts_with('/')
        || raw == "/"
        || raw.len() > 1000
        || raw.contains('\0')
        || raw.contains('\n')
        || raw.contains('\r')
        || raw
            .split('/')
            .any(|component| component == "." || component == "..")
    {
        return Err("Remote deployment path must be a normalized absolute Linux path".to_string());
    }
    Ok(())
}

fn parse_request(
    cfg: &DeploymentsConfig,
    params: &HashMap<String, String>,
    require_artifact: bool,
) -> Result<DeploymentRequest, String> {
    if !cfg.enabled {
        return Err("Application deployment is disabled in agent configuration".to_string());
    }
    let deployment_mode = params
        .get("deployment_mode")
        .map(|value| value.trim().to_ascii_lowercase())
        .unwrap_or_else(|| "local".to_string());
    if deployment_mode != "local" && deployment_mode != "ssh" {
        return Err("deployment_mode must be local or ssh".to_string());
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
    if deployment_mode == "ssh" {
        validate_remote_deploy_path(&deploy_path)?;
    } else {
        validate_deploy_path(cfg, &deploy_path)?;
    }
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

    let remote_params = if deployment_mode == "ssh" {
        [
            "ssh_host",
            "ssh_port",
            "ssh_username",
            "ssh_auth_type",
            "ssh_credential",
            "ssh_known_hosts",
            "ssh_allow_unknown_host",
            "ssh_use_sudo",
        ]
        .into_iter()
        .filter_map(|key| {
            params
                .get(key)
                .map(|value| (key.to_string(), value.clone()))
        })
        .collect()
    } else {
        HashMap::new()
    };

    Ok(DeploymentRequest {
        deployment_mode,
        remote_params,
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

fn download_artifact(
    cfg: &DeploymentsConfig,
    url: &str,
    dest: &Path,
    expected_size: u64,
) -> Result<DownloadOutcome, String> {
    if expected_size == 0 || expected_size > cfg.max_artifact_size {
        return Err("Artifact size exceeds the configured limit".to_string());
    }
    let mut resume_from = match fs::symlink_metadata(dest) {
        Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_file() => {
            return Err("Partial artifact path is not a regular file".to_string());
        }
        Ok(metadata) => metadata.len(),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => 0,
        Err(error) => return Err(format!("Failed to inspect partial artifact: {error}")),
    };
    if resume_from > expected_size || resume_from > cfg.max_artifact_size {
        fs::remove_file(dest)
            .map_err(|error| format!("Failed to discard oversized partial artifact: {error}"))?;
        resume_from = 0;
    }
    if resume_from == expected_size {
        return Ok(DownloadOutcome {
            size: expected_size,
            resumed_from: resume_from,
        });
    }

    let dest = dest
        .to_str()
        .ok_or_else(|| "Artifact path is not valid UTF-8".to_string())?;
    #[cfg(unix)]
    {
        let started = Instant::now();
        let timeout = Duration::from_secs(cfg.timeout_seconds);
        let mut last_error = String::new();
        for attempt in 1..=5 {
            let remaining = timeout.saturating_sub(started.elapsed());
            if remaining.is_zero() {
                break;
            }
            let max_time = remaining.as_secs().max(1).to_string();
            let output = run_tool(
                Command::new("curl").args([
                    "-fL",
                    "--silent",
                    "--show-error",
                    "--connect-timeout",
                    "15",
                    "--continue-at",
                    "-",
                    "--max-filesize",
                    &cfg.max_artifact_size.to_string(),
                    "--max-time",
                    &max_time,
                    "-o",
                    dest,
                    url,
                ]),
                remaining,
            )?;
            let size = fs::metadata(dest)
                .map(|metadata| metadata.len())
                .unwrap_or(0);
            if size > expected_size || size > cfg.max_artifact_size {
                let _ = fs::remove_file(dest);
                return Err("Downloaded artifact exceeds the configured limit".to_string());
            }
            if output.status.success() && size == expected_size {
                return Ok(DownloadOutcome {
                    size,
                    resumed_from: resume_from,
                });
            }
            last_error = String::from_utf8_lossy(&output.stderr).trim().to_string();
            if output.status.success() {
                last_error =
                    format!("server ended the transfer at byte {size}, expected {expected_size}");
            }
            if attempt < 5 && started.elapsed() < timeout {
                thread::sleep(Duration::from_secs(1));
            }
        }
        return Err(format!(
            "Artifact download failed after resumable retries{}{}",
            if last_error.is_empty() { "" } else { ": " },
            last_error
        ));
    }

    #[cfg(windows)]
    {
        // Windows PowerShell's Invoke-WebRequest does not consistently support
        // append-safe Range downloads across supported versions. Start clean
        // there rather than risk concatenating a full response onto a partial
        // file; Linux Agents use the resumable curl path above.
        if resume_from > 0 {
            fs::remove_file(dest)
                .map_err(|error| format!("Failed to reset partial artifact: {error}"))?;
            resume_from = 0;
        }
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
        if size == 0 || size > cfg.max_artifact_size || size > expected_size {
            let _ = fs::remove_file(dest);
            return Err("Downloaded artifact exceeds the configured limit".to_string());
        }
        Ok(DownloadOutcome {
            size,
            resumed_from: resume_from,
        })
    }
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
    let actual = hex::encode(hasher.finalize());
    if actual != expected_hash {
        return Err("Artifact SHA-256 mismatch".to_string());
    }
    Ok(())
}

fn validate_archive_entries(artifact: &Path, name: &str) -> Result<(), String> {
    #[cfg(not(unix))]
    {
        let _ = (artifact, name);
        Err("Static archive deployment is currently supported on Unix agents".to_string())
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
        Err("Static archive deployment is currently supported on Unix agents".to_string())
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
    // read_link preserves the link target exactly. Resolve relative targets from
    // the deployment root (where `current` lives), not from the agent's cwd.
    let previous = if previous.is_absolute() {
        previous.to_path_buf()
    } else {
        req.deploy_path.join(previous)
    };
    match activate_release(&req.deploy_path, &previous) {
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

    #[cfg(unix)]
    #[test]
    fn automatic_rollback_resolves_relative_current_link_from_deploy_root() {
        use std::os::unix::fs::symlink;

        let deploy_path =
            std::env::temp_dir().join(format!("nanolink-relative-rollback-{}", Uuid::new_v4()));
        let bootstrap = deploy_path.join("releases/bootstrap");
        let next = deploy_path.join("releases/next");
        fs::create_dir_all(&bootstrap).unwrap();
        fs::create_dir_all(&next).unwrap();
        fs::write(bootstrap.join("health.txt"), b"bootstrap-ok").unwrap();
        fs::write(next.join("health.txt"), b"next-ok").unwrap();
        symlink("releases/bootstrap", deploy_path.join("current")).unwrap();

        let previous = activate_release(&deploy_path, &next)
            .expect("activate next")
            .expect("relative previous link");
        assert_eq!(previous, PathBuf::from("releases/bootstrap"));

        let req = DeploymentRequest {
            deployment_mode: "local".into(),
            remote_params: HashMap::new(),
            project_type: "static".into(),
            version: "next".into(),
            deploy_path: deploy_path.clone(),
            service_name: String::new(),
            health_url: String::new(),
            keep_releases: 3,
            artifact_url: None,
            artifact_sha256: None,
            artifact_size: None,
            artifact_name: None,
            extract_artifact: true,
            strip_top_level: false,
            log_update_url: String::new(),
        };
        let mut logs = Vec::new();
        assert!(restore_previous(&req, Some(&previous), &mut logs));
        assert_eq!(
            fs::canonicalize(deploy_path.join("current")).unwrap(),
            fs::canonicalize(&bootstrap).unwrap()
        );
        fs::remove_dir_all(deploy_path).unwrap();
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

    #[test]
    fn remote_deployment_path_is_linux_absolute_on_every_agent_platform() {
        assert!(validate_remote_deploy_path(Path::new("/opt/apps/orders")).is_ok());
        assert!(validate_remote_deploy_path(Path::new("/opt/apps/../orders")).is_err());
        assert!(validate_remote_deploy_path(Path::new("relative/orders")).is_err());
        assert!(validate_remote_deploy_path(Path::new("/")).is_err());
    }

    #[test]
    fn remote_request_retains_connection_params_without_logging_them() {
        let cfg = DeploymentsConfig {
            enabled: true,
            allowed_roots: Vec::new(),
            max_artifact_size: 1024,
            timeout_seconds: 30,
        };
        let params = HashMap::from([
            ("deployment_mode".into(), "ssh".into()),
            ("project_type".into(), "java".into()),
            ("version".into(), "1.0.0".into()),
            ("deploy_path".into(), "/opt/apps/orders".into()),
            ("service_name".into(), "orders.service".into()),
            (
                "artifact_url".into(),
                "https://example.com/orders.jar".into(),
            ),
            ("artifact_sha256".into(), "a".repeat(64)),
            ("artifact_size".into(), "12".into()),
            ("artifact_name".into(), "orders.jar".into()),
            ("ssh_host".into(), "example.com".into()),
            ("ssh_port".into(), "22".into()),
            ("ssh_username".into(), "deploy".into()),
            ("ssh_auth_type".into(), "password".into()),
            ("ssh_credential".into(), "secret".into()),
        ]);
        let request = parse_request(&cfg, &params, true).expect("remote request");
        assert_eq!(request.deployment_mode, "ssh");
        assert_eq!(
            request
                .remote_params
                .get("ssh_credential")
                .map(String::as_str),
            Some("secret")
        );
    }
}
