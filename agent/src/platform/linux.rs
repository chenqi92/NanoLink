/// Linux-specific implementations
use std::process::Command;

/// Install as systemd service
pub fn install_service() -> Result<(), String> {
    // TODO: Implement systemd service installation
    Err("Not implemented".to_string())
}

/// Uninstall systemd service
pub fn uninstall_service() -> Result<(), String> {
    // TODO: Implement systemd service uninstallation
    Err("Not implemented".to_string())
}

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
