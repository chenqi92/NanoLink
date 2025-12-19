# NanoLink Python SDK

Python SDK for NanoLink monitoring system.

## Installation

```bash
pip install kkape-nanolink
```

Or install from source:

```bash
cd sdk/python
pip install -e .
```

## Quick Start

```python
import asyncio
from nanolink import NanoLinkServer, ServerConfig, Metrics, AgentConnection

async def main():
    # Create server
    server = NanoLinkServer(ServerConfig(port=9100))

    # Handle agent connections
    @server.on_agent_connect
    async def handle_connect(agent: AgentConnection):
        print(f"Agent connected: {agent.hostname}")
        print(f"  OS: {agent.os}/{agent.arch}")
        print(f"  Version: {agent.version}")

    # Handle agent disconnections
    @server.on_agent_disconnect
    async def handle_disconnect(agent: AgentConnection):
        print(f"Agent disconnected: {agent.hostname}")

    # Handle metrics
    @server.on_metrics
    async def handle_metrics(metrics: Metrics):
        if metrics.cpu:
            print(f"CPU: {metrics.cpu.usage_percent:.1f}%")
            if metrics.cpu.model:
                print(f"  Model: {metrics.cpu.model}")

        if metrics.memory:
            print(f"Memory: {metrics.memory.usage_percent:.1f}%")

        for gpu in metrics.gpus:
            print(f"GPU: {gpu.name} - {gpu.usage_percent:.1f}%")

    # Start server
    await server.run_forever()

if __name__ == "__main__":
    asyncio.run(main())
```

## Token Validation

```python
from nanolink import NanoLinkServer, ServerConfig, ValidationResult

def my_token_validator(token: str) -> ValidationResult:
    if token == "admin-token":
        return ValidationResult(valid=True, permission_level=3)
    elif token == "read-token":
        return ValidationResult(valid=True, permission_level=0)
    else:
        return ValidationResult(valid=False, error_message="Invalid token")

config = ServerConfig(
    port=9100,
    token_validator=my_token_validator,
)
server = NanoLinkServer(config)
```

## Sending Commands

```python
from nanolink import Command

# Get agent
agent = server.get_agent_by_hostname("my-server")

# List processes
result = await agent.send_command(Command.process_list())
print(result.output)

# Restart a service
result = await agent.send_command(Command.service_restart("nginx"))
if result.success:
    print("Service restarted successfully")
else:
    print(f"Error: {result.error}")

# Execute shell command (requires SuperToken)
result = await agent.send_command(
    Command.shell_execute("df -h", super_token="your-super-token")
)
```

## Permission Levels

| Level | Name | Allowed Operations |
|-------|------|-------------------|
| 0 | READ_ONLY | View metrics, process list, logs |
| 1 | BASIC_WRITE | Download files, clear temp files |
| 2 | SERVICE_CONTROL | Restart services, Docker containers, kill processes |
| 3 | SYSTEM_ADMIN | System reboot, execute shell commands |

## TLS Configuration

```python
config = ServerConfig(
    port=9100,
    tls_cert_path="/path/to/cert.pem",
    tls_key_path="/path/to/key.pem",
)
server = NanoLinkServer(config)
```

## Development

```bash
# Install development dependencies
pip install -e ".[dev]"

# Run tests
pytest

# Run linting
ruff check .
black --check .
mypy .
```

## License

Apache 2.0 License - see [LICENSE](../../LICENSE) for details.
