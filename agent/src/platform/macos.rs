/// macOS-specific implementations
use std::process::Command;
use std::thread;
use std::time::Duration;

const LAUNCHD_PLIST: &str = "/Library/LaunchDaemons/com.nanolink.agent.plist";

/// Install as launchd service
pub fn install_service() -> Result<(), String> {
    // TODO: Implement launchd service installation
    Err("Not implemented".to_string())
}

/// Uninstall launchd service
pub fn uninstall_service() -> Result<(), String> {
    // TODO: Implement launchd service uninstallation
    Err("Not implemented".to_string())
}

/// Restart the nanolink-agent launchd service
pub fn restart_service() -> Result<(), String> {
    // Unload the service
    let unload = Command::new("launchctl")
        .args(["unload", "-w", LAUNCHD_PLIST])
        .output()
        .map_err(|e| format!("Failed to execute launchctl unload: {e}"))?;

    if !unload.status.success() {
        // Service might not be loaded, continue anyway
        eprintln!(
            "Warning: launchctl unload: {}",
            String::from_utf8_lossy(&unload.stderr)
        );
    }

    // Wait a moment for the service to stop
    thread::sleep(Duration::from_secs(1));

    // Load the service
    let load = Command::new("launchctl")
        .args(["load", "-w", LAUNCHD_PLIST])
        .output()
        .map_err(|e| format!("Failed to execute launchctl load: {e}"))?;

    if load.status.success() {
        Ok(())
    } else {
        Err(format!(
            "launchctl load failed: {}",
            String::from_utf8_lossy(&load.stderr)
        ))
    }
}

/// Check if the agent service is running
pub fn is_service_running() -> bool {
    Command::new("launchctl")
        .args(["list", "com.nanolink.agent"])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}
