"""
Agent connection management for NanoLink SDK
"""

import asyncio
import logging
import threading
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

    _stream_sender: Optional[Callable[[object], None]] = field(default=None, repr=False)
    _pending_commands: dict = field(default_factory=dict, repr=False)
    _active: bool = field(default=True, repr=False)

    def set_stream_sender(self, sender: Callable[[object], None]) -> None:
        """Set the stream sender for dispatching commands via the gRPC stream.

        The sender receives a MetricsStreamResponse protobuf message to enqueue
        onto the agent's response stream.
        """
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

        # Create future for result, tracking the owning loop so the synchronous
        # gRPC servicer thread can complete it via call_soon_threadsafe.
        loop = asyncio.get_running_loop()
        future: asyncio.Future = loop.create_future()
        self._pending_commands[command.command_id] = ("async", future, loop)

        try:
            # Send command to the agent as a Command message on the stream.
            from .proto import nanolink_pb2 as _pb
            self._stream_sender(_pb.MetricsStreamResponse(command=command.to_proto()))

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
        ]:
            return 0

        # BASIC_WRITE (1)
        if command.command_type in [
            CommandType.FILE_DOWNLOAD,
            CommandType.FILE_TRUNCATE,
            CommandType.DOCKER_LOGS,
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

        # Unknown/unspecified commands are fail-closed at SYSTEM_ADMIN (3)
        return 3

    def handle_command_result(self, result: CommandResult) -> None:
        """Complete the pending command waiter for this result.

        Safe to call from the synchronous gRPC servicer thread: async waiters are
        completed via their event loop, blocking waiters via a threading.Event.
        """
        entry = self._pending_commands.get(result.command_id)
        if not entry:
            return
        kind = entry[0]
        if kind == "async":
            _, future, loop = entry
            if not future.done():
                loop.call_soon_threadsafe(future.set_result, result)
        elif kind == "sync":
            _, event, box = entry
            box["result"] = result
            event.set()

    def send_command_blocking(self, command: Command, timeout: float = 30.0) -> CommandResult:
        """Synchronous command dispatch for non-async callers (e.g. unary RPC).

        Mirrors send_command but blocks the calling thread instead of awaiting,
        so it is safe to call from the gRPC servicer's thread pool.
        """
        if not self._active:
            return CommandResult(command_id=command.command_id, success=False,
                                 error="Agent is not connected")
        if self._stream_sender is None:
            return CommandResult(command_id=command.command_id, success=False,
                                 error="Stream sender not available")

        required_level = self._get_required_permission(command)
        if self.permission_level < required_level:
            return CommandResult(
                command_id=command.command_id, success=False,
                error=f"Permission denied. Required level: {required_level}, "
                      f"current level: {self.permission_level}",
            )

        event = threading.Event()
        box: dict = {}
        self._pending_commands[command.command_id] = ("sync", event, box)
        try:
            from .proto import nanolink_pb2 as _pb
            self._stream_sender(_pb.MetricsStreamResponse(command=command.to_proto()))
            if event.wait(timeout):
                return box.get("result") or CommandResult(
                    command_id=command.command_id, success=False, error="empty result")
            return CommandResult(command_id=command.command_id, success=False,
                                 error=f"Command timed out after {timeout} seconds")
        finally:
            self._pending_commands.pop(command.command_id, None)

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
