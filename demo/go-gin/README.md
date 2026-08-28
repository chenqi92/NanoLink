# NanoOps Go Gin Demo

This demo shows how to integrate NanoOps SDK with Go and Gin framework to create a monitoring server that receives metrics from agents.

## Features

- Receives real-time metrics from NanoOps agents
- REST API for querying agents and metrics
- Alert logging for high resource usage
- Command execution on remote agents

## Prerequisites

- Go 1.21+
- NanoOps Go SDK (local reference via go.mod replace)

## Quick Start

### 1. Run the demo

```bash
cd demo/go-gin
export NANOLINK_AGENT_TOKEN="$(openssl rand -hex 32)"
export NANOLINK_API_TOKEN="$(openssl rand -hex 32)"
go run main.go
```

### 2. Access the services

- **REST API**: http://localhost:8080
- **Agent gRPC**: localhost:39100

## Configuration

Configuration is done via environment variables or modify the code directly:

| Variable | Default | Description |
|----------|---------|-------------|
| `NANOLINK_AGENT_TOKEN` | Required | Agent gRPC bearer token, 32+ bytes |
| `NANOLINK_API_TOKEN` | Required | REST API bearer token, 32+ bytes |
| `NANOLINK_HTTP_BIND_ADDRESS` | `127.0.0.1` | REST bind address |
| `NANOLINK_TLS_CERT` / `NANOLINK_TLS_KEY` | Empty | Optional gRPC TLS pair |

## API Endpoints

### Agents

```bash
# List all connected agents
curl -H "Authorization: Bearer $NANOLINK_API_TOKEN" http://localhost:8080/api/agents

# Get metrics for specific agent
curl -H "Authorization: Bearer $NANOLINK_API_TOKEN" http://localhost:8080/api/agents/{agentId}/metrics
```

### Metrics

```bash
# Get all latest metrics
curl -H "Authorization: Bearer $NANOLINK_API_TOKEN" http://localhost:8080/api/metrics

# Get cluster summary
curl -H "Authorization: Bearer $NANOLINK_API_TOKEN" http://localhost:8080/api/summary
```

### Commands

```bash
# Restart a service
curl -X POST http://localhost:8080/api/commands/agents/{hostname}/service/restart \
  -H "Authorization: Bearer $NANOLINK_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"serviceName": "nginx"}'

# Kill a process
curl -X POST http://localhost:8080/api/commands/agents/{hostname}/process/kill \
  -H "Authorization: Bearer $NANOLINK_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"pid": 1234}'

# Restart Docker container
curl -X POST http://localhost:8080/api/commands/agents/{hostname}/docker/restart \
  -H "Authorization: Bearer $NANOLINK_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"containerName": "my-app"}'
```

### Health Check

```bash
curl -H "Authorization: Bearer $NANOLINK_API_TOKEN" http://localhost:8080/api/health
```

## Project Structure

```
go-gin/
├── go.mod       # Go module configuration
├── main.go      # Main application with Gin routes
└── README.md    # This file
```

## How It Works

1. **NanoOps Server** starts a token-protected gRPC listener on port 39100
2. **MetricsService** stores agent info and processes incoming metrics
3. **Gin Router** exposes REST API endpoints on port 8080
4. When agents connect, their info is registered in the service
5. Metrics are stored in memory and can be queried via API
6. Commands can be sent to agents via POST endpoints

## Production Considerations

1. **Authentication**: Required for both agents and REST API
2. **TLS**: Enable TLS for secure connections
3. **Persistence**: Store metrics in a time-series database
4. **Scaling**: Use Redis for shared state across instances
5. **Monitoring**: Export metrics to Prometheus/Grafana

## License

MIT License - see [LICENSE](../../LICENSE) for details.
