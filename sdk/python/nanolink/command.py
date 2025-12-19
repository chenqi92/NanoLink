"""
Command models for NanoLink SDK
"""

from dataclasses import dataclass, field
from enum import IntEnum
from typing import Dict, Optional
import uuid


class CommandType(IntEnum):
    """Command types that can be executed on agents"""
    UNSPECIFIED = 0

    # Process management
    PROCESS_LIST = 1
    PROCESS_KILL = 2

    # Service management
    SERVICE_START = 10
    SERVICE_STOP = 11
    SERVICE_RESTART = 12
    SERVICE_STATUS = 13

    # File operations
    FILE_TAIL = 20
    FILE_DOWNLOAD = 21
    FILE_UPLOAD = 22
    FILE_TRUNCATE = 23

    # Docker operations
    DOCKER_LIST = 30
    DOCKER_START = 31
    DOCKER_STOP = 32
    DOCKER_RESTART = 33
    DOCKER_LOGS = 34

    # System operations
    SYSTEM_REBOOT = 40

    # Shell command (requires SuperToken)
    SHELL_EXECUTE = 50


@dataclass
class Command:
    """Command to be executed on an agent"""
    command_type: CommandType
    target: str = ""
    params: Dict[str, str] = field(default_factory=dict)
    super_token: str = ""
    command_id: str = field(default_factory=lambda: str(uuid.uuid4()))

    def to_dict(self) -> dict:
        """Convert command to dictionary"""
        return {
            "commandId": self.command_id,
            "type": self.command_type.value,
            "target": self.target,
            "params": self.params,
            "superToken": self.super_token,
        }

    @classmethod
    def process_list(cls) -> "Command":
        """Create a process list command"""
        return cls(command_type=CommandType.PROCESS_LIST)

    @classmethod
    def process_kill(cls, pid: int) -> "Command":
        """Create a process kill command"""
        return cls(
            command_type=CommandType.PROCESS_KILL,
            target=str(pid),
        )

    @classmethod
    def service_start(cls, service_name: str) -> "Command":
        """Create a service start command"""
        return cls(
            command_type=CommandType.SERVICE_START,
            target=service_name,
        )

    @classmethod
    def service_stop(cls, service_name: str) -> "Command":
        """Create a service stop command"""
        return cls(
            command_type=CommandType.SERVICE_STOP,
            target=service_name,
        )

    @classmethod
    def service_restart(cls, service_name: str) -> "Command":
        """Create a service restart command"""
        return cls(
            command_type=CommandType.SERVICE_RESTART,
            target=service_name,
        )

    @classmethod
    def service_status(cls, service_name: str) -> "Command":
        """Create a service status command"""
        return cls(
            command_type=CommandType.SERVICE_STATUS,
            target=service_name,
        )

    @classmethod
    def file_tail(cls, file_path: str, lines: int = 100) -> "Command":
        """Create a file tail command"""
        return cls(
            command_type=CommandType.FILE_TAIL,
            target=file_path,
            params={"lines": str(lines)},
        )

    @classmethod
    def docker_list(cls) -> "Command":
        """Create a docker list command"""
        return cls(command_type=CommandType.DOCKER_LIST)

    @classmethod
    def docker_restart(cls, container: str) -> "Command":
        """Create a docker restart command"""
        return cls(
            command_type=CommandType.DOCKER_RESTART,
            target=container,
        )

    @classmethod
    def docker_logs(cls, container: str, tail: int = 100) -> "Command":
        """Create a docker logs command"""
        return cls(
            command_type=CommandType.DOCKER_LOGS,
            target=container,
            params={"tail": str(tail)},
        )

    @classmethod
    def shell_execute(cls, command: str, super_token: str) -> "Command":
        """Create a shell execute command (requires SuperToken)"""
        return cls(
            command_type=CommandType.SHELL_EXECUTE,
            target=command,
            super_token=super_token,
        )


@dataclass
class CommandResult:
    """Result of a command execution"""
    command_id: str = ""
    success: bool = False
    output: str = ""
    error: str = ""
    file_content: Optional[bytes] = None

    @classmethod
    def from_dict(cls, data: dict) -> "CommandResult":
        """Create CommandResult from dictionary"""
        return cls(
            command_id=data.get("commandId", ""),
            success=data.get("success", False),
            output=data.get("output", ""),
            error=data.get("error", ""),
            file_content=data.get("fileContent"),
        )
