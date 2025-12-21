package nanolink

import (
	"regexp"
	"strings"
)

// Constants for sanitization
const (
	MaxHostnameLength = 255
	MaxStringLength   = 1024
	MaxAgentIDLength  = 64
)

var (
	// validHostnamePattern matches valid hostname characters
	validHostnamePattern = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9._-]{0,253}[a-zA-Z0-9]$|^[a-zA-Z0-9]$`)
	// validAgentIDPattern matches valid agent ID characters
	validAgentIDPattern = regexp.MustCompile(`^[a-zA-Z0-9-]{1,64}$`)
	// safeCharPattern matches safe characters only
	safeCharPattern = regexp.MustCompile(`[^a-zA-Z0-9._-]`)
)

// SanitizeHostname sanitizes a hostname to prevent log injection and path traversal.
func SanitizeHostname(hostname string) string {
	if hostname == "" {
		return "unknown"
	}

	// Truncate to max length
	if len(hostname) > MaxHostnameLength {
		hostname = hostname[:MaxHostnameLength]
	}

	// Remove dangerous characters
	hostname = strings.ReplaceAll(hostname, "\n", "")
	hostname = strings.ReplaceAll(hostname, "\r", "")
	hostname = strings.ReplaceAll(hostname, "\t", "")
	hostname = strings.ReplaceAll(hostname, "..", "")
	hostname = strings.ReplaceAll(hostname, "/", "_")
	hostname = strings.ReplaceAll(hostname, "\\", "_")
	hostname = strings.ReplaceAll(hostname, "\x00", "")

	// If not valid, replace unsafe characters
	if !validHostnamePattern.MatchString(hostname) {
		hostname = safeCharPattern.ReplaceAllString(hostname, "_")
	}

	if hostname == "" {
		return "unknown"
	}
	return hostname
}

// SanitizeAgentID sanitizes an agent ID to prevent injection attacks.
func SanitizeAgentID(agentID string) string {
	if agentID == "" {
		return "unknown"
	}

	if len(agentID) > MaxAgentIDLength {
		agentID = agentID[:MaxAgentIDLength]
	}

	if !validAgentIDPattern.MatchString(agentID) {
		agentID = regexp.MustCompile(`[^a-zA-Z0-9-]`).ReplaceAllString(agentID, "")
	}

	if agentID == "" {
		return "unknown"
	}
	return agentID
}

// SanitizeString sanitizes a general string for safe logging.
func SanitizeString(value string) string {
	if value == "" {
		return ""
	}

	if len(value) > MaxStringLength {
		value = value[:MaxStringLength]
	}

	// Remove control characters for log safety
	value = strings.ReplaceAll(value, "\n", " ")
	value = strings.ReplaceAll(value, "\r", "")
	value = strings.ReplaceAll(value, "\t", " ")
	value = strings.ReplaceAll(value, "\x00", "")

	return value
}

// SanitizeForPath sanitizes a string for use in file paths.
func SanitizeForPath(value string) string {
	if value == "" {
		return "unknown"
	}

	value = strings.ReplaceAll(value, "..", "")
	value = strings.ReplaceAll(value, "/", "_")
	value = strings.ReplaceAll(value, "\\", "_")
	value = strings.ReplaceAll(value, "\x00", "")
	value = strings.ReplaceAll(value, ":", "_")
	value = safeCharPattern.ReplaceAllString(value, "_")

	if value == "" {
		return "unknown"
	}
	return value
}
