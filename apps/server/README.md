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
  grpc_port: 39100
  mode: release
  tls_cert: /etc/nanolink/tls/server.crt
  tls_key: /etc/nanolink/tls/server.key
  # Optional: require an Agent certificate issued by this CA.
  grpc_client_ca: /etc/nanolink/tls/agent-ca.crt

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

deployment:
  storage_path: ./data/artifacts
  max_artifact_bytes: 536870912
  download_ttl_minutes: 30
```

Set `server.external_url` (or `NANOLINK_EXTERNAL_URL`) to the HTTPS URL that
agents can reach before using the deployment center. Artifacts are stored under
`deployment.storage_path`; Docker deployments should keep `/app/data` on a
persistent volume.

`tls_cert` and `tls_key` enable native TLS on the HTTP, WebSocket, and gRPC
listeners. `grpc_client_ca` additionally enables mutual TLS on gRPC: Agents
must present a valid client certificate and still pass token authentication.
The equivalent environment variables are `NANOLINK_TLS_CERT`,
`NANOLINK_TLS_KEY`, and `NANOLINK_GRPC_CLIENT_CA`. Keep all private keys outside
the container image and repository, mounted read-only and mode `0600` on Linux.

For a private CA, set `tls_ca_cert` in each Agent configuration. When the Agent
connects to a local SSH tunnel address, set `tls_server_name` to the DNS SAN in
the Server certificate. TLS verification cannot be disabled.

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
| GET/POST | /api/deployment-projects | List or create deployment projects |
| POST | /api/deployment-projects/:id/releases | Upload an immutable release artifact |
| POST | /api/deployment-projects/:id/releases/:releaseId/deploy | Deploy a release |
| POST | /api/deployment-projects/:id/releases/:releaseId/rollback | Activate an earlier release |

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
