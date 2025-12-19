package io.nanolink.sdk;

/**
 * Token validator interface for authenticating agents
 */
@FunctionalInterface
public interface TokenValidator {

    /**
     * Validate a token and return the permission level
     *
     * @param token The authentication token
     * @return ValidationResult with success status and permission level
     */
    ValidationResult validate(String token);

    /**
     * Result of token validation
     */
    class ValidationResult {
        private final boolean valid;
        private final int permissionLevel;
        private final String errorMessage;

        public ValidationResult(boolean valid, int permissionLevel) {
            this(valid, permissionLevel, null);
        }

        public ValidationResult(boolean valid, int permissionLevel, String errorMessage) {
            this.valid = valid;
            this.permissionLevel = permissionLevel;
            this.errorMessage = errorMessage;
        }

        public boolean isValid() {
            return valid;
        }

        public int getPermissionLevel() {
            return permissionLevel;
        }

        public String getErrorMessage() {
            return errorMessage;
        }

        public static ValidationResult success(int permissionLevel) {
            return new ValidationResult(true, permissionLevel);
        }

        public static ValidationResult failure(String message) {
            return new ValidationResult(false, 0, message);
        }
    }

    /**
     * Permission levels
     */
    interface PermissionLevel {
        int READ_ONLY = 0;
        int BASIC_WRITE = 1;
        int SERVICE_CONTROL = 2;
        int SYSTEM_ADMIN = 3;
    }
}
