# NanoLink Python FastAPI Demo

This demo shows how to integrate NanoLink SDK with Python and FastAPI to create a monitoring server that receives metrics from agents.

## Features

- Receives real-time metrics from NanoLink agents
- REST API for querying agents and metrics
- Built-in NanoLink WebSocket server
- Alert logging for high resource usage
- Command execution on remote agents
- OpenAPI documentation (Swagger UI)

## Prerequisites

- Python 3.8+
- NanoLink Python SDK

## Quick Start

### 1. Install dependencies

```bash
cd demo/python-fastapi
pip install -r requirements.txt
```

### 2. Run the demo

```bash
python main.py
# or
uvicorn main:app --reload
```

### 3. Access the services

- **REST API**: http://localhost:8000
- **API Documentation**: http://localhost:8000/docs
- **NanoLink Server**: ws://localhost:9100/ws

## API Endpoints

### Agents

```bash
# List all connected agents
curl http://localhost:8000/api/agents

# Get metrics for specific agent
curl http://localhost:8000/api/agents/{agentId}/metrics
```

### Metrics

```bash
# Get all latest metrics
curl http://localhost:8000/api/metrics

# Get cluster summary
curl http://localhost:8000/api/summary
```

### Commands

```bash
# Restart a service
curl -X POST http://localhost:8000/api/commands/agents/{hostname}/service/restart \
  -H "Content-Type: application/json" \
  -d '{"service_name": "nginx"}'

# Kill a process
curl -X POST http://localhost:8000/api/commands/agents/{hostname}/process/kill \
  -H "Content-Type: application/json" \
  -d '{"pid": 1234}'

# Restart Docker container
curl -X POST http://localhost:8000/api/commands/agents/{hostname}/docker/restart \
  -H "Content-Type: application/json" \
  -d '{"container_name": "my-app"}'
```

### Health Check

```bash
curl http://localhost:8000/api/health
```

## Project Structure

```
python-fastapi/
├── main.py          # FastAPI application with routes
├── requirements.txt # Python dependencies
└── README.md        # This file
```

## How It Works

1. **NanoLink Server** starts on port 9100 in lifespan context
2. **MetricsService** stores agent info and processes metrics
3. **FastAPI** exposes REST endpoints on port 8000
4. Agents connect via WebSocket and send metrics
5. Metrics are stored in memory and queryable via API

## Production Considerations

1. **Authentication**: Add proper token validation
2. **TLS**: Enable TLS for secure connections
3. **Persistence**: Store metrics in a time-series database
4. **Scaling**: Use Redis for shared state
5. **Monitoring**: Export metrics to Prometheus

## License

MIT License - see [LICENSE](../../LICENSE) for details.
