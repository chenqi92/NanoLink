//! Hardware-based stable agent ID generation
//!
//! This module generates a persistent, hardware-based agent ID that remains
//! consistent across restarts. It uses OS-native machine identifiers with
//! fallbacks for robustness.
//!
//! # Format
//! `nanolink-agent-{5 char hash}`
//!
//! # Platform Sources
//! - Linux: /etc/machine-id or /var/lib/dbus/machine-id
//! - macOS: IOPlatformUUID
//! - Windows: HKLM\SOFTWARE\Microsoft\Cryptography\MachineGuid
//! - BSD: /etc/hostid or smbios.system.uuid

use sha2::{Digest, Sha256};
use std::fmt::Write;

/// Generates a stable hardware-based agent ID.
///
/// Returns a string in format: `nanolink-agent-{5 char hash}`
///
/// The hash is derived from the OS-native machine identifier, with fallbacks
/// to hostname if the primary source is unavailable.
pub fn generate_hardware_agent_id() -> String {
    let raw_id = get_machine_id();
    let hash = hash_to_short_hex(&raw_id, 5);
    format!("nanolink-agent-{}", hash.to_uppercase())
}

/// Gets the raw machine identifier from the OS.
///
/// Uses machine_uid crate as primary source, with hostname fallback.
fn get_machine_id() -> String {
    // Try machine_uid first (cross-platform, no admin required)
    if let Ok(id) = machine_uid::get() {
        if !id.is_empty() {
            tracing::debug!(
                "Got machine ID from machine_uid: {}...",
                &id[..id.len().min(8)]
            );
            return id;
        }
    }

    // Fallback: use hostname + platform info
    let hostname = get_hostname();
    let platform = get_platform_info();
    let fallback_id = format!("{}-{}", hostname, platform);
    tracing::warn!(
        "machine_uid unavailable, using fallback ID based on hostname: {}",
        hostname
    );
    fallback_id
}

/// Gets the system hostname.
fn get_hostname() -> String {
    hostname::get()
        .ok()
        .and_then(|h| h.into_string().ok())
        .unwrap_or_else(|| "unknown-host".to_string())
}

/// Gets platform-specific info for fallback ID generation.
fn get_platform_info() -> String {
    #[cfg(target_os = "linux")]
    {
        // Try to read additional info from /sys
        if let Ok(product_uuid) = std::fs::read_to_string("/sys/class/dmi/id/product_uuid") {
            return product_uuid.trim().to_string();
        }
        if let Ok(board_serial) = std::fs::read_to_string("/sys/class/dmi/id/board_serial") {
            return board_serial.trim().to_string();
        }
        "linux".to_string()
    }

    #[cfg(target_os = "macos")]
    {
        // macos will typically have IOPlatformUUID available via machine_uid
        "macos".to_string()
    }

    #[cfg(target_os = "windows")]
    {
        // Windows will typically have MachineGuid available via machine_uid
        "windows".to_string()
    }

    #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
    {
        std::env::consts::OS.to_string()
    }
}

/// Hashes a string and returns the first N characters as hex.
fn hash_to_short_hex(input: &str, len: usize) -> String {
    let mut hasher = Sha256::new();
    hasher.update(input.as_bytes());
    let result = hasher.finalize();

    // Convert first bytes to hex string
    let mut hex = String::with_capacity(len);
    for byte in result.iter().take((len + 1) / 2) {
        write!(hex, "{:02x}", byte).unwrap();
    }
    hex.truncate(len);
    hex
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_hardware_agent_id_format() {
        let id = generate_hardware_agent_id();
        assert!(id.starts_with("nanolink-agent-"));
        // Should be "nanolink-agent-" (15 chars) + 5 char hash
        assert_eq!(id.len(), 20);
        // Hash part should be uppercase hex
        let hash_part = &id[15..];
        assert!(hash_part.chars().all(|c| c.is_ascii_hexdigit()));
        assert!(
            hash_part
                .chars()
                .all(|c| c.is_uppercase() || c.is_ascii_digit())
        );
    }

    #[test]
    fn test_consistent_id_generation() {
        // ID should be consistent across calls
        let id1 = generate_hardware_agent_id();
        let id2 = generate_hardware_agent_id();
        assert_eq!(id1, id2);
    }

    #[test]
    fn test_hash_to_short_hex() {
        let hash = hash_to_short_hex("test-input", 5);
        assert_eq!(hash.len(), 5);
        assert!(hash.chars().all(|c| c.is_ascii_hexdigit()));
    }
}
