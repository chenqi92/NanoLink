package com.kkape.sdk.util;

import java.util.regex.Pattern;

/**
 * Utility class for sanitizing input from agents to prevent injection attacks.
 */
public final class SanitizeUtils {

    // Pattern for valid hostname: alphanumeric, hyphen, dot, underscore
    private static final Pattern VALID_HOSTNAME = Pattern
            .compile("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,253}[a-zA-Z0-9]$|^[a-zA-Z0-9]$");

    // Pattern for valid agent ID: UUID format or alphanumeric
    private static final Pattern VALID_AGENT_ID = Pattern.compile("^[a-zA-Z0-9-]{1,64}$");

    // Maximum lengths
    private static final int MAX_HOSTNAME_LENGTH = 255;
    private static final int MAX_STRING_LENGTH = 1024;

    private SanitizeUtils() {
        // Utility class
    }

    /**
     * Sanitize hostname to prevent log injection and path traversal.
     * Removes newlines, control characters, and path traversal sequences.
     */
    public static String sanitizeHostname(String hostname) {
        if (hostname == null || hostname.isEmpty()) {
            return "unknown";
        }

        // Truncate to max length
        if (hostname.length() > MAX_HOSTNAME_LENGTH) {
            hostname = hostname.substring(0, MAX_HOSTNAME_LENGTH);
        }

        // Remove dangerous characters
        hostname = hostname
                .replace("\n", "")
                .replace("\r", "")
                .replace("\t", "")
                .replace("..", "")
                .replace("/", "_")
                .replace("\\", "_")
                .replace("\0", "");

        // If still not valid, replace with sanitized version
        if (!VALID_HOSTNAME.matcher(hostname).matches()) {
            // Keep only safe characters
            hostname = hostname.replaceAll("[^a-zA-Z0-9._-]", "_");
        }

        return hostname.isEmpty() ? "unknown" : hostname;
    }

    /**
     * Sanitize agent ID to prevent injection attacks.
     */
    public static String sanitizeAgentId(String agentId) {
        if (agentId == null || agentId.isEmpty()) {
            return "unknown";
        }

        if (agentId.length() > 64) {
            agentId = agentId.substring(0, 64);
        }

        if (!VALID_AGENT_ID.matcher(agentId).matches()) {
            agentId = agentId.replaceAll("[^a-zA-Z0-9-]", "");
        }

        return agentId.isEmpty() ? "unknown" : agentId;
    }

    /**
     * Sanitize a general string value for safe logging.
     * Removes control characters and truncates to max length.
     */
    public static String sanitizeString(String value) {
        if (value == null) {
            return "";
        }

        if (value.length() > MAX_STRING_LENGTH) {
            value = value.substring(0, MAX_STRING_LENGTH);
        }

        // Remove control characters including newlines for log safety
        return value
                .replace("\n", " ")
                .replace("\r", "")
                .replace("\t", " ")
                .replace("\0", "")
                .replaceAll("[\\p{Cntrl}]", "");
    }

    /**
     * Sanitize a string for use in file paths.
     * Removes path traversal sequences and invalid characters.
     */
    public static String sanitizeForPath(String value) {
        if (value == null || value.isEmpty()) {
            return "unknown";
        }

        return value
                .replace("..", "")
                .replace("/", "_")
                .replace("\\", "_")
                .replace("\0", "")
                .replace(":", "_")
                .replaceAll("[^a-zA-Z0-9._-]", "_");
    }
}
