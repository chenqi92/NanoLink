# NanoLink Demo Projects

This directory contains demo projects showing how to integrate NanoLink SDK into various frameworks and languages.

## Available Demos

| Demo | Language | Framework | Description |
|------|----------|-----------|-------------|
| [spring-boot](./spring-boot) | Java | Spring Boot 3.x | REST API server with NanoLink integration |
| [go-gin](./go-gin) | Go | Gin | REST API server with NanoLink integration |
| [python-fastapi](./python-fastapi) | Python | FastAPI | REST API server with NanoLink integration |

## Quick Start

### Spring Boot Demo

```bash
cd spring-boot
mvn spring-boot:run
```

The demo will start:
- REST API on `http://localhost:8080`
- NanoLink server on port `9100`
- Dashboard on `http://localhost:9100/`

### Connect an Agent

Configure your agent to connect:

```yaml
servers:
  - url: "ws://localhost:9100"
    token: ""
    permission: 3
```

Start the agent:
```bash
nanolink-agent -c nanolink.yaml
```

## API Endpoints

All demos provide similar REST APIs:

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/agents` | List connected agents |
| GET | `/api/agents/{id}/metrics` | Get agent metrics |
| GET | `/api/metrics` | Get all metrics |
| GET | `/api/summary` | Get cluster summary |
| POST | `/api/commands/agents/{hostname}/service/restart` | Restart a service |
| POST | `/api/commands/agents/{hostname}/process/kill` | Kill a process |

## Contributing

Want to add a demo for another framework? Contributions are welcome!

1. Create a new directory under `demo/`
2. Include a complete working example
3. Add a README with setup instructions
4. Update this README with the new demo

## License

MIT License - see [LICENSE](../LICENSE) for details.
