use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::{Read, Write};
use std::path::{Component, Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tracing::info;
use url::Url;
use uuid::Uuid;

#[cfg(unix)]
use std::os::unix::{fs::PermissionsExt, process::CommandExt};

use crate::config::{BuildsConfig, Config};
use crate::proto::CommandResult;

pub struct BuildExecutor {
    config: Arc<Config>,
    active: Arc<Mutex<HashMap<String, Arc<AtomicBool>>>>,
}

type ActiveBuilds = Arc<Mutex<HashMap<String, Arc<AtomicBool>>>>;
static ACTIVE_BUILDS: OnceLock<ActiveBuilds> = OnceLock::new();

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct BuildStage {
    id: String,
    name: String,
    command: String,
    #[serde(default)]
    needs: Vec<String>,
    #[serde(default)]
    allow_failure: bool,
    #[serde(default)]
    timeout_seconds: u64,
}

#[derive(Debug)]
struct BuildRequest {
    run_id: String,
    source_type: String,
    source_url: String,
    source_ref: String,
    source_name: String,
    source_sha256: String,
    git_auth_type: String,
    git_username: String,
    git_credential: String,
    git_ssh_known_hosts: String,
    runner_type: String,
    container_image: String,
    stages: Vec<BuildStage>,
    variables: HashMap<String, String>,
    artifact_pattern: String,
    artifact_name: String,
    source_download_url: String,
    artifact_upload_url: String,
    log_update_url: String,
    timeout_seconds: u64,
}

impl BuildExecutor {
    pub fn new(config: Arc<Config>) -> Self {
        Self {
            config,
            active: ACTIVE_BUILDS
                .get_or_init(|| Arc::new(Mutex::new(HashMap::new())))
                .clone(),
        }
    }

    pub async fn execute(&self, params: &HashMap<String, String>) -> CommandResult {
        let run_id = params
            .get("run_id")
            .map(|value| value.trim().to_string())
            .unwrap_or_default();
        if run_id.is_empty() {
            return CommandResult {
                success: false,
                error: "Invalid build run id".to_string(),
                ..Default::default()
            };
        }
        let cancel = Arc::new(AtomicBool::new(false));
        {
            let mut active = self
                .active
                .lock()
                .unwrap_or_else(|guard| guard.into_inner());
            if active.contains_key(&run_id) {
                return CommandResult {
                    success: false,
                    error: "Build run is already active on this agent".to_string(),
                    ..Default::default()
                };
            }
            active.insert(run_id.clone(), cancel.clone());
        }
        let cfg = self.config.builds.clone();
        let params = params.clone();
        let result =
            tokio::task::spawn_blocking(move || execute_sync(&cfg, &params, &cancel)).await;
        self.active
            .lock()
            .unwrap_or_else(|guard| guard.into_inner())
            .remove(&run_id);
        match result {
            Ok(Ok(lines)) => CommandResult {
                success: true,
                output: lines.join("\n"),
                ..Default::default()
            },
            Ok(Err((lines, error))) => CommandResult {
                success: false,
                output: lines.join("\n"),
                error,
                ..Default::default()
            },
            Err(error) => CommandResult {
                success: false,
                error: format!("Build worker failed: {error}"),
                ..Default::default()
            },
        }
    }

    pub fn cancel(&self, run_id: &str) -> CommandResult {
        let run_id = run_id.trim();
        let active = self
            .active
            .lock()
            .unwrap_or_else(|guard| guard.into_inner());
        match active.get(run_id) {
            Some(cancel) => {
                cancel.store(true, Ordering::SeqCst);
                CommandResult {
                    success: true,
                    output: format!("Cancellation requested for build {run_id}"),
                    ..Default::default()
                }
            }
            None => CommandResult {
                success: false,
                error: "Build is no longer active on this agent".to_string(),
                ..Default::default()
            },
        }
    }

    pub async fn git_status(&self) -> CommandResult {
        match tokio::task::spawn_blocking(git_status_sync).await {
            Ok(Ok(output)) => CommandResult {
                success: true,
                output,
                ..Default::default()
            },
            Ok(Err(error)) => CommandResult {
                success: false,
                error,
                ..Default::default()
            },
            Err(error) => CommandResult {
                success: false,
                error: format!("Git readiness check failed: {error}"),
                ..Default::default()
            },
        }
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct GitCredentialStatus {
    username: String,
    git_version: String,
    credential_helper: String,
    ssh_agent: bool,
    public_keys: Vec<GitPublicKey>,
}

#[derive(Serialize)]
struct GitPublicKey {
    name: String,
    key: String,
}

fn git_status_sync() -> Result<String, String> {
    let git_version = command_stdout("git", &["--version"]);
    if git_version.is_empty() {
        return Err(
            "Git is not installed or is not available to the agent service account".to_string(),
        );
    }
    let credential_helper =
        command_stdout("git", &["config", "--global", "--get", "credential.helper"]);
    let username = std::env::var("USER")
        .or_else(|_| std::env::var("USERNAME"))
        .unwrap_or_default();
    let ssh_agent = std::env::var_os("SSH_AUTH_SOCK").is_some();
    let mut public_keys = Vec::new();
    if let Some(home) = std::env::var_os("HOME").or_else(|| std::env::var_os("USERPROFILE")) {
        let ssh_dir = PathBuf::from(home).join(".ssh");
        if let Ok(entries) = fs::read_dir(ssh_dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                let name = entry.file_name().to_string_lossy().to_string();
                let Ok(kind) = entry.file_type() else {
                    continue;
                };
                if !name.ends_with(".pub") || !kind.is_file() || kind.is_symlink() {
                    continue;
                }
                let Ok(metadata) = entry.metadata() else {
                    continue;
                };
                if metadata.len() == 0 || metadata.len() > 16 * 1024 {
                    continue;
                }
                let Ok(value) = fs::read_to_string(path) else {
                    continue;
                };
                let key = value.trim();
                if is_ssh_public_key(key) {
                    public_keys.push(GitPublicKey {
                        name,
                        key: key.to_string(),
                    });
                }
            }
        }
    }
    public_keys.sort_by(|a, b| a.name.cmp(&b.name));
    serde_json::to_string(&GitCredentialStatus {
        username,
        git_version,
        credential_helper,
        ssh_agent,
        public_keys,
    })
    .map_err(|error| format!("Encode Git readiness status: {error}"))
}

fn command_stdout(program: &str, args: &[&str]) -> String {
    Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()
        .filter(|output| output.status.success())
        .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_string())
        .unwrap_or_default()
}

fn is_ssh_public_key(value: &str) -> bool {
    let prefix = value.split_whitespace().next().unwrap_or_default();
    prefix.starts_with("ssh-") || prefix.starts_with("ecdsa-") || prefix.starts_with("sk-")
}

fn execute_sync(
    cfg: &BuildsConfig,
    params: &HashMap<String, String>,
    cancel: &AtomicBool,
) -> Result<Vec<String>, (Vec<String>, String)> {
    let mut logs = Vec::new();
    let req = parse_request(cfg, params).map_err(|error| (logs.clone(), error))?;
    let root = PathBuf::from(&cfg.workspace_root);
    fs::create_dir_all(&root).map_err(|e| (logs.clone(), format!("Create workspace root: {e}")))?;
    let canonical_root = root
        .canonicalize()
        .map_err(|e| (logs.clone(), format!("Resolve workspace root: {e}")))?;
    let workspace = canonical_root.join(format!("run-{}-{}", req.run_id, Uuid::new_v4()));
    fs::create_dir(&workspace).map_err(|e| (logs.clone(), format!("Create workspace: {e}")))?;
    let _guard = WorkspaceGuard(workspace.clone());
    logs.push(format!("[done] prepare workspace {}", req.run_id));
    send_log_update(&req, &logs, cfg.max_output_size);

    let deadline = Instant::now() + Duration::from_secs(req.timeout_seconds);
    if let Err(error) = ensure_not_canceled(cancel)
        .and_then(|_| fetch_source(cfg, &req, &workspace, &mut logs, cancel))
    {
        logs.push(format!("[error] {error}"));
        send_log_update(&req, &logs, cfg.max_output_size);
        return Err((logs, error));
    }
    send_log_update(&req, &logs, cfg.max_output_size);
    let source_dir = workspace.join("source");
    if !source_dir.exists() {
        return Err((
            logs,
            "Source preparation did not produce a source directory".to_string(),
        ));
    }

    for stage in &req.stages {
        if let Err(error) = ensure_not_canceled(cancel) {
            logs.push(format!("[stage:canceled] {} {}", stage.id, stage.name));
            send_log_update(&req, &logs, cfg.max_output_size);
            return Err((logs, error));
        }
        if Instant::now() >= deadline {
            return Err((
                logs,
                format!("Pipeline timed out before stage {}", stage.name),
            ));
        }
        logs.push(format!("[stage:start] {} {}", stage.id, stage.name));
        send_log_update(&req, &logs, cfg.max_output_size);
        let progress_prefix = logs.clone();
        match run_stage(cfg, &req, stage, &source_dir, deadline, cancel, |partial| {
            let mut snapshot = progress_prefix.clone();
            append_output(&mut snapshot, partial, cfg.max_output_size);
            send_log_update(&req, &snapshot, cfg.max_output_size);
        }) {
            Ok(output) => {
                append_output(&mut logs, &output, cfg.max_output_size);
                logs.push(format!("[stage:done] {} {}", stage.id, stage.name));
                send_log_update(&req, &logs, cfg.max_output_size);
            }
            Err(error) if stage.allow_failure => {
                append_output(&mut logs, &error, cfg.max_output_size);
                logs.push(format!("[stage:warning] {} {}", stage.id, stage.name));
                send_log_update(&req, &logs, cfg.max_output_size);
            }
            Err(error) => {
                append_output(&mut logs, &error, cfg.max_output_size);
                logs.push(format!("[stage:failed] {} {}", stage.id, stage.name));
                send_log_update(&req, &logs, cfg.max_output_size);
                return Err((logs, format!("Stage '{}' failed", stage.name)));
            }
        }
    }

    if let Err(error) = ensure_not_canceled(cancel) {
        return Err((logs, error));
    }
    let artifact =
        resolve_artifact(&source_dir, &req.artifact_pattern).map_err(|e| (logs.clone(), e))?;
    let metadata =
        fs::metadata(&artifact).map_err(|e| (logs.clone(), format!("Inspect artifact: {e}")))?;
    if metadata.len() == 0 || metadata.len() > cfg.max_artifact_size {
        return Err((
            logs,
            "Artifact is empty or exceeds the configured limit".to_string(),
        ));
    }
    let hash = sha256_file(&artifact).map_err(|e| (logs.clone(), e))?;
    logs.push(format!(
        "[done] collect {} {} bytes",
        req.artifact_name,
        metadata.len()
    ));
    send_log_update(&req, &logs, cfg.max_output_size);
    upload_artifact(&req, &artifact, metadata.len(), &hash, cancel)
        .map_err(|e| (logs.clone(), e))?;
    logs.push(format!(
        "[done] upload {} sha256:{}",
        req.artifact_name, hash
    ));
    send_log_update(&req, &logs, cfg.max_output_size);
    info!(
        "Build {} completed with artifact {}",
        req.run_id, req.artifact_name
    );
    Ok(logs)
}

fn parse_request(
    cfg: &BuildsConfig,
    params: &HashMap<String, String>,
) -> Result<BuildRequest, String> {
    if !cfg.enabled {
        return Err("Automated builds are disabled on this agent".to_string());
    }
    let get = |key: &str| params.get(key).map(|s| s.trim()).unwrap_or("");
    let get_raw = |key: &str| params.get(key).map(String::as_str).unwrap_or("");
    let run_id = get("run_id").to_string();
    if run_id.is_empty()
        || !run_id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-')
    {
        return Err("Invalid build run id".to_string());
    }
    let source_type = get("source_type").to_string();
    if !matches!(source_type.as_str(), "git" | "url" | "upload") {
        return Err("source_type must be git, url, or upload".to_string());
    }
    let runner_type = get("runner_type").to_string();
    if !matches!(runner_type.as_str(), "docker" | "host") {
        return Err("runner_type must be docker or host".to_string());
    }
    if runner_type == "host" && !cfg.allow_host_runner {
        return Err("Host build runner is disabled on this agent".to_string());
    }
    let container_image = get("container_image").to_string();
    if runner_type == "docker" {
        validate_image(&container_image)?;
        if !cfg.allowed_images.is_empty() && !cfg.allowed_images.contains(&container_image) {
            return Err(format!(
                "Container image '{container_image}' is not allowed"
            ));
        }
    }
    let stages: Vec<BuildStage> = serde_json::from_str(get("stages_json"))
        .map_err(|e| format!("Invalid pipeline stages: {e}"))?;
    validate_stages(&stages)?;
    let variables: HashMap<String, String> = serde_json::from_str(get("variables_json"))
        .map_err(|e| format!("Invalid variables: {e}"))?;
    if variables.len() > 100 || variables.keys().any(|key| !valid_variable_name(key)) {
        return Err("Variables contain an invalid name or exceed the limit".to_string());
    }
    let timeout_seconds = get("timeout_seconds")
        .parse::<u64>()
        .unwrap_or(cfg.timeout_seconds)
        .min(cfg.timeout_seconds);
    if timeout_seconds == 0 {
        return Err("Build timeout must be greater than zero".to_string());
    }
    let artifact_pattern = get("artifact_pattern").to_string();
    validate_relative_pattern(&artifact_pattern)?;
    let artifact_name = get("artifact_name").to_string();
    if artifact_name.is_empty()
        || Path::new(&artifact_name)
            .file_name()
            .and_then(|v| v.to_str())
            != Some(artifact_name.as_str())
    {
        return Err("Invalid artifact name".to_string());
    }
    let source_url = get("source_url").to_string();
    let source_download_url = get("source_download_url").to_string();
    let artifact_upload_url = get("artifact_upload_url").to_string();
    let log_update_url = get("log_update_url").to_string();
    validate_http_url(&artifact_upload_url)?;
    validate_http_url(&log_update_url)?;
    if source_type == "git" {
        validate_git_url(&source_url)?;
    } else {
        validate_http_url(&source_download_url)?;
    }
    let git_auth_type = get("git_auth_type");
    let git_auth_type = if git_auth_type.is_empty() {
        "none"
    } else {
        git_auth_type
    };
    let git_username = get("git_username").to_string();
    let git_ssh_known_hosts = get_raw("git_ssh_known_hosts").trim().to_string();
    let git_credential = match git_auth_type {
        "none" => String::new(),
        "basic" => {
            let parsed =
                Url::parse(&source_url).map_err(|_| "Git URL must be absolute".to_string())?;
            if source_type != "git" || parsed.scheme() != "https" || git_username.is_empty() {
                return Err(
                    "Basic Git authentication requires an HTTPS source and username".to_string(),
                );
            }
            let password = get_raw("git_password").to_string();
            if password.is_empty()
                || password.len() > 16 * 1024
                || password.chars().any(|c| matches!(c, '\r' | '\n' | '\0'))
            {
                return Err("Git password or access token is invalid".to_string());
            }
            password
        }
        "ssh" => {
            let parsed =
                Url::parse(&source_url).map_err(|_| "Git URL must be absolute".to_string())?;
            let private_key = get_raw("git_ssh_private_key").to_string();
            if source_type != "git"
                || parsed.scheme() != "ssh"
                || !private_key.starts_with("-----BEGIN OPENSSH PRIVATE KEY-----")
                || !private_key
                    .trim_end()
                    .ends_with("-----END OPENSSH PRIVATE KEY-----")
                || private_key.len() > 64 * 1024
                || private_key.contains('\0')
            {
                return Err(
                    "SSH Git authentication requires an ssh:// source and a valid deploy key"
                        .to_string(),
                );
            }
            if git_ssh_known_hosts.len() > 64 * 1024 || git_ssh_known_hosts.contains('\0') {
                return Err("SSH known_hosts data is invalid".to_string());
            }
            private_key
        }
        _ => return Err("git_auth_type must be none, basic, or ssh".to_string()),
    };
    Ok(BuildRequest {
        run_id,
        source_type,
        source_url,
        source_ref: get("source_ref").to_string(),
        source_name: get("source_name").to_string(),
        source_sha256: get("source_sha256").to_ascii_lowercase(),
        git_auth_type: git_auth_type.to_string(),
        git_username,
        git_credential,
        git_ssh_known_hosts,
        runner_type,
        container_image,
        stages,
        variables,
        artifact_pattern,
        artifact_name,
        source_download_url,
        artifact_upload_url,
        log_update_url,
        timeout_seconds,
    })
}

fn validate_stages(stages: &[BuildStage]) -> Result<(), String> {
    if stages.is_empty() || stages.len() > 30 {
        return Err("A pipeline must contain between 1 and 30 stages".to_string());
    }
    let mut seen = HashSet::new();
    for stage in stages {
        if stage.id.is_empty()
            || stage.id.len() > 64
            || !stage
                .id
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
            || !seen.insert(stage.id.clone())
        {
            return Err(
                "Stage ids must be unique and use letters, numbers, dash, or underscore"
                    .to_string(),
            );
        }
        if stage.name.trim().is_empty()
            || stage.name.len() > 100
            || stage.command.trim().is_empty()
            || stage.command.len() > 16_000
        {
            return Err("Every stage requires a valid name and command".to_string());
        }
        for need in &stage.needs {
            if !seen.contains(need) {
                return Err(format!(
                    "Stage '{}' depends on an unknown or later stage",
                    stage.id
                ));
            }
        }
    }
    Ok(())
}

fn fetch_source(
    cfg: &BuildsConfig,
    req: &BuildRequest,
    workspace: &Path,
    logs: &mut Vec<String>,
    cancel: &AtomicBool,
) -> Result<(), String> {
    if req.source_type == "git" {
        let mut args = vec!["clone", "--depth", "1"];
        if !req.source_ref.is_empty() {
            args.extend(["--branch", req.source_ref.as_str()]);
        }
        args.push("--");
        args.push(req.source_url.as_str());
        args.push("source");
        let mut command = Command::new("git");
        command
            .args(args)
            .current_dir(workspace)
            .env("GIT_TERMINAL_PROMPT", "0")
            .envs(&req.variables);
        configure_git_auth(&mut command, req, workspace)?;
        run_with_timeout(
            command,
            Duration::from_secs(req.timeout_seconds),
            cfg.max_output_size,
            cancel,
            |_| {},
        )
        .map_err(|error| format!("Git source fetch failed: {error}"))?;
        logs.push(format!(
            "[done] source git {} {}",
            req.source_url,
            if req.source_ref.is_empty() {
                "HEAD"
            } else {
                &req.source_ref
            }
        ));
        return Ok(());
    }

    let source_name = if req.source_name.is_empty() {
        "source.tar.gz"
    } else {
        &req.source_name
    };
    if Path::new(source_name).file_name().and_then(|v| v.to_str()) != Some(source_name) {
        return Err("Invalid source archive name".to_string());
    }
    let archive = workspace.join(source_name);
    download_limited(
        &req.source_download_url,
        &archive,
        cfg.max_source_size,
        req.timeout_seconds,
        cancel,
    )?;
    if !req.source_sha256.is_empty() && sha256_file(&archive)? != req.source_sha256 {
        return Err("Source SHA-256 mismatch".to_string());
    }
    let source_dir = workspace.join("source");
    fs::create_dir(&source_dir).map_err(|e| format!("Create source directory: {e}"))?;
    extract_archive(&archive, source_name, &source_dir)?;
    logs.push(format!("[done] source {} {}", req.source_type, source_name));
    Ok(())
}

fn configure_git_auth(
    command: &mut Command,
    req: &BuildRequest,
    workspace: &Path,
) -> Result<(), String> {
    match req.git_auth_type.as_str() {
        "none" => Ok(()),
        "basic" => {
            #[cfg(unix)]
            let askpass = workspace.join(".git-askpass.sh");
            #[cfg(windows)]
            let askpass = workspace.join("git-askpass.cmd");
            #[cfg(unix)]
            let script = "#!/bin/sh\ncase \"$1\" in *sername*) printf '%s\\n' \"$NANOLINK_GIT_USERNAME\" ;; *) printf '%s\\n' \"$NANOLINK_GIT_PASSWORD\" ;; esac\n";
            #[cfg(windows)]
            let script = "@echo off\r\necho %1| findstr /I username >nul\r\nif errorlevel 1 (echo %NANOLINK_GIT_PASSWORD%) else (echo %NANOLINK_GIT_USERNAME%)\r\n";
            fs::write(&askpass, script)
                .map_err(|e| format!("Create Git credential helper: {e}"))?;
            #[cfg(unix)]
            fs::set_permissions(&askpass, fs::Permissions::from_mode(0o700))
                .map_err(|e| format!("Protect Git credential helper: {e}"))?;
            command
                .env("GIT_ASKPASS", &askpass)
                .env("NANOLINK_GIT_USERNAME", &req.git_username)
                .env("NANOLINK_GIT_PASSWORD", &req.git_credential);
            Ok(())
        }
        "ssh" => {
            let key_path = workspace.join(".git-deploy-key");
            fs::write(&key_path, &req.git_credential)
                .map_err(|e| format!("Create Git SSH deploy key: {e}"))?;
            #[cfg(unix)]
            fs::set_permissions(&key_path, fs::Permissions::from_mode(0o600))
                .map_err(|e| format!("Protect Git SSH deploy key: {e}"))?;
            let mut ssh_command = format!(
                "ssh -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -i {}",
                shell_quote_path(&key_path)
            );
            if !req.git_ssh_known_hosts.is_empty() {
                let known_hosts = workspace.join(".git-known-hosts");
                fs::write(&known_hosts, &req.git_ssh_known_hosts)
                    .map_err(|e| format!("Create Git SSH known_hosts file: {e}"))?;
                #[cfg(unix)]
                fs::set_permissions(&known_hosts, fs::Permissions::from_mode(0o600))
                    .map_err(|e| format!("Protect Git SSH known_hosts file: {e}"))?;
                ssh_command.push_str(" -o UserKnownHostsFile=");
                ssh_command.push_str(&shell_quote_path(&known_hosts));
            }
            command.env("GIT_SSH_COMMAND", ssh_command);
            Ok(())
        }
        _ => Err("Unsupported Git authentication mode".to_string()),
    }
}

fn shell_quote_path(path: &Path) -> String {
    let value = path.to_string_lossy();
    #[cfg(unix)]
    return format!("'{}'", value.replace('\'', "'\\''"));
    #[cfg(windows)]
    return format!("\"{}\"", value.replace('"', "\\\""));
}

fn run_stage<F>(
    cfg: &BuildsConfig,
    req: &BuildRequest,
    stage: &BuildStage,
    source_dir: &Path,
    deadline: Instant,
    cancel: &AtomicBool,
    on_progress: F,
) -> Result<String, String>
where
    F: Fn(&str),
{
    let remaining = deadline.saturating_duration_since(Instant::now());
    let stage_timeout = if stage.timeout_seconds == 0 {
        remaining
    } else {
        remaining.min(Duration::from_secs(stage.timeout_seconds))
    };
    if stage_timeout.is_zero() {
        return Err("Stage deadline expired".to_string());
    }
    let container_name = if req.runner_type == "docker" {
        Some(format!(
            "nanolink-build-{}-{}",
            req.run_id.chars().take(8).collect::<String>(),
            stage.id
        ))
    } else {
        None
    };
    let mut command = if let Some(name) = &container_name {
        let mut cmd = Command::new("docker");
        cmd.args([
            "run",
            "--rm",
            "--init",
            "--name",
            name,
            "--network",
            "bridge",
            "--cap-drop",
            "ALL",
            "--security-opt",
            "no-new-privileges",
        ]);
        cmd.args(["--pids-limit", "512", "--memory", "2g", "--cpus", "2"]);
        cmd.args(["--tmpfs", "/tmp:rw,nosuid,size=512m"]);
        cmd.arg("--label")
            .arg(format!("nanolink.build_run={}", req.run_id));
        cmd.arg("-v")
            .arg(format!("{}:/workspace", source_dir.display()));
        cmd.args(["-w", "/workspace"]);
        for (key, value) in &req.variables {
            // Pass only the variable name on the command line and let Docker
            // inherit its value from the client environment. Secret values do
            // not become visible in the host process list.
            cmd.arg("-e").arg(key);
            cmd.env(key, value);
        }
        cmd.arg(&req.container_image);
        cmd.args(["/bin/sh", "-eu", "-c", &stage.command]);
        cmd
    } else {
        let mut cmd = if cfg!(windows) {
            let mut c = Command::new("powershell");
            c.args(["-NoProfile", "-NonInteractive", "-Command", &stage.command]);
            c
        } else {
            let mut c = Command::new("/bin/sh");
            c.args(["-eu", "-c", &stage.command]);
            c
        };
        cmd.current_dir(source_dir);
        cmd.envs(&req.variables);
        cmd
    };
    command.stdout(Stdio::piped()).stderr(Stdio::piped());
    let result = run_with_timeout(
        command,
        stage_timeout,
        cfg.max_output_size,
        cancel,
        on_progress,
    );
    if result.is_err() {
        if let Some(name) = container_name {
            let _ = Command::new("docker")
                .args(["rm", "-f", &name])
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status();
        }
    }
    result
}

fn run_with_timeout<F>(
    mut command: Command,
    timeout: Duration,
    max_output: usize,
    cancel: &AtomicBool,
    on_progress: F,
) -> Result<String, String>
where
    F: Fn(&str),
{
    command.stdout(Stdio::piped()).stderr(Stdio::piped());
    #[cfg(unix)]
    command.process_group(0);
    let mut child = command.spawn().map_err(|e| format!("Start stage: {e}"))?;
    let output = Arc::new(Mutex::new(Vec::with_capacity(max_output.min(64 * 1024))));
    let mut readers = Vec::with_capacity(2);
    if let Some(pipe) = child.stdout.take() {
        let shared = output.clone();
        readers.push(std::thread::spawn(move || {
            drain_reader_shared(pipe, shared, max_output)
        }));
    }
    if let Some(pipe) = child.stderr.take() {
        let shared = output.clone();
        readers.push(std::thread::spawn(move || {
            drain_reader_shared(pipe, shared, max_output)
        }));
    }
    let start = Instant::now();
    let mut last_progress = Instant::now();
    loop {
        if cancel.load(Ordering::SeqCst) {
            terminate_process_tree(&mut child);
            return Err("Build canceled".to_string());
        }
        match child.try_wait() {
            Ok(Some(status)) => {
                join_readers(readers);
                let output = output_snapshot(&output);
                return if status.success() {
                    Ok(output)
                } else {
                    Err(format!("{output}\nProcess exited with {status}"))
                };
            }
            Ok(None) if start.elapsed() >= timeout => {
                terminate_process_tree(&mut child);
                return Err(format!(
                    "Stage timed out after {} seconds",
                    timeout.as_secs()
                ));
            }
            Ok(None) => {
                if last_progress.elapsed() >= Duration::from_secs(1) {
                    let snapshot = output_snapshot(&output);
                    if !snapshot.is_empty() {
                        on_progress(&snapshot);
                    }
                    last_progress = Instant::now();
                }
                std::thread::sleep(Duration::from_millis(150));
            }
            Err(e) => {
                terminate_process_tree(&mut child);
                return Err(format!("Wait for stage: {e}"));
            }
        }
    }
}

fn terminate_process_tree(child: &mut Child) {
    #[cfg(unix)]
    {
        use nix::sys::signal::{Signal, killpg};
        use nix::unistd::Pid;
        let _ = killpg(Pid::from_raw(child.id() as i32), Signal::SIGKILL);
    }
    #[cfg(windows)]
    {
        let pid = child.id().to_string();
        let _ = Command::new("taskkill")
            .args(["/PID", &pid, "/T", "/F"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
    let _ = child.kill();
    let _ = child.wait();
}

fn drain_reader_shared(mut reader: impl Read, output: Arc<Mutex<Vec<u8>>>, max: usize) {
    let mut buffer = [0u8; 16 * 1024];
    loop {
        match reader.read(&mut buffer) {
            Ok(0) | Err(_) => break,
            Ok(read) => {
                let mut kept = output.lock().unwrap_or_else(|guard| guard.into_inner());
                let remaining = max.saturating_sub(kept.len());
                kept.extend_from_slice(&buffer[..read.min(remaining)]);
            }
        }
    }
}

fn join_readers(readers: Vec<std::thread::JoinHandle<()>>) {
    for reader in readers {
        let _ = reader.join();
    }
}

fn output_snapshot(output: &Arc<Mutex<Vec<u8>>>) -> String {
    let bytes = output.lock().unwrap_or_else(|guard| guard.into_inner());
    String::from_utf8_lossy(&bytes).to_string()
}

fn resolve_artifact(root: &Path, pattern: &str) -> Result<PathBuf, String> {
    let full = root.join(pattern);
    let matches = glob::glob(full.to_string_lossy().as_ref())
        .map_err(|e| format!("Invalid artifact pattern: {e}"))?
        .filter_map(Result::ok)
        .filter(|path| path.is_file())
        .take(2)
        .collect::<Vec<_>>();
    if matches.len() != 1 {
        return Err(format!(
            "Artifact pattern must match exactly one file; matched {}",
            matches.len()
        ));
    }
    let canonical_root = root
        .canonicalize()
        .map_err(|e| format!("Resolve source root: {e}"))?;
    let canonical = matches[0]
        .canonicalize()
        .map_err(|e| format!("Resolve artifact: {e}"))?;
    if !canonical.starts_with(canonical_root) {
        return Err("Artifact escapes the build workspace".to_string());
    }
    Ok(canonical)
}

fn download_limited(
    url: &str,
    destination: &Path,
    max_size: u64,
    timeout: u64,
    cancel: &AtomicBool,
) -> Result<(), String> {
    let destination = destination
        .to_str()
        .ok_or("Destination is not valid UTF-8")?;
    #[cfg(unix)]
    let mut command = Command::new("curl");
    #[cfg(unix)]
    command.args([
        "-fL",
        "--silent",
        "--show-error",
        "--connect-timeout",
        "15",
        "--max-filesize",
        &max_size.to_string(),
        "--max-time",
        &timeout.to_string(),
        "-o",
        destination,
        url,
    ]);
    #[cfg(windows)]
    let command = {
        let mut command = Command::new("powershell");
        command.args(["-NoProfile", "-NonInteractive", "-Command", "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri $args[0] -OutFile $args[1]", url, destination]);
        command
    };
    run_with_timeout(
        command,
        Duration::from_secs(timeout),
        64 * 1024,
        cancel,
        |_| {},
    )
    .map_err(|error| format!("Source download failed: {error}"))?;
    let size = fs::metadata(destination)
        .map_err(|e| format!("Inspect source: {e}"))?
        .len();
    if size == 0 || size > max_size {
        let _ = fs::remove_file(destination);
        return Err("Source exceeds the configured limit".to_string());
    }
    Ok(())
}

fn upload_artifact(
    req: &BuildRequest,
    artifact: &Path,
    size: u64,
    sha256: &str,
    cancel: &AtomicBool,
) -> Result<(), String> {
    let artifact = artifact
        .to_str()
        .ok_or("Artifact path is not valid UTF-8")?;
    #[cfg(unix)]
    let mut command = Command::new("curl");
    #[cfg(unix)]
    command.args([
        "-f",
        "--silent",
        "--show-error",
        "--connect-timeout",
        "15",
        "--max-time",
        &req.timeout_seconds.to_string(),
        "-X",
        "PUT",
        "-H",
        &format!("X-Artifact-Name: {}", req.artifact_name),
        "-H",
        &format!("X-Artifact-Size: {size}"),
        "-H",
        &format!("X-Artifact-SHA256: {sha256}"),
        "--upload-file",
        artifact,
        &req.artifact_upload_url,
    ]);
    #[cfg(windows)]
    let command = {
        let mut command = Command::new("powershell");
        command.args(["-NoProfile", "-NonInteractive", "-Command", "$headers=@{'X-Artifact-Name'=$args[2];'X-Artifact-Size'=$args[3];'X-Artifact-SHA256'=$args[4]}; Invoke-WebRequest -Method Put -Headers $headers -InFile $args[0] -Uri $args[1]", artifact, &req.artifact_upload_url, &req.artifact_name, &size.to_string(), sha256]);
        command
    };
    run_with_timeout(
        command,
        Duration::from_secs(req.timeout_seconds),
        64 * 1024,
        cancel,
        |_| {},
    )
    .map(|_| ())
    .map_err(|error| format!("Artifact upload failed: {error}"))
}

fn extract_archive(archive: &Path, name: &str, destination: &Path) -> Result<(), String> {
    validate_archive_entries(archive, name)?;
    let lower = name.to_ascii_lowercase();
    let status = if lower.ends_with(".zip") {
        Command::new("unzip")
            .args(["-q"])
            .arg(archive)
            .arg("-d")
            .arg(destination)
            .status()
    } else if lower.ends_with(".tar.gz") || lower.ends_with(".tgz") {
        Command::new("tar")
            .args(["-xzf"])
            .arg(archive)
            .arg("-C")
            .arg(destination)
            .status()
    } else if lower.ends_with(".tar") {
        Command::new("tar")
            .args(["-xf"])
            .arg(archive)
            .arg("-C")
            .arg(destination)
            .status()
    } else {
        return Err("Source archive must be .zip, .tar, .tar.gz, or .tgz".to_string());
    }
    .map_err(|e| format!("Start archive extraction: {e}"))?;
    if !status.success() {
        return Err("Source archive extraction failed".to_string());
    }
    Ok(())
}

fn validate_archive_entries(archive: &Path, name: &str) -> Result<(), String> {
    let output = if name.to_ascii_lowercase().ends_with(".zip") {
        Command::new("unzip").args(["-Z1"]).arg(archive).output()
    } else {
        Command::new("tar").args(["-tf"]).arg(archive).output()
    }
    .map_err(|e| format!("Inspect archive: {e}"))?;
    if !output.status.success() {
        return Err("Source archive inspection failed".to_string());
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
            return Err("Source archive contains an unsafe path".to_string());
        }
    }
    Ok(())
}

fn validate_http_url(raw: &str) -> Result<(), String> {
    let url = Url::parse(raw).map_err(|_| "URL must be absolute".to_string())?;
    if !matches!(url.scheme(), "http" | "https")
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
    {
        return Err(
            "Only absolute HTTP(S) URLs without embedded credentials are allowed".to_string(),
        );
    }
    Ok(())
}

fn validate_git_url(raw: &str) -> Result<(), String> {
    let url = Url::parse(raw).map_err(|_| "Git URL must be absolute".to_string())?;
    if !matches!(url.scheme(), "http" | "https" | "ssh")
        || url.host_str().is_none()
        || url.password().is_some()
        || (matches!(url.scheme(), "http" | "https") && !url.username().is_empty())
    {
        return Err(
            "Git URL must use HTTP(S) or SSH and HTTP(S) must not embed credentials".to_string(),
        );
    }
    Ok(())
}

fn validate_image(image: &str) -> Result<(), String> {
    if image.is_empty()
        || image.len() > 500
        || !image
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '/' | ':' | '-' | '_' | '@'))
    {
        return Err("Container image contains unsupported characters".to_string());
    }
    Ok(())
}

fn validate_relative_pattern(pattern: &str) -> Result<(), String> {
    if pattern.is_empty()
        || pattern.len() > 500
        || Path::new(pattern).is_absolute()
        || pattern.contains("..")
        || pattern.contains('\\')
    {
        return Err("Artifact pattern must be a safe relative path or glob".to_string());
    }
    Ok(())
}

fn valid_variable_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 100
        && name
            .chars()
            .enumerate()
            .all(|(i, c)| c == '_' || c.is_ascii_alphanumeric() && (i > 0 || !c.is_ascii_digit()))
}

