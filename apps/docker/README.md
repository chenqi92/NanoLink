# NanoOps Docker Deployment

Docker configuration for deploying NanoOps Server.

## Quick Start

```bash
# Start the server
docker-compose up -d

# View logs
docker-compose logs -f

# Stop the server
docker-compose down
```

## Configuration

1. Copy and modify `config.yaml`:
```bash
cp config.yaml my-config.yaml
# Edit my-config.yaml
```

2. Mount your config:
```yaml
volumes:
  - ./my-config.yaml:/app/config.yaml:ro
```

## Multi-Architecture Build

Build images for multiple architectures:

```bash
# Build for linux/amd64 and linux/arm64
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/chenqi92/nanolink-server:latest \
  -f Dockerfile \
  ../.. \
  --push
```

Or use docker-compose:

```bash
docker-compose -f docker-compose.build.yml build
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| NANOLINK_SERVER_HTTP_PORT | 8080 | HTTP API port |
| NANOLINK_SERVER_WS_PORT | 9100 | WebSocket port |
| NANOLINK_SERVER_MODE | release | Server mode |
| NANOLINK_AUTH_ENABLED | false | Enable authentication |
| NANOLINK_STORAGE_TYPE | memory | Storage type |
| NANOLINK_STORAGE_PATH | /app/data/nanolink.db | SQLite path |

## Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 8080 | HTTP | API and Dashboard |
| 9100 | WebSocket | Agent connections |

## Volumes

| Path | Description |
|------|-------------|
| /app/data | Persistent data storage |
| /app/config.yaml | Configuration file |

## Health Check

The container includes a health check:
- Endpoint: `http://localhost:8080/api/health`
- Interval: 30s
- Timeout: 10s
- Retries: 3

## Building Native Applications

Android is built from `apps/android` with Gradle. iOS, iPadOS and macOS
(Mac Catalyst) are built from `apps/ios/NanoOps.xcodeproj` with Xcode. The
release workflow packages the native APK, IPA and macOS application.

## License

MIT License
