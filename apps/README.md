# NanoLink Applications

Complete standalone applications for monitoring servers with NanoLink.

## Applications

| Application | Platform | Description |
|-------------|----------|-------------|
| [Server](./server) | Linux/Docker | Web-based monitoring dashboard |
| [Desktop](./desktop) | Windows/macOS | Native desktop application |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    NanoLink Applications                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │  Linux Server   │  │ Windows Desktop │  │  macOS Desktop  │  │
│  │  (Docker/Web)   │  │    (Tauri)      │  │    (Tauri)      │  │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘  │
│           │                    │                     │           │
│           └────────────────────┴─────────────────────┘           │
│                                │                                  │
│                    ┌───────────▼───────────┐                     │
│                    │   NanoLink Server     │                     │
│                    │  (Go/WebSocket/API)   │                     │
│                    └───────────┬───────────┘                     │
│                                │                                  │
└────────────────────────────────┼─────────────────────────────────┘
                                 │
                    WebSocket + Protocol Buffers
                                 │
         ┌───────────────────────┼───────────────────────┐
         ▼                       ▼                       ▼
    ┌─────────┐            ┌─────────┐            ┌─────────┐
    │ Agent 1 │            │ Agent 2 │            │ Agent N │
    └─────────┘            └─────────┘            └─────────┘
```

## Quick Start

### Docker (Recommended for Linux)

```bash
# Using docker-compose
cd docker
docker-compose up -d

# Or using pre-built image
docker run -d -p 9100:9100 -p 8080:8080 ghcr.io/chenqi92/nanolink-server:latest
```

### Desktop Application

Download from [Releases](https://github.com/chenqi92/NanoLink/releases):

- **Windows**: `NanoLink_x.x.x_x64_en-US.msi`
- **macOS Intel**: `NanoLink_x.x.x_x64.dmg`
- **macOS Apple Silicon**: `NanoLink_x.x.x_aarch64.dmg`

## Building

### Build All Platforms

```bash
cd docker
docker-compose -f docker-compose.build.yml up
```

This will build:
- Linux AMD64 server image
- Linux ARM64 server image
- Windows x64 installer
- macOS x64 DMG
- macOS ARM64 DMG

### Build Specific Platform

```bash
# Linux server
cd server
go build -o nanolink-server ./cmd

# Desktop (requires Rust and Node.js)
cd desktop
npm install
npm run tauri build
```

## Configuration

### Server Configuration

```yaml
# config.yaml
server:
  http_port: 8080
  ws_port: 9100

auth:
  enabled: true
  tokens:
    - token: "admin-token"
      permission: 3
    - token: "read-token"
      permission: 0

storage:
  type: sqlite  # sqlite, postgres, mysql
  path: ./data/nanolink.db

dashboard:
  enabled: true
```

### Desktop Configuration

Settings are stored in:
- Windows: `%APPDATA%\NanoLink\config.json`
- macOS: `~/Library/Application Support/NanoLink/config.json`

## License

MIT License - see [LICENSE](../LICENSE) for details.
