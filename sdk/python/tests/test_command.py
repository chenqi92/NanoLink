"""Tests for command module"""

import pytest
from nanolink.command import Command, CommandType, CommandResult


class TestCommandType:
    def test_command_types_exist(self):
        assert CommandType.PROCESS_LIST == 1
        assert CommandType.PROCESS_KILL == 2
        assert CommandType.SERVICE_START == 10
        assert CommandType.SERVICE_STOP == 11
        assert CommandType.SERVICE_RESTART == 12
        assert CommandType.DOCKER_LIST == 30
        assert CommandType.SHELL_EXECUTE == 50


class TestCommand:
    def test_default_values(self):
        cmd = Command(command_type=CommandType.PROCESS_LIST)
        assert cmd.command_type == CommandType.PROCESS_LIST
        assert cmd.target == ""
        assert cmd.params == {}
        assert cmd.super_token == ""
        assert cmd.command_id  # Should have a UUID

    def test_to_dict(self):
        cmd = Command(
            command_type=CommandType.SERVICE_RESTART,
            target="nginx",
        )
        data = cmd.to_dict()
        assert data["type"] == CommandType.SERVICE_RESTART.value
        assert data["target"] == "nginx"
        assert data["commandId"] == cmd.command_id

    def test_process_list(self):
        cmd = Command.process_list()
        assert cmd.command_type == CommandType.PROCESS_LIST

    def test_process_kill(self):
        cmd = Command.process_kill(1234)
        assert cmd.command_type == CommandType.PROCESS_KILL
        assert cmd.target == "1234"

    def test_service_start(self):
        cmd = Command.service_start("nginx")
        assert cmd.command_type == CommandType.SERVICE_START
        assert cmd.target == "nginx"

    def test_service_stop(self):
        cmd = Command.service_stop("nginx")
        assert cmd.command_type == CommandType.SERVICE_STOP
        assert cmd.target == "nginx"

    def test_service_restart(self):
        cmd = Command.service_restart("nginx")
        assert cmd.command_type == CommandType.SERVICE_RESTART
        assert cmd.target == "nginx"

    def test_service_status(self):
        cmd = Command.service_status("nginx")
        assert cmd.command_type == CommandType.SERVICE_STATUS
        assert cmd.target == "nginx"

    def test_file_tail(self):
        cmd = Command.file_tail("/var/log/syslog", lines=50)
        assert cmd.command_type == CommandType.FILE_TAIL
        assert cmd.target == "/var/log/syslog"
        assert cmd.params["lines"] == "50"

    def test_file_tail_default_lines(self):
        cmd = Command.file_tail("/var/log/syslog")
        assert cmd.params["lines"] == "100"

    def test_docker_list(self):
        cmd = Command.docker_list()
        assert cmd.command_type == CommandType.DOCKER_LIST

    def test_docker_restart(self):
        cmd = Command.docker_restart("my-container")
        assert cmd.command_type == CommandType.DOCKER_RESTART
        assert cmd.target == "my-container"

    def test_docker_logs(self):
        cmd = Command.docker_logs("my-container", tail=50)
        assert cmd.command_type == CommandType.DOCKER_LOGS
        assert cmd.target == "my-container"
        assert cmd.params["tail"] == "50"

    def test_shell_execute(self):
        cmd = Command.shell_execute("df -h", super_token="secret-token")
        assert cmd.command_type == CommandType.SHELL_EXECUTE
        assert cmd.target == "df -h"
        assert cmd.super_token == "secret-token"


class TestCommandResult:
    def test_default_values(self):
        result = CommandResult()
        assert result.command_id == ""
        assert result.success is False
        assert result.output == ""
        assert result.error == ""
        assert result.file_content is None

    def test_from_dict(self):
        data = {
            "commandId": "test-123",
            "success": True,
            "output": "Command output",
            "error": "",
        }
        result = CommandResult.from_dict(data)
        assert result.command_id == "test-123"
        assert result.success is True
        assert result.output == "Command output"
        assert result.error == ""

    def test_from_dict_with_error(self):
        data = {
            "commandId": "test-456",
            "success": False,
            "output": "",
            "error": "Permission denied",
        }
        result = CommandResult.from_dict(data)
        assert result.success is False
        assert result.error == "Permission denied"

    def test_from_dict_missing_fields(self):
        data = {}
        result = CommandResult.from_dict(data)
        assert result.command_id == ""
        assert result.success is False
        assert result.output == ""
        assert result.error == ""
