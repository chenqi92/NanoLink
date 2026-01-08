//! Token management for Management API
//!
//! Handles generation and rotation of management tokens.

use uuid::Uuid;

/// Generate a new management token
#[allow(dead_code)]
pub fn generate_management_token() -> String {
    // Use UUID v4 for secure random token
    Uuid::new_v4().to_string()
}

/// Generate a cryptographically secure token with specified length
pub fn generate_secure_token(prefix: Option<&str>) -> String {
    let token = Uuid::new_v4().to_string().replace("-", "");
    match prefix {
        Some(p) => format!("{p}_{token}"),
        None => format!("mgmt_{token}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_token() {
        let token1 = generate_management_token();
        let token2 = generate_management_token();

        // Tokens should be unique
        assert_ne!(token1, token2);

        // UUID format: 8-4-4-4-12 = 36 chars
        assert_eq!(token1.len(), 36);
    }

    #[test]
    fn test_generate_secure_token() {
        let token = generate_secure_token(Some("test"));
        assert!(token.starts_with("test_"));

        let token = generate_secure_token(None);
        assert!(token.starts_with("mgmt_"));
    }
}
