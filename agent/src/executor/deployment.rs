use std::collections::HashMap;
use std::fs;
use std::io::Read;
use std::path::{Component, Path, PathBuf};
use std::process::Command;
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use sha2::{Digest, Sha256};
use tracing::{info, warn};
use url::Url;
use uuid::Uuid;

use crate::config::{Config, DeploymentsConfig};
use crate::proto::CommandResult;
use crate::security::validation::validate_service_name;

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

    let releases = req.deploy_path.join("releases");
    if let Err(e) = fs::create_dir_all(&releases) {
        return fail(logs, format!("Failed to create releases directory: {e}"));
    }
    let release_path = releases.join(&req.version);
    if release_path.exists() {
        return fail(logs, format!("Release {} already exists", req.version));
    }
    let stage = releases.join(format!(".staging-{}", Uuid::new_v4()));
    if let Err(e) = fs::create_dir(&stage) {
        return fail(logs, format!("Failed to create staging directory: {e}"));
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
        verify_artifact(
            &artifact_path,
            req.artifact_size.unwrap_or_default(),
            req.artifact_sha256.as_deref().unwrap_or_default(),
        )?;
        logs.push("[done] verify sha256".to_string());

        if req.project_type == "java" {
            fs::rename(&artifact_path, stage.join("app.jar"))
                .map_err(|e| format!("Failed to stage JAR: {e}"))?;
        } else {
            validate_archive_entries(&artifact_path, artifact_name)?;
            extract_archive(&artifact_path, artifact_name, &stage)?;
            reject_extracted_links(&stage)?;
            fs::remove_file(&artifact_path)
                .map_err(|e| format!("Failed to remove staged archive: {e}"))?;
        }
        fs::rename(&stage, &release_path)
            .map_err(|e| format!("Failed to finalize release: {e}"))?;
        Ok(())
    })();
    if let Err(error) = prepare {
        let _ = fs::remove_file(&artifact_path);
        let _ = fs::remove_dir_all(&stage);
        return fail(logs, error);
    }
    logs.push(format!("[done] stage {}", release_path.display()));

    let previous = match activate_release(&req.deploy_path, &release_path) {
        Ok(previous) => previous,
        Err(error) => {
            remove_failed_release(&release_path, &mut logs);
            return fail(logs, error);
        }
    };
    logs.push(format!("[done] activate {}", req.version));

    if let Err(error) = restart_or_reload(&req) {
        if restore_previous(&req, previous.as_deref(), &mut logs) {
            remove_failed_release(&release_path, &mut logs);
        }
        return fail(logs, error);
    }
    logs.push(format!("[done] service {}", service_action_label(&req)));

    if let Err(error) = check_health(&req.health_url) {
        if restore_previous(&req, previous.as_deref(), &mut logs) {
            remove_failed_release(&release_path, &mut logs);
        }
        return fail(logs, error);
    }
    logs.push(if req.health_url.is_empty() {
        "[done] health check skipped".to_string()
    } else {
        "[done] health check passed".to_string()
    });

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
    if !release_path.is_dir() {
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
    })
}

fn required(params: &HashMap<String, String>, name: &str) -> Result<String, String> {
    params
        .get(name)
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty())
        .ok_or_else(|| format!("Missing deployment parameter: {name}"))
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
        if root.is_absolute() && target.starts_with(root) && target != root {
            return Ok(());
        }
    }
    Err("Deployment path is outside deployments.allowed_roots".to_string())
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
        && !lower.ends_with(".tar.gz")
        && !lower.ends_with(".tgz")
    {
        return Err("Static deployments require a .zip, .tar.gz, or .tgz artifact".to_string());
    }
    Ok(())
}

