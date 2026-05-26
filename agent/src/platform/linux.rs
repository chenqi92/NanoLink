/// Linux-specific implementations.
///
/// systemd service install/uninstall are intentionally NOT exposed here — the
/// real implementations live in main.rs (`install_systemd_service` /
/// `uninstall_systemd_service`) because they need access to the parsed CLI
/// args (config path, run user, etc.). Earlier versions had stub functions
/// here that always returned "Not implemented", which were never called but
/// confused readers into thinking install was a TODO. They've been removed.
use std::process::Command;

/// Restart the nanolink-agent systemd service
pub fn restart_service() -> Result<(), String> {
    let output = Command::new("systemctl")
        .args(["restart", "nanolink-agent"])
        .output()
        .map_err(|e| format!("Failed to execute systemctl: {e}"))?;

    if output.status.success() {
        Ok(())
    } else {
        Err(format!(
            "systemctl restart failed: {}",
            String::from_utf8_lossy(&output.stderr)
        ))
    }
}

/// Check if the agent service is running
pub fn is_service_running() -> bool {
    Command::new("systemctl")
        .args(["is-active", "--quiet", "nanolink-agent"])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}
