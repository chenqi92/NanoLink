//! Input validation utilities for security

use tracing::warn;

/// Validates a Docker container name or ID
/// Container names must match: ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$
/// Container IDs are 12 or 64 character hex strings
pub fn validate_container_name(name: &str) -> Result<(), String> {
    if name.is_empty() {
        return Err("Container name cannot be empty".to_string());
    }

    // Check for dangerous shell metacharacters
    const DANGEROUS_CHARS: &[char] = &[';', '|', '&', '$', '`', '(', ')', '{', '}', '<', '>', '\n', '\r', '\\', '"', '\''];
    
    for c in name.chars() {
        if DANGEROUS_CHARS.contains(&c) {
            warn!("[SECURITY] Blocked container name with dangerous character: {}", name);
            return Err(format!("Container name contains forbidden character: '{}'", c));
        }
    }

    // Check if it looks like a container ID (hex string)
    if name.len() == 12 || name.len() == 64 {
        if name.chars().all(|c| c.is_ascii_hexdigit()) {
            return Ok(());
        }
    }

    // Validate container name format: ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$
    let mut chars = name.chars();
    if let Some(first) = chars.next() {
        if !first.is_ascii_alphanumeric() {
            return Err("Container name must start with alphanumeric character".to_string());
        }
    }

    for c in name.chars() {
        if !c.is_ascii_alphanumeric() && c != '_' && c != '.' && c != '-' {
            return Err(format!("Container name contains invalid character: '{}'", c));
        }
    }

    Ok(())
}

/// Validates a service name
/// Service names should be: letters, digits, _, -, @, .
pub fn validate_service_name(name: &str) -> Result<(), String> {
    if name.is_empty() {
        return Err("Service name cannot be empty".to_string());
    }

    // Check for dangerous shell metacharacters
    const DANGEROUS_CHARS: &[char] = &[';', '|', '&', '$', '`', '(', ')', '{', '}', '<', '>', '\n', '\r', '\\', '"', '\'', ' ', '\t'];
    
    for c in name.chars() {
        if DANGEROUS_CHARS.contains(&c) {
            warn!("[SECURITY] Blocked service name with dangerous character: {}", name);
            return Err(format!("Service name contains forbidden character: '{}'", c));
        }
    }

    // Validate allowed characters
    for c in name.chars() {
        if !c.is_ascii_alphanumeric() && c != '_' && c != '-' && c != '@' && c != '.' {
            return Err(format!("Service name contains invalid character: '{}'", c));
        }
    }

    Ok(())
}

/// Validates a process name for kill operations
pub fn validate_process_name(name: &str) -> Result<(), String> {
    if name.is_empty() {
        return Err("Process name cannot be empty".to_string());
    }

    // Check for dangerous shell metacharacters
    const DANGEROUS_CHARS: &[char] = &[';', '|', '&', '$', '`', '(', ')', '{', '}', '<', '>', '\n', '\r', '\\', '"', '\''];
    
    for c in name.chars() {
        if DANGEROUS_CHARS.contains(&c) {
            warn!("[SECURITY] Blocked process name with dangerous character: {}", name);
            return Err(format!("Process name contains forbidden character: '{}'", c));
        }
    }

    Ok(())
}

/// Check if a PID is a protected system process
/// Returns Err if the process should not be killed
pub fn validate_pid_killable(pid: u32) -> Result<(), String> {
    // PID 0 is the kernel scheduler (swapper/sched)
    // PID 1 is init/systemd
    if pid == 0 {
        return Err("Cannot kill PID 0 (kernel scheduler)".to_string());
    }
    
    if pid == 1 {
        return Err("Cannot kill PID 1 (init/systemd)".to_string());
    }

    // PIDs below 100 are typically kernel threads and critical system processes
    // This is a conservative protection - users can still kill most processes
    if pid < 10 {
        warn!("[SECURITY] Blocked kill of low PID: {}", pid);
        return Err(format!("Cannot kill PID {} (protected system process)", pid));
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_container_name_validation() {
        assert!(validate_container_name("nginx").is_ok());
        assert!(validate_container_name("my-container").is_ok());
        assert!(validate_container_name("my_container.1").is_ok());
        assert!(validate_container_name("abc123def456").is_ok()); // 12-char hex ID
        
        assert!(validate_container_name("").is_err());
        assert!(validate_container_name("foo;rm -rf /").is_err());
        assert!(validate_container_name("foo|cat").is_err());
        assert!(validate_container_name("$(whoami)").is_err());
    }

    #[test]
    fn test_service_name_validation() {
        assert!(validate_service_name("nginx").is_ok());
        assert!(validate_service_name("my-service").is_ok());
        assert!(validate_service_name("service@instance").is_ok());
        
        assert!(validate_service_name("").is_err());
        assert!(validate_service_name("foo;id").is_err());
        assert!(validate_service_name("foo bar").is_err());
    }

    #[test]
    fn test_pid_protection() {
        assert!(validate_pid_killable(0).is_err());
        assert!(validate_pid_killable(1).is_err());
        assert!(validate_pid_killable(5).is_err());
        assert!(validate_pid_killable(100).is_ok());
        assert!(validate_pid_killable(12345).is_ok());
    }
}
