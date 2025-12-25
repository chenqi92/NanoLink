"""
Agent connection management for NanoLink SDK
"""

import asyncio
import logging
from dataclasses import dataclass, field
from datetime import datetime
from typing import Callable, Optional

from .command import Command, CommandResult

logger = logging.getLogger(__name__)


class PermissionLevel:
    """Permission levels for agent connections"""
    READ_ONLY = 0
    BASIC_WRITE = 1
    SERVICE_CONTROL = 2
    SYSTEM_ADMIN = 3


@dataclass
class AgentInfo:
    """Agent information received during authentication"""
    hostname: str = ""
    agent_version: str = ""
    os: str = ""
    arch: str = ""


@dataclass
class AgentConnection:
    """Represents a connection to a NanoLink agent (gRPC-based)"""
    agent_id: str = ""
    hostname: str = ""
    os: str = ""
    arch: str = ""
    version: str = ""
    permission_level: int = 0
    connected_at: datetime = field(default_factory=datetime.now)
    last_heartbeat: datetime = field(default_factory=datetime.now)

    _stream_sender: Optional[Callable[[bytes], None]] = field(default=None, repr=False)
    _pending_commands: dict = field(default_factory=dict, repr=False)
    _active: bool = field(default=True, repr=False)

    def set_stream_sender(self, sender: Callable[[bytes], None]) -> None:
        """Set the stream sender for sending commands via gRPC"""
        self._stream_sender = sender

    async def send_command(self, command: Command, timeout: float = 30.0) -> CommandResult:
        """
        Send a command to the agent and wait for result

        Args:
            command: The command to execute
            timeout: Timeout in seconds

        Returns:
            CommandResult with the execution result

        Raises:
            TimeoutError: If command times out
            ConnectionError: If agent is disconnected
        """
        if not self._active:
            raise ConnectionError("Agent is not connected")

        if self._stream_sender is None:
            raise ConnectionError("Stream sender not available")

        # Check permission level
        required_level = self._get_required_permission(command)
        if self.permission_level < required_level:
            return CommandResult(
                command_id=command.command_id,
                success=False,
                error=f"Permission denied. Required level: {required_level}, "
                      f"current level: {self.permission_level}",
            )

        # Create future for result
        future: asyncio.Future[CommandResult] = asyncio.Future()
        self._pending_commands[command.command_id] = future

        try:
            # Send command via gRPC stream
            data = command.to_protobuf()
            self._stream_sender(data)

            # Wait for result
            result = await asyncio.wait_for(future, timeout=timeout)
            return result

        except asyncio.TimeoutError:
            return CommandResult(
                command_id=command.command_id,
                success=False,
                error=f"Command timed out after {timeout} seconds",
            )
        finally:
            self._pending_commands.pop(command.command_id, None)

    def _get_required_permission(self, command: Command) -> int:
        """Get required permission level for a command"""
        from .command import CommandType

        # READ_ONLY (0)
        if command.command_type in [
            CommandType.PROCESS_LIST,
            CommandType.SERVICE_STATUS,
            CommandType.FILE_TAIL,
            CommandType.DOCKER_LIST,
            CommandType.DOCKER_LOGS,
        ]:
            return 0

        # BASIC_WRITE (1)
        if command.command_type in [
            CommandType.FILE_DOWNLOAD,
            CommandType.FILE_TRUNCATE,
        ]:
            return 1

        # SERVICE_CONTROL (2)
        if command.command_type in [
            CommandType.PROCESS_KILL,
            CommandType.SERVICE_START,
            CommandType.SERVICE_STOP,
            CommandType.SERVICE_RESTART,
            CommandType.DOCKER_START,
            CommandType.DOCKER_STOP,
            CommandType.DOCKER_RESTART,
        ]:
            return 2

        # SYSTEM_ADMIN (3)
        if command.command_type in [
            CommandType.SYSTEM_REBOOT,
            CommandType.SHELL_EXECUTE,
            CommandType.FILE_UPLOAD,
        ]:
            return 3

        return 0

    def _handle_command_result(self, data: dict) -> None:
        """Handle incoming command result"""
        result = CommandResult.from_dict(data)
        future = self._pending_commands.get(result.command_id)
        if future and not future.done():
            future.set_result(result)

    async def close(self) -> None:
        """Close the agent connection"""
        self._active = False

    @property
    def is_connected(self) -> bool:
        """Check if agent is connected"""
        return self._active


@dataclass
class ValidationResult:
    """Token validation result"""
    valid: bool = False
    permission_level: int = 0
    error_message: str = ""


# Type alias for token validator
TokenValidator = Callable[[str], ValidationResult]


def default_token_validator(token: str) -> ValidationResult:
    """Default token validator that accepts all tokens with read-only permission"""
    return ValidationResult(valid=True, permission_level=0)
