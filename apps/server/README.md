# NanoLink Server

Web-based monitoring dashboard for NanoLink agents.

## Features

- Real-time agent monitoring
- CPU, Memory, Disk, Network metrics visualization
- WebSocket-based communication with agents
- Embedded web dashboard
- REST API for integration

## Quick Start

### Using Docker

```bash
docker run -d \
  -p 8080:8080 \
  -p 9100:9100 \
  ghcr.io/chenqi92/nanolink-server:latest
```

### Building from Source

```bash
# Build web dashboard
cd web
npm install
npm run build
cd ..

# Build server
go build -o nanolink-server ./cmd
./nanolink-server
```

## Configuration

Create `config.yaml`:

```yaml
server:
  http_port: 8080
  ws_port: 9100
  mode: release

auth:
  enabled: true
  tokens:
    - token: "your-admin-token"
      permission: 3
      name: "Admin"
    - token: "your-read-token"
      permission: 0
      name: "ReadOnly"

storage:
  type: memory  # memory, sqlite
  path: ./data/nanolink.db

metrics:
  retention_days: 7
  max_agents: 100
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/health | Health check |
| GET | /api/agents | List all connected agents |
| GET | /api/agents/:id | Get specific agent |
| GET | /api/agents/:id/metrics | Get agent metrics |
| GET | /api/metrics | Get all current metrics |
| GET | /api/metrics/history | Get historical metrics |
| GET | /api/summary | Get metrics summary |
| POST | /api/agents/:id/command | Send command to agent |

## WebSocket Protocol

Agents connect via WebSocket on port 9100.

### Authentication

```json
{
  "type": "auth",
  "timestamp": 1703001234567,
  "payload": {
    "token": "your-token",
    "hostname": "server-01",
    "os": "linux",
    "arch": "amd64",
    "agentVersion": "0.1.0"
  }
}
```

### Metrics

```json
{
  "type": "metrics",
  "timestamp": 1703001234567,
  "payload": {
    "cpu": {
      "usagePercent": 45.5,
      "coreCount": 8,
      "perCoreUsage": [40.0, 50.0, ...]
    },
    "memory": {
      "total": 17179869184,
      "used": 8589934592,
      "available": 8589934592
    },
    "disks": [...],
    "networks": [...]
  }
}
```

## License

MIT License
