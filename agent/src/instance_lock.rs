use anyhow::{Context, Result, anyhow, bail};
use std::fs::{File, OpenOptions};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

/// A replacement process spawned by the self-restart path may wait briefly for
/// its parent to release the instance lock. Normal interactive starts never set
/// this variable and therefore fail fast with a helpful message.
pub const RESTART_WAIT_ENV: &str = "NANOLINK_RESTART_WAIT_FOR_LOCK_MS";

/// Keeps one NanoLink Agent process per canonical configuration file.
///
/// The lock file intentionally lives next to the resolved configuration file.
/// This makes `/etc/nanolink/nanolink.yaml` and a symlink to the installed
/// configuration resolve to the same lock, without relying on a fixed TCP port
/// or a writable system-wide runtime directory.
pub struct InstanceLock {
    #[allow(dead_code)]
    file: File,
    #[cfg(not(any(unix, windows)))]
    path: PathBuf,
}

#[cfg(unix)]
impl Drop for InstanceLock {
    fn drop(&mut self) {
        use std::os::fd::AsRawFd;

        // Explicit unlock keeps reacquisition deterministic on platforms whose
        // flock lifetime semantics differ for multiple descriptors in one process.
        let _ = unsafe { libc::flock(self.file.as_raw_fd(), libc::LOCK_UN) };
    }
}

enum TryLockError {
    AlreadyRunning,
    Io(std::io::Error),
}

impl InstanceLock {
    pub fn acquire(config_path: &Path) -> Result<Self> {
        let resolved_config = std::fs::canonicalize(config_path).with_context(|| {
            format!(
                "Failed to resolve configuration file {}",
                config_path.display()
            )
        })?;
        let lock_path = lock_path_for(&resolved_config)?;
        let wait = restart_wait_duration();
        let deadline = Instant::now() + wait;

        loop {
            match try_acquire(&lock_path) {
                Ok(lock) => return Ok(lock),
                Err(TryLockError::AlreadyRunning) if Instant::now() < deadline => {
                    std::thread::sleep(Duration::from_millis(100));
                }
                Err(TryLockError::AlreadyRunning) => {
                    bail!(
                        "NanoLink Agent is already running for configuration {}.\n\
                         NanoLink Agent 已在运行，请勿重复启动。\n\
                         Use `nanolink-agent status` or `journalctl -fu nanolink-agent` to inspect the service.",
                        resolved_config.display()
                    );
                }
                Err(TryLockError::Io(error)) => {
                    return Err(anyhow!(error)).with_context(|| {
                        format!("Failed to acquire instance lock {}", lock_path.display())
                    });
                }
            }
        }
    }
}

fn lock_path_for(config_path: &Path) -> Result<PathBuf> {
    let parent = config_path.parent().ok_or_else(|| {
        anyhow!(
            "Configuration path has no parent directory: {}",
            config_path.display()
        )
    })?;
    let file_name = config_path
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| anyhow!("Configuration file name is not valid UTF-8"))?;
    Ok(parent.join(format!(".{file_name}.agent.lock")))
}

fn restart_wait_duration() -> Duration {
    let millis = std::env::var(RESTART_WAIT_ENV)
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .unwrap_or(0)
        .min(60_000);
    Duration::from_millis(millis)
}

#[cfg(unix)]
fn try_acquire(lock_path: &Path) -> std::result::Result<InstanceLock, TryLockError> {
    use std::os::fd::AsRawFd;

    let file = open_lock_file(lock_path).map_err(TryLockError::Io)?;
    let result = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
    if result == 0 {
        return Ok(InstanceLock { file });
    }

    let error = std::io::Error::last_os_error();
    if error.kind() == std::io::ErrorKind::WouldBlock {
        Err(TryLockError::AlreadyRunning)
    } else {
        Err(TryLockError::Io(error))
    }
}

#[cfg(unix)]
fn open_lock_file(lock_path: &Path) -> std::io::Result<File> {
    match OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(lock_path)
    {
        Ok(file) => Ok(file),
        Err(error)
            if error.kind() == std::io::ErrorKind::PermissionDenied && lock_path.exists() =>
        {
            File::open(lock_path)
        }
        Err(error) => Err(error),
    }
}

#[cfg(windows)]
fn try_acquire(lock_path: &Path) -> std::result::Result<InstanceLock, TryLockError> {
    use std::os::windows::fs::OpenOptionsExt;

    match OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .share_mode(0)
        .open(lock_path)
    {
        Ok(file) => Ok(InstanceLock { file }),
        Err(error) if matches!(error.raw_os_error(), Some(32 | 33)) => {
            Err(TryLockError::AlreadyRunning)
        }
        Err(error) => Err(TryLockError::Io(error)),
    }
}

#[cfg(not(any(unix, windows)))]
fn try_acquire(lock_path: &Path) -> std::result::Result<InstanceLock, TryLockError> {
    match OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .open(lock_path)
    {
        Ok(file) => Ok(InstanceLock {
            file,
            path: lock_path.to_path_buf(),
        }),
        Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
            Err(TryLockError::AlreadyRunning)
        }
        Err(error) => Err(TryLockError::Io(error)),
    }
}

#[cfg(not(any(unix, windows)))]
impl Drop for InstanceLock {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_a_second_instance_and_releases_on_drop() {
        let test_dir = std::env::temp_dir().join(format!(
            "nanolink-instance-lock-{}-{}",
            std::process::id(),
            uuid::Uuid::new_v4()
        ));
        std::fs::create_dir_all(&test_dir).unwrap();
        let config_path = test_dir.join("nanolink.yaml");
        std::fs::write(&config_path, "servers: []\n").unwrap();

        let first = InstanceLock::acquire(&config_path).unwrap();
        let second = InstanceLock::acquire(&config_path)
            .err()
            .expect("second instance should be rejected");
        assert!(second.to_string().contains("already running"));

        drop(first);
        InstanceLock::acquire(&config_path).unwrap();

        std::fs::remove_dir_all(test_dir).unwrap();
    }
}
