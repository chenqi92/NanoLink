"""
Input sanitization utilities for NanoLink Python SDK.
Prevents log injection, path traversal, and other injection attacks from malicious agents.
"""

import re
from typing import Optional

# Constants
MAX_HOSTNAME_LENGTH = 255
MAX_STRING_LENGTH = 1024
MAX_AGENT_ID_LENGTH = 64

# Regex patterns
VALID_HOSTNAME_PATTERN = re.compile(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,253}[a-zA-Z0-9]$|^[a-zA-Z0-9]$')
VALID_AGENT_ID_PATTERN = re.compile(r'^[a-zA-Z0-9-]{1,64}$')
SAFE_CHAR_PATTERN = re.compile(r'[^a-zA-Z0-9._-]')


def sanitize_hostname(hostname: Optional[str]) -> str:
    """
    Sanitize hostname to prevent log injection and path traversal.
    
    Args:
        hostname: The raw hostname from agent
        
    Returns:
        Sanitized hostname safe for logging and file paths
    """
    if not hostname:
        return "unknown"
    
    # Truncate to max length
    if len(hostname) > MAX_HOSTNAME_LENGTH:
        hostname = hostname[:MAX_HOSTNAME_LENGTH]
    
    # Remove dangerous characters
    hostname = hostname.replace("\n", "")
    hostname = hostname.replace("\r", "")
    hostname = hostname.replace("\t", "")
    hostname = hostname.replace("..", "")
    hostname = hostname.replace("/", "_")
    hostname = hostname.replace("\\", "_")
    hostname = hostname.replace("\x00", "")
    
    # If not valid, replace unsafe characters
    if not VALID_HOSTNAME_PATTERN.match(hostname):
        hostname = SAFE_CHAR_PATTERN.sub("_", hostname)
    
    return hostname if hostname else "unknown"


def sanitize_agent_id(agent_id: Optional[str]) -> str:
    """
    Sanitize agent ID to prevent injection attacks.
    
    Args:
        agent_id: The raw agent ID
        
    Returns:
        Sanitized agent ID
    """
    if not agent_id:
        return "unknown"
    
    if len(agent_id) > MAX_AGENT_ID_LENGTH:
        agent_id = agent_id[:MAX_AGENT_ID_LENGTH]
    
    if not VALID_AGENT_ID_PATTERN.match(agent_id):
        agent_id = re.sub(r'[^a-zA-Z0-9-]', '', agent_id)
    
    return agent_id if agent_id else "unknown"


def sanitize_string(value: Optional[str]) -> str:
    """
    Sanitize a general string for safe logging.
    
    Args:
        value: The raw string value
        
    Returns:
        Sanitized string safe for logging
    """
    if not value:
        return ""
    
    if len(value) > MAX_STRING_LENGTH:
        value = value[:MAX_STRING_LENGTH]
    
    # Remove control characters for log safety
    value = value.replace("\n", " ")
    value = value.replace("\r", "")
    value = value.replace("\t", " ")
    value = value.replace("\x00", "")
    
    return value


def sanitize_for_path(value: Optional[str]) -> str:
    """
    Sanitize a string for use in file paths.
    
    Args:
        value: The raw string value
        
    Returns:
        Sanitized string safe for file paths
    """
    if not value:
        return "unknown"
    
    value = value.replace("..", "")
    value = value.replace("/", "_")
    value = value.replace("\\", "_")
    value = value.replace("\x00", "")
    value = value.replace(":", "_")
    value = SAFE_CHAR_PATTERN.sub("_", value)
    
    return value if value else "unknown"