fn download_artifact(cfg: &DeploymentsConfig, url: &str, dest: &Path) -> Result<(), String> {
    let dest = dest
        .to_str()
        .ok_or_else(|| "Artifact path is not valid UTF-8".to_string())?;
    #[cfg(unix)]
    let status = Command::new("curl")
        .args([
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
        ])
        .status()
        .map_err(|e| format!("Failed to run curl: {e}"))?;

    #[cfg(windows)]
    let status = Command::new("powershell")
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri $args[0] -OutFile $args[1]",
            url,
            dest,
        ])
        .status()
        .map_err(|e| format!("Failed to download artifact: {e}"))?;

    if !status.success() {
        return Err("Artifact download failed".to_string());
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
            Command::new("unzip").args(["-Z1"]).arg(artifact).output()
        } else {
            Command::new("tar").args(["-tzf"]).arg(artifact).output()
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
        let status = if name.to_lowercase().ends_with(".zip") {
            Command::new("unzip")
                .arg("-q")
                .arg(artifact)
                .arg("-d")
                .arg(stage)
                .status()
        } else {
            Command::new("tar")
                .arg("-xzf")
                .arg("--no-same-owner")
                .arg("--no-same-permissions")
                .arg(artifact)
                .arg("-C")
                .arg(stage)
                .status()
        }
        .map_err(|e| format!("Failed to extract archive: {e}"))?;
        if !status.success() {
            return Err("Artifact extraction failed".to_string());
        }
        Ok(())
    }
}

fn reject_extracted_links(root: &Path) -> Result<(), String> {
    let mut pending = vec![root.to_path_buf()];
    while let Some(directory) = pending.pop() {
        for entry in fs::read_dir(&directory)
            .map_err(|e| format!("Failed to validate extracted content: {e}"))?
        {
            let entry = entry.map_err(|e| format!("Failed to validate extracted content: {e}"))?;
            let metadata = fs::symlink_metadata(entry.path())
                .map_err(|e| format!("Failed to validate extracted content: {e}"))?;
            if metadata.file_type().is_symlink() {
                return Err(format!(
                    "Archive links are not allowed: {}",
                    entry.path().display()
                ));
            }
            if metadata.is_dir() {
                pending.push(entry.path());
            }
        }
    }
    Ok(())
}

#[cfg(unix)]
fn activate_release(deploy_path: &Path, release_path: &Path) -> Result<Option<PathBuf>, String> {
    use std::os::unix::fs::symlink;

    let current = deploy_path.join("current");
    let previous = fs::read_link(&current).ok();
    if current.exists() && previous.is_none() {
        return Err("Deployment current path exists but is not a symbolic link".to_string());
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
            let test = Command::new("nginx")
                .arg("-t")
                .output()
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
        let output = Command::new("systemctl")
            .args([action, "--", &req.service_name])
            .output()
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
        let status = Command::new("curl")
            .args(["-fsS", "--connect-timeout", "3", "--max-time", "10", url])
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status();
        if status.is_ok_and(|s| s.success()) {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deploy_path_must_be_below_an_allowed_root() {
        #[cfg(unix)]
        let (root, target, sibling) = (
            "/opt/nanolink/apps",
            "/opt/nanolink/apps/demo",
            "/opt/nanolink/apps2/demo",
        );
        #[cfg(windows)]
        let (root, target, sibling) = (
            r"C:\opt\nanolink\apps",
            r"C:\opt\nanolink\apps\demo",
            r"C:\opt\nanolink\apps2\demo",
        );
        let cfg = DeploymentsConfig {
            enabled: true,
            allowed_roots: vec![root.to_string()],
            max_artifact_size: 1024,
            timeout_seconds: 30,
        };
        assert!(validate_deploy_path(&cfg, Path::new(target)).is_ok());
        assert!(validate_deploy_path(&cfg, Path::new(sibling)).is_err());
        assert!(validate_deploy_path(&cfg, Path::new(root)).is_err());
    }

    #[test]
    fn validates_artifact_type() {
        assert!(validate_artifact_name("java", "service.jar").is_ok());
        assert!(validate_artifact_name("java", "service.zip").is_err());
        assert!(validate_artifact_name("static", "site.tar.gz").is_ok());
        assert!(validate_artifact_name("static", "../site.zip").is_err());
    }

    #[test]
    fn rejects_embedded_url_credentials() {
        assert!(validate_http_url("https://example.com/a.jar?token=x").is_ok());
        assert!(validate_http_url("https://user:pass@example.com/a.jar").is_err());
        assert!(validate_http_url("file:///tmp/a.jar").is_err());
    }
}
