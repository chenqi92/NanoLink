# NanoLink

[![Test](https://github.com/chenqi92/NanoLink/actions/workflows/test.yml/badge.svg)](https://github.com/chenqi92/NanoLink/actions/workflows/test.yml)
[![Release](https://github.com/chenqi92/NanoLink/actions/workflows/release.yml/badge.svg)](https://github.com/chenqi92/NanoLink/actions/workflows/release.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

English | [中文](README_CN.md)

**NanoLink** is a lightweight, cross-platform server monitoring system that includes Agent, SDK, Dashboard, and standalone applications.

## Core Components

| Component | Description | Tech Stack |
|-----------|-------------|------------|
| [Agent](./agent) | Monitoring agent deployed on target servers | Rust |
| [SDK](./sdk) | Client libraries for embedding in existing services | Java / Go / Python |
| [Dashboard](./dashboard) | Web visualization panel | Vue 3 + TailwindCSS |
| [Apps](./apps) | Standalone deployable applications | Go + Tauri |

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Target Server                                   │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                         NanoLink Agent (Rust)                          │  │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐          │  │
│  │  │   CPU   │ │  Memory │ │  Disk   │ │ Network │ │   GPU   │          │  │
│  │  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘          │  │
│  │       └───────────┴───────────┴───────────┴───────────┘               │  │
│  │                               │                                        │  │
│  │                    ┌──────────▼──────────┐                             │  │
│  │                    │     Ring Buffer     │  ← 10min offline data cache │  │
│  │                    └──────────┬──────────┘                             │  │
│  │                               │                                        │  │
│  │                    ┌──────────▼──────────┐                             │  │
│  │                    │   Connection Mgr    │  ← Multi-server + auto reconnect │
│  │                    └──────────┬──────────┘                             │  │
│  └───────────────────────────────┼───────────────────────────────────────┘  │
└──────────────────────────────────┼──────────────────────────────────────────┘
                                   │
                        gRPC + Protocol Buffers (TLS)
                              Port: 39100
                                   │
         ┌─────────────────────────┼─────────────────────────┐
         ▼                         ▼                         ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Java Service   │     │   Go Service    │     │ Python Service  │
│   (with SDK)    │     │   (with SDK)    │     │   (with SDK)    │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                      WebSocket  │  Port: 9100
                                 │
                      ┌──────────▼──────────┐
                      │     Dashboard       │
                      │     (Vue 3)         │
                      └─────────────────────┘
```

### Standalone Application Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    NanoLink Applications                         │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │  Linux Server   │  │ Windows Desktop │  │  macOS Desktop  │  │
│  │   (Go + Web)    │  │    (Tauri)      │  │    (Tauri)      │  │
│  │                 │  │                 │  │                 │  │
│  │  Docker Deploy  │  │  Native Desktop │  │  Native Desktop │  │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘  │
│           └────────────────────┴────────────────────┘           │
│                                │                                 │
│                     ┌──────────▼──────────┐                      │
│                     │   NanoLink Server   │                      │
│                     │ (WebSocket/gRPC+API)│                      │
│                     └─────────────────────┘                      │
└─────────────────────────────────────────────────────────────────┘
```

## Features

### Agent Features

| Feature | Description |
|---------|-------------|
| Hardware Monitoring | Comprehensive CPU, memory, disk, network, GPU collection |
| Offline Buffering | Ring Buffer stores 10 minutes of data, syncs after reconnect |
| Multi-Server | Connect to multiple servers simultaneously with different permission levels |
| Auto Reconnect | Exponential backoff reconnection with configurable max delay |
| Command Execution | Process management, service control, file operations, Docker operations |
| Cross-Platform | Full support for Linux, macOS, Windows |

### Monitoring Metrics

<details>
<summary><b>CPU</b></summary>

- Total usage, per-core usage, load average
- Model, vendor (Intel/AMD/Apple)
- Current frequency, max frequency, base frequency
- Physical cores, logical cores
- Architecture (x86_64/aarch64)
- Temperature (Linux/macOS)
- L1/L2/L3 cache sizes

</details>

<details>
<summary><b>Memory</b></summary>

- Total, used, available, usage percentage
- Swap total, swap used
- Cached, buffers (Linux)
- Memory type (DDR4/DDR5)
- Memory speed (MHz)

</details>

<details>
<summary><b>Disk</b></summary>

- Mount point, device name, filesystem type
- Total capacity, used, available
- Read/write rates (bytes/s), IOPS
- Model, serial number, vendor
- Type (SSD/HDD/NVMe)
- Temperature, S.M.A.R.T. health status

</details>

<details>
<summary><b>Network</b></summary>

- Interface name, type (physical/virtual)
- RX/TX rates (bytes/s), packets/sec
- MAC address, IPv4/IPv6 addresses
- Link speed, MTU
- Connection status

</details>

<details>
<summary><b>GPU (NVIDIA/AMD/Intel)</b></summary>

- Model, vendor, driver version
- GPU utilization, VRAM usage
- Temperature, fan speed
- Power draw, power limit
- Core clock, memory clock
- PCIe info (generation, bandwidth)
- Encoder/decoder utilization

</details>

<details>
<summary><b>System Info</b></summary>

- OS name, version
- Kernel version
- Hostname
- Boot time, uptime
- Motherboard model, vendor
- BIOS version

</details>

### Permission Levels

| Level | Name | Allowed Operations |
|-------|------|-------------------|
| 0 | READ_ONLY | Read metrics, view process list, view logs |
| 1 | BASIC_WRITE | Download log files, clear temp files, upload files |
| 2 | SERVICE_CONTROL | Restart services, Docker containers, kill processes |
| 3 | SYSTEM_ADMIN | System reboot, execute shell commands (requires SuperToken) |

### Communication Protocols

NanoLink uses a layered communication architecture:

| Protocol | Port | Purpose | Features |
|----------|------|---------|----------|
| **gRPC** | 39100 | Agent ↔ Server communication | High performance, bidirectional streaming, type-safe |
| **WebSocket** | 9100 | Dashboard ↔ Server communication | Native browser support, real-time updates |
| **HTTP API** | 8080 | REST management interface | Standard HTTP calls |

> **Note**: Agents now use gRPC exclusively for server connections. Dashboard still uses WebSocket for real-time communication.

### Security Mechanisms

| Mechanism | Description |
|-----------|-------------|
| TLS Encryption | All communication (WebSocket/gRPC) enforces TLS |
| Token Authentication | Each connection uses an independent token |
| Command Whitelist | Only predefined command patterns allowed |
| Command Blacklist | Dangerous commands are always blocked |
| SuperToken | Shell commands require a separate super token |
| Audit Log | All command executions logged to local file |
| Rate Limiting | Prevents command flood attacks |

## Quick Start

### One-Click Agent Installation

**Linux/macOS (Interactive):**
```bash
curl -fsSL https://raw.githubusercontent.com/chenqi92/NanoLink/main/agent/scripts/install.sh | sudo bash
```

**Windows (PowerShell Admin):**
```powershell
irm https://raw.githubusercontent.com/chenqi92/NanoLink/main/agent/scripts/install.ps1 | iex
```

**Silent Installation (Automated Deployment):**
```bash
curl -fsSL https://raw.githubusercontent.com/chenqi92/NanoLink/main/agent/scripts/install.sh | sudo bash -s -- \
  --silent \
  --url "wss://monitor.example.com:9100" \
  --token "your_token" \
  --permission 2
```

### Cloudflare R2 Mirror (China Optimized) ☁️

For faster downloads in mainland China, use R2 mirror:

**Linux/macOS:**
```bash
curl -fsSL https://agent.download.kkape.com/releases/v0.2.6/install-r2.sh | sudo bash
```

**Windows (PowerShell Admin):**
```powershell
irm https://agent.download.kkape.com/releases/v0.2.6/install-r2.ps1 | iex
```

<details>
<summary><b>Direct Agent Downloads (R2 Mirror)</b></summary>

| Platform | Architecture | Download |
|----------|--------------|----------|
| Linux | x86_64 | [nanolink-agent-linux-x86_64](https://agent.download.kkape.com/releases/v0.2.6/nanolink-agent-linux-x86_64) |
| Linux | ARM64 | [nanolink-agent-linux-aarch64](https://agent.download.kkape.com/releases/v0.2.6/nanolink-agent-linux-aarch64) |
| macOS | Intel | [nanolink-agent-macos-x86_64](https://agent.download.kkape.com/releases/v0.2.6/nanolink-agent-macos-x86_64) |
| macOS | Apple Silicon | [nanolink-agent-macos-aarch64](https://agent.download.kkape.com/releases/v0.2.6/nanolink-agent-macos-aarch64) |
| Windows | x64 | [nanolink-agent-windows-x86_64.exe](https://agent.download.kkape.com/releases/v0.2.6/nanolink-agent-windows-x86_64.exe) |

</details>

### Multi-Server Management

Agent supports connecting to multiple servers simultaneously with dynamic add/remove/update of server configurations.

**Add a new server:**
```bash
# Using install script
sudo ./install.sh --add-server --host "second.example.com" --port 39100 --token "token2"

# Using Agent CLI
nanolink-agent server add --host "second.example.com" --port 39100 --token "token2" --permission 1

# Using Management API (hot-reload)
curl -X POST http://localhost:9101/api/servers \
  -H "Content-Type: application/json" \
  -d '{"host":"second.example.com","port":39100,"token":"token2","permission":1}'
```

**Remove a server:**
```bash
# Using Agent CLI
nanolink-agent server remove --host "old.example.com" --port 39100

# Using Management API
curl -X DELETE "http://localhost:9101/api/servers?host=old.example.com&port=39100"
```

**List configured servers:**
```bash
nanolink-agent server list
```

### Deploy Server with Docker

```bash
# Using docker-compose
cd apps/docker
docker-compose up -d

# Or run directly
docker run -d \
  -p 8080:8080 \
  -p 9100:9100 \
  ghcr.io/chenqi92/nanolink-server:latest
```

Access Dashboard: http://localhost:8080/dashboard

### Agent Configuration

```yaml
# /etc/nanolink/nanolink.yaml
agent:
  hostname: ""  # Leave empty for auto-detection
  heartbeat_interval: 30
  reconnect_delay: 5
  max_reconnect_delay: 300

servers:
  # gRPC connection (high-performance, type-safe)
  - host: monitor.example.com
    port: 39100           # Default gRPC port
    token: "your-auth-token"
    permission: 2
    tls_enabled: false    # Recommended: true for production
    tls_verify: true

collector:
  cpu_interval_ms: 1000
  disk_interval_ms: 3000
  network_interval_ms: 1000
  enable_per_core_cpu: true

buffer:
  capacity: 600  # 10 minutes (1s sampling)

shell:
  enabled: false
  super_token: ""
  timeout_seconds: 30
  whitelist:
    - pattern: "df -h"
    - pattern: "free -m"
  blacklist:
    - "rm -rf"
    - "mkfs"

logging:
  level: info
  audit_enabled: true
  audit_file: "/var/log/nanolink/audit.log"
```

## SDK Integration

### Java SDK

```xml
<dependency>
    <groupId>com.kkape</groupId>
    <artifactId>nanolink-sdk</artifactId>
    <version>0.2.6</version>
</dependency>
```

```java
NanoLinkServer server = NanoLinkServer.builder()
    .wsPort(9100)       // Dashboard WebSocket port
    .grpcPort(39100)    // Agent gRPC port
    .staticFilesPath("/path/to/dashboard")  // Optional: external Dashboard path
    .onAgentConnect(agent -> {
        log.info("Agent connected: {} ({})", agent.getHostname(), agent.getOs());
    })
    .onMetrics(metrics -> {
        log.info("CPU: {:.1f}% | Memory: {:.1f}%",
            metrics.getCpu().getUsagePercent(),
            metrics.getMemory().getUsedPercent());
    })
    .build();

server.start();
```

### Go SDK

```go
import "github.com/chenqi92/NanoLink/sdk/go/nanolink"

server := nanolink.NewServer(nanolink.Config{
    WsPort:   9100,    // Dashboard WebSocket port
    GrpcPort: 39100,   // Agent gRPC port
    // StaticFilesPath: "/path/to/dashboard",  // Optional
})

server.OnAgentConnect(func(agent *nanolink.AgentConnection) {
    log.Printf("Agent connected: %s (%s)", agent.Hostname, agent.OS)
})

server.OnMetrics(func(m *nanolink.Metrics) {
    log.Printf("CPU: %.1f%% | Memory: %.1f%%",
        m.CPU.UsagePercent, m.Memory.UsedPercent)
})

server.Start()
```

### Python SDK

```bash
pip install nanolink-sdk
```

```python
from nanolink import NanoLinkServer, ServerConfig

async def main():
    config = ServerConfig(
        ws_port=9100,    # Dashboard WebSocket port
        grpc_port=39100  # Agent gRPC port
    )
    server = NanoLinkServer(config)

    @server.on_agent_connect
    async def on_connect(agent):
        print(f"Agent connected: {agent.hostname} ({agent.os})")

    @server.on_metrics
    async def on_metrics(metrics):
        print(f"CPU: {metrics.cpu.usage_percent:.1f}%")

    await server.run_forever()

asyncio.run(main())
```

## Project Structure

```
NanoLink/
├── agent/                      # Rust Agent
│   ├── src/
│   │   ├── collector/          # Data collectors
│   │   │   ├── cpu.rs
│   │   │   ├── memory.rs
│   │   │   ├── disk.rs
│   │   │   ├── network.rs
│   │   │   └── gpu.rs
│   │   ├── connection/         # WebSocket/gRPC client
│   │   ├── executor/           # Command executors
│   │   ├── buffer/             # Ring Buffer
│   │   ├── security/           # Permission system
│   │   └── platform/           # Platform-specific code
│   ├── scripts/                # Install/uninstall scripts
│   └── systemd/                # Linux service config
│
├── sdk/                        # Multi-language SDKs
│   ├── protocol/               # Protocol Buffers definitions
│   │   └── nanolink.proto
│   ├── java/                   # Java SDK (Maven)
│   ├── go/                     # Go SDK (Module)
│   └── python/                 # Python SDK (PyPI)
│
├── dashboard/                  # Web Dashboard
│   ├── src/
│   │   ├── components/         # Vue components
│   │   └── composables/        # WebSocket composables
│   └── package.json
│
├── apps/                       # Standalone Applications
│   ├── server/                 # Go Web server
│   │   ├── cmd/                # Entry point
│   │   ├── internal/           # Internal modules
│   │   │   ├── grpc/           # gRPC server
│   │   │   ├── handler/        # HTTP/WebSocket handlers
│   │   │   └── proto/          # Generated Proto code
│   │   └── web/                # Embedded Dashboard
│   ├── desktop/                # Tauri desktop app
│   │   ├── src/                # Vue frontend
│   │   └── src-tauri/          # Rust backend
│   └── docker/                 # Docker configuration
│       ├── Dockerfile
│       ├── docker-compose.yml
│       └── docker-compose.build.yml
│
├── demo/                       # Integration examples
│   └── spring-boot/            # Spring Boot example
│
├── scripts/                    # Utility scripts
│   ├── bump-version.sh         # Version update (Linux/macOS)
│   └── bump-version.ps1        # Version update (Windows)
│
└── .github/workflows/          # CI/CD
    ├── test.yml                # Tests
    ├── release.yml             # Agent release
    ├── sdk-release.yml         # SDK release
    └── apps-release.yml        # Apps release
```

## Building

### Agent (Rust)

```bash
cd agent
cargo build --release
# Output: target/release/nanolink-agent
```

### SDK

```bash
# Java
cd sdk/java && mvn clean package

# Go
cd sdk/go && go build ./...

# Python
cd sdk/python && pip install -e ".[dev]"
```

### Dashboard

```bash
cd dashboard
npm install && npm run build
```

### Standalone Applications

```bash
# Linux Server (Docker)
cd apps/docker && docker-compose build

# Desktop (requires Rust + Node.js)
cd apps/desktop && npm install && npm run tauri build
```

## Service Management

### Linux (systemd)

```bash
sudo systemctl start nanolink-agent    # Start
sudo systemctl stop nanolink-agent     # Stop
sudo systemctl restart nanolink-agent  # Restart
sudo systemctl status nanolink-agent   # Status
sudo journalctl -u nanolink-agent -f   # Logs
```

### macOS (launchd)

```bash
sudo launchctl start com.nanolink.agent
sudo launchctl stop com.nanolink.agent
tail -f /var/log/nanolink/agent.log
```

### Windows

```powershell
Start-Service NanoLinkAgent
Stop-Service NanoLinkAgent
Restart-Service NanoLinkAgent
Get-Service NanoLinkAgent
```

## CI/CD

| Workflow | Trigger | Artifacts |
|----------|---------|-----------|
| Test | PR / Push | Test reports |
| Release Agent | Tag `v*` | Multi-platform binaries |
| SDK Release | Tag `sdk-v*` | Maven / PyPI / GitHub |
| Apps Release | Tag `app-v*` | Docker images / Installers |

## License

MIT License - See [LICENSE](LICENSE)

## Contributing

Issues and Pull Requests are welcome!

1. Fork this repository
2. Create a feature branch (`git checkout -b feature/xxx`)
3. Commit your changes (`git commit -m 'Add xxx'`)
4. Push the branch (`git push origin feature/xxx`)
5. Create a Pull Request