fn sha256_file(path: &Path) -> Result<String, String> {
    let mut file = fs::File::open(path).map_err(|e| format!("Open file for hashing: {e}"))?;
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 64 * 1024];
    loop {
        let read = file
            .read(&mut buffer)
            .map_err(|e| format!("Hash file: {e}"))?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(hex::encode(hasher.finalize()))
}

fn ensure_not_canceled(cancel: &AtomicBool) -> Result<(), String> {
    if cancel.load(Ordering::SeqCst) {
        Err("Build canceled".to_string())
    } else {
        Ok(())
    }
}

fn append_output(logs: &mut Vec<String>, output: &str, max: usize) {
    let used = logs.iter().map(|line| line.len() + 1).sum::<usize>();
    let remaining = max.saturating_sub(used);
    if remaining == 0 {
        return;
    }
    let mut bytes = output.as_bytes();
    if bytes.len() > remaining {
        bytes = &bytes[..remaining];
    }
    let text = String::from_utf8_lossy(bytes);
    logs.extend(text.lines().map(|line| format!("[log] {line}")));
    if output.len() > remaining {
        logs.push("[log] ... output truncated".to_string());
    }
}

fn send_log_update(req: &BuildRequest, logs: &[String], max: usize) {
    if req.log_update_url.is_empty() {
        return;
    }
    let mut body = logs.join("\n");
    if body.len() > max {
        let mut boundary = max;
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

struct WorkspaceGuard(PathBuf);
impl Drop for WorkspaceGuard {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_forward_or_unknown_dependencies() {
        let stages = vec![BuildStage {
            id: "test".into(),
            name: "Test".into(),
            command: "true".into(),
            needs: vec!["build".into()],
            allow_failure: false,
            timeout_seconds: 0,
        }];
        assert!(validate_stages(&stages).is_err());
    }

    #[test]
    fn artifact_pattern_cannot_escape_workspace() {
        assert!(validate_relative_pattern("../secret").is_err());
        assert!(validate_relative_pattern("dist/*.zip").is_ok());
    }

    #[test]
    fn accepts_ssh_git_user_but_rejects_http_credentials() {
        assert!(validate_git_url("ssh://git@example.com/team/repo.git").is_ok());
        assert!(validate_git_url("https://user:secret@example.com/repo.git").is_err());
    }

    #[test]
    fn recognizes_public_keys_without_exposing_private_material() {
        assert!(is_ssh_public_key("ssh-ed25519 AAAAC3Nz test@example"));
        assert!(is_ssh_public_key(
            "ecdsa-sha2-nistp256 AAAAE2Vj test@example"
        ));
        assert!(!is_ssh_public_key("-----BEGIN OPENSSH PRIVATE KEY-----"));
        assert!(!is_ssh_public_key("not a key"));
    }

    #[test]
    fn cancellation_flag_is_observed() {
        let cancel = AtomicBool::new(false);
        assert!(ensure_not_canceled(&cancel).is_ok());
        cancel.store(true, Ordering::SeqCst);
        assert_eq!(
            ensure_not_canceled(&cancel),
            Err("Build canceled".to_string())
        );
    }

    fn valid_git_params() -> HashMap<String, String> {
        HashMap::from([
			("run_id".into(), Uuid::new_v4().to_string()),
			("source_type".into(), "git".into()),
			("source_url".into(), "https://git.example.com/team/repo.git".into()),
			("source_ref".into(), "main".into()),
			("runner_type".into(), "docker".into()),
			("container_image".into(), "node:22-alpine".into()),
			("stages_json".into(), r#"[{"id":"build","name":"Build","command":"true","needs":[],"allowFailure":false,"timeoutSeconds":0}]"#.into()),
			("variables_json".into(), "{}".into()),
			("artifact_pattern".into(), "app.tar.gz".into()),
			("artifact_name".into(), "app.tar.gz".into()),
			("artifact_upload_url".into(), "https://server.example.com/upload".into()),
			("log_update_url".into(), "https://server.example.com/log".into()),
			("timeout_seconds".into(), "60".into()),
		])
    }

    #[test]
    fn validates_server_managed_git_authentication() {
        let cfg = BuildsConfig {
            enabled: true,
            ..Default::default()
        };
        let mut params = valid_git_params();
        params.insert("git_auth_type".into(), "basic".into());
        params.insert("git_username".into(), "builder".into());
        assert!(parse_request(&cfg, &params).is_err());
        params.insert("git_password".into(), "secret-token".into());
        let request = parse_request(&cfg, &params).expect("HTTPS credentials");
        assert_eq!(request.git_auth_type, "basic");
        assert_eq!(request.git_credential, "secret-token");

        params.insert(
            "source_url".into(),
            "http://git.example.com/team/repo.git".into(),
        );
        assert!(parse_request(&cfg, &params).is_err());

        params.insert(
            "source_url".into(),
            "ssh://git@git.example.com/team/repo.git".into(),
        );
        params.insert("git_auth_type".into(), "ssh".into());
        params.insert(
            "git_ssh_private_key".into(),
            "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----\n".into(),
        );
        params.insert(
            "git_ssh_known_hosts".into(),
            "git.example.com ssh-ed25519 AAAA".into(),
        );
        let request = parse_request(&cfg, &params).expect("SSH deploy key");
        assert_eq!(request.git_auth_type, "ssh");
        assert!(request.git_ssh_known_hosts.starts_with("git.example.com"));
    }
}
