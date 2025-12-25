"""Tests for server module"""

import pytest
from nanolink.server import NanoLinkServer, ServerConfig
from nanolink.connection import ValidationResult, default_token_validator


class TestServerConfig:
    def test_default_values(self):
        config = ServerConfig()
        assert config.grpc_port == 39100
        assert config.host == "0.0.0.0"
        assert config.tls_cert_path is None
        assert config.tls_key_path is None

    def test_custom_values(self):
        config = ServerConfig(
            grpc_port=39200,
            host="127.0.0.1",
            tls_cert_path="/path/to/cert.pem",
            tls_key_path="/path/to/key.pem",
        )
        assert config.grpc_port == 39200
        assert config.host == "127.0.0.1"
        assert config.tls_cert_path == "/path/to/cert.pem"
        assert config.tls_key_path == "/path/to/key.pem"


class TestDefaultTokenValidator:
    def test_accepts_any_token(self):
        result = default_token_validator("any-token")
        assert result.valid is True
        assert result.permission_level == 0

    def test_returns_read_only_permission(self):
        result = default_token_validator("test-token")
        assert result.permission_level == 0


class TestCustomTokenValidator:
    def test_custom_validator(self):
        def custom_validator(token: str) -> ValidationResult:
            if token == "admin":
                return ValidationResult(valid=True, permission_level=3)
            elif token == "user":
                return ValidationResult(valid=True, permission_level=0)
            else:
                return ValidationResult(valid=False, error_message="Invalid token")

        config = ServerConfig(token_validator=custom_validator)

        result = config.token_validator("admin")
        assert result.valid is True
        assert result.permission_level == 3

        result = config.token_validator("user")
        assert result.valid is True
        assert result.permission_level == 0

        result = config.token_validator("invalid")
        assert result.valid is False
        assert result.error_message == "Invalid token"


class TestNanoLinkServer:
    def test_create_with_default_config(self):
        server = NanoLinkServer()
        assert server.config.grpc_port == 39100

    def test_create_with_custom_config(self):
        config = ServerConfig(grpc_port=39200)
        server = NanoLinkServer(config)
        assert server.config.grpc_port == 39200

    def test_agents_empty_initially(self):
        server = NanoLinkServer()
        assert server.agents == {}

    def test_get_agent_not_found(self):
        server = NanoLinkServer()
        assert server.get_agent("non-existent") is None

    def test_get_agent_by_hostname_not_found(self):
        server = NanoLinkServer()
        assert server.get_agent_by_hostname("unknown-host") is None

    def test_on_agent_connect_decorator(self):
        server = NanoLinkServer()
        callback_called = False

        @server.on_agent_connect
        async def handle_connect(agent):
            nonlocal callback_called
            callback_called = True

        assert server._on_agent_connect is not None

    def test_on_agent_disconnect_decorator(self):
        server = NanoLinkServer()

        @server.on_agent_disconnect
        async def handle_disconnect(agent):
            pass

        assert server._on_agent_disconnect is not None

    def test_on_metrics_decorator(self):
        server = NanoLinkServer()

        @server.on_metrics
        async def handle_metrics(metrics):
            pass

        assert server._on_metrics is not None


class TestValidationResult:
    def test_default_values(self):
        result = ValidationResult()
        assert result.valid is False
        assert result.permission_level == 0
        assert result.error_message == ""

    def test_valid_result(self):
        result = ValidationResult(valid=True, permission_level=3)
        assert result.valid is True
        assert result.permission_level == 3

    def test_invalid_result(self):
        result = ValidationResult(valid=False, error_message="Token expired")
        assert result.valid is False
        assert result.error_message == "Token expired"
