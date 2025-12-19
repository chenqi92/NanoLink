/// Platform-specific implementations
///
/// This module contains platform-specific code for Windows, Linux, and macOS.

#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "windows")]
mod windows;

#[cfg(target_os = "linux")]
pub use linux::*;
#[cfg(target_os = "windows")]
pub use windows::*;

/// Get the current platform name
pub fn platform_name() -> &'static str {
    #[cfg(target_os = "linux")]
    return "linux";

    #[cfg(target_os = "macos")]
    return "macos";

    #[cfg(target_os = "windows")]
    return "windows";

    #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
    return "unknown";
}

/// Get the current architecture
pub fn arch_name() -> &'static str {
    std::env::consts::ARCH
}
