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
  --url "monitor.example.com:39100" \
  --token "your_token" \
  --permission 2
```

### Cloudflare R2 Mirror (China Optimized) ☁️

For faster downloads in mainland China, use R2 mirror:

**Linux/macOS:**
```bash
curl -fsSL https://agent.download.kkape.com/newest/install.sh | sudo bash
```

**Windows (PowerShell Admin):**
```powershell
irm https://agent.download.kkape.com/newest/install.ps1 | iex
```

<details>
<summary><b>Direct Agent Downloads (R2 Mirror)</b></summary>

| Platform | Architecture | Download |
|----------|--------------|----------|
| Linux | x86_64 | [nanolink-agent-linux-x86_64](https://agent.download.kkape.com/newest/nanolink-agent-linux-x86_64) |
| Linux | ARM64 | [nanolink-agent-linux-aarch64](https://agent.download.kkape.com/newest/nanolink-agent-linux-aarch64) |
| macOS | Intel | [nanolink-agent-macos-x86_64](https://agent.download.kkape.com/newest/nanolink-agent-macos-x86_64) |
| macOS | Apple Silicon | [nanolink-agent-macos-aarch64](https://agent.download.kkape.com/newest/nanolink-agent-macos-aarch64) |
| Windows | x64 | [nanolink-agent-windows-x86_64.exe](https://agent.download.kkape.com/newest/nanolink-agent-windows-x86_64.exe) |

</details>

---

## Installation Guide (Interactive Mode)

When running the install script interactively, you'll be prompted for several configuration options:

### Step 1: Server Address

```
Server address (e.g., monitor.example.com:39100): 
```

| Format | Example | Description |
|--------|---------|-------------|
| `host:port` | `api.example.com:39100` | Full format with custom port |
| `host` | `api.example.com` | Uses default port 39100 |

> **Note:** This is the gRPC endpoint of your NanoLink Server, not a web URL.

### Step 2: Authentication Token

```
Authentication Token: 
```

This token is used to authenticate the Agent with the Server.

| Where to get it | Description |
|-----------------|-------------|
| Server config `auth.tokens[].token` | Configured in server's `config.yaml` |
| Admin Dashboard | Generated through the management interface |

> **Important:** If `auth.enabled: false` on the server, any token value will be accepted.

### Step 3: Permission Level

```
Permission Level
  1) Read Only (monitoring only)
  2) Read + Process Control
  3) Read + Process + Limited Shell
  4) Full Access (all operations)
Select [1-4]: 
```

| Level | Name | Allowed Operations |
|-------|------|------------------- |
| **0** (Option 1) | READ_ONLY | Read metrics, view processes, view logs |
| **1** (Option 2) | BASIC_WRITE | + Download files, clear temp, upload files |
| **2** (Option 3) | SERVICE_CONTROL | + Restart services, Docker, kill processes |
| **3** (Option 4) | SYSTEM_ADMIN | + System reboot, shell commands (requires SuperToken) |

### Step 4: TLS Configuration

```
Enable TLS? [y/N]: 
```

| Choice | When to use |
|--------|-------------|
| **N** (No) | Server is **not** configured with HTTPS/TLS (most common for self-hosted) |
| **Y** (Yes) | Server uses TLS certificate (Let's Encrypt, etc.) |

If you select Yes:

```
Verify TLS certificate? [Y/n]: 
```

| Choice | When to use |
|--------|-------------|
| **Y** (Yes) | Production: Server has a valid, trusted certificate |
| **N** (No) | Testing only: Self-signed certificate (security warning) |

> **⚠️ Common Mistake:** If your server doesn't have TLS configured but you enable TLS on the agent, the connection will fail with "Cannot reach server".

### Step 5: Connection Test

```
Test server connection before installing? [Y/n]: 
```

Tests TCP connectivity to the server. If the test fails:
- Check if the server is running
- Verify firewall/security group allows port 39100
- Confirm TLS settings match between Agent and Server

### Step 6: Hostname Configuration

```
Use system hostname (server-name)? [Y/n]: 
```

| Choice | Result |
|--------|--------|
| **Y** | Uses auto-detected hostname (e.g., `ubuntu-server`) |
| **N** | Enter a custom display name for this agent |

Custom hostnames are useful for identifying servers:
```
Custom hostname: prod-web-01
```

### Step 7: Shell Commands (if permission ≥ 2)

```
Enable shell command execution? (requires super token) [y/N]: 
```

| Choice | Description |
|--------|-------------|
| **N** | Disable shell access (safer) |
| **Y** | Enable shell, requires a **separate** SuperToken |

If enabled:
```
Shell Super Token (different from auth token): 
```

> **Security:** The Shell SuperToken is different from the Authentication Token. This adds an extra layer of protection for dangerous operations.

---

## Token Types Explained

NanoLink uses **two different types of tokens** for different purposes:

| Token Type | Purpose | Where Configured |
|------------|---------|------------------|
| **Authentication Token** | Agent ↔ Server connection auth | Agent: `servers[].token`<br>Server: `auth.tokens[].token` |
| **API Token** | Local Management API access | Agent: `management.api_token` |
| **Shell SuperToken** | Shell command execution | Agent: `shell.super_token` |

### Authentication Flow

```
Agent                                Server
  │                                    │
  │  Connect with token="xxx"          │
  ├───────────────────────────────────►│
  │                                    │
  │  Server checks auth.tokens[]       │
  │  ◄─────────────────────────────────┤
  │  Returns: permission level         │
  │                                    │
```

### Server Configuration Example

```yaml
# Server config.yaml
auth:
  enabled: true
  tokens:
    - token: "prod-agent-token-1"
      permission: 2
      name: "Production Servers"
    
    - token: "dev-agent-token"
      permission: 3
      name: "Dev Environment"
```

---

## Silent Installation Parameters

For automated/scripted deployments:

```bash
curl -fsSL URL | sudo bash -s -- [OPTIONS]
```

| Parameter | Description | Example |
|-----------|-------------|---------|
| `--silent` | Non-interactive mode | `--silent` |
| `--url` | Server address (host:port) | `--url "api.example.com:39100"` |
| `--token` | Authentication token | `--token "your_token"` |
| `--permission` | Permission level (0-3) | `--permission 2` |
| `--no-tls` | Disable TLS | `--no-tls` |
| `--hostname` | Custom hostname | `--hostname "prod-01"` |
| `--shell-enabled` | Enable shell | `--shell-enabled` |
| `--shell-token` | Shell SuperToken | `--shell-token "super_secret"` |
| `--lang` | Language (en/zh) | `--lang zh` |

**Examples:**

```bash
# Minimal installation (TLS disabled)
curl -fsSL URL | sudo bash -s -- --silent \
  --url "192.168.1.100:39100" \
  --token "my_token" \
  --no-tls

# Full production setup (TLS enabled)
curl -fsSL URL | sudo bash -s -- --silent \
  --url "monitor.example.com:39100" \
  --token "prod_token" \
  --permission 2 \
  --hostname "web-server-01"

# With shell access enabled
curl -fsSL URL | sudo bash -s -- --silent \
  --url "monitor.example.com:39100" \
  --token "admin_token" \
  --permission 3 \
  --shell-enabled \
  --shell-token "super_admin_token"
```

---

## Troubleshooting Installation

### "Cannot reach server"

| Cause | Solution |
|-------|----------|
| TLS mismatch | If server has no TLS, select `Enable TLS? [y/N]: N` |
| Firewall | Open port 39100 (or your custom port) |
| Server not running | Start NanoLink Server first |
| Wrong port | Verify gRPC port (default: 39100) |

### "Management API token not set"

The agent config has `management.enabled: true` but no `api_token`:

```bash
# Fix: Edit config
sudo nano /etc/nanolink/nanolink.yaml

# Change this:
management:
  enabled: false  # Disable if not needed
  # OR set a token:
  # enabled: true
  # api_token: "your_local_api_token"

# Restart
sudo systemctl restart nanolink-agent
```

### View Agent Logs

```bash
# Linux
sudo journalctl -u nanolink-agent -f

# macOS
tail -f /var/log/nanolink/agent.log

# Windows (PowerShell)
Get-Content "C:\ProgramData\NanoLink\logs\agent.log" -Wait
```

### Interactive CLI Mode

Running `nanolink-agent` without arguments enters an interactive mode with a user-friendly menu. The CLI automatically detects your system language (English/Chinese).

```
$ nanolink-agent

╭──────────────────────────────────────╮
│       NanoLink Agent v1.0.0          │
╰──────────────────────────────────────╯

? Select an action:
❯ Start Agent
  Manage Servers
  View Status
  Initialize Config
  Exit
```

**Server Management Menu:**
```
? Configured servers:
❯ 192.168.1.100:39100 [READ_ONLY]
  10.0.0.5:39100 [SYSTEM_ADMIN]
  ──────────────────
  + Add new server
  ← Back to main menu
```

**Server Actions:**
```
? Actions for 192.168.1.100:39100:
❯ Update configuration
  Remove server
  Test connection
  Back
```

The interactive mode supports:
- **Add Server**: Step-by-step wizard to add a new server connection
- **Update Server**: Modify token, permission, or TLS settings
- **Remove Server**: Delete a server configuration
- **Test Connection**: Verify connectivity to a server before use
- **View Status**: Check agent running status and connected servers

> **Note**: You can still use command-line arguments for scripting. The interactive mode is only activated when no arguments are provided.

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

### Web Dashboard - Add Agent Wizard

The Dashboard provides a step-by-step wizard to help you deploy agents easily. Click the **"Add Agent"** button on the dashboard to start.

**Step 1: Select Platform**
```
┌─────────────────────────────────────┐
│  Add Agent - Step 1/3               │
├─────────────────────────────────────┤
│  Select target operating system:    │
│                                     │
│  ┌─────────┐ ┌─────────┐ ┌────────┐ │
│  │  Linux  │ │ Windows │ │ macOS  │ │
│  └─────────┘ └─────────┘ └────────┘ │
│                                     │
│            [Next]                   │
└─────────────────────────────────────┘
```

**Step 2: Configure Agent**
```
┌─────────────────────────────────────┐
│  Add Agent - Step 2/3               │
├─────────────────────────────────────┤
│  Agent Name: [optional, auto-gen]   │
│                                     │
│  Permission Level:                  │
│  ○ Read Only (READ_ONLY)            │
│  ● Basic Write (BASIC_WRITE)        │
│  ○ Service Control                  │
│  ○ System Admin (SYSTEM_ADMIN)      │
│                                     │
│  ☐ Enable Remote Shell              │
│  ☐ Enable TLS Encryption            │
│                                     │
│     [Back]          [Next]          │
└─────────────────────────────────────┘
```

**Step 3: Get Installation Command**
```
┌─────────────────────────────────────┐
│  Add Agent - Step 3/3               │
├─────────────────────────────────────┤
│  Run this command on target server: │
│                                     │
│  ┌─────────────────────────────────┐│
│  │ curl -sSL https://xxx/install  ││
│  │   | bash -s -- \               ││
│  │   --server "192.168.1.100:391" ││
│  │   --token "eyJhbGci..."        ││
│  └─────────────────────────────────┘│
│                         [Copy]      │
│                                     │
│  Or download pre-configured binary: │
│  [Linux] [Windows] [macOS]          │
│                                     │
│     [Done]                          │
└─────────────────────────────────────┘
```

The wizard automatically:
- Generates a one-time authentication token
- Detects the server URL from your current connection
- Creates platform-specific installation commands
- Provides YAML configuration for manual setup

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
    <version>0.3.8</version>
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

### Data Request API

The SDK can proactively request specific data from agents on demand, useful for real-time dashboard scenarios.

#### Layered Data Push Mechanism

| Layer | Data Type | Default Interval | Description |
|-------|-----------|------------------|-------------|
| Static | Hardware info | Once on connect | CPU model, memory size, disk devices |
| Realtime | Dynamic metrics | 5 seconds | CPU usage, memory, disk/network IO |
| Periodic | Low-frequency | 30-60 seconds | Disk usage, user sessions |

#### Supported Request Types

| Type | Description |
|------|-------------|
| `FULL` | Complete metrics |
| `STATIC` | Static hardware info |
| `DISK_USAGE` | Disk capacity |
| `NETWORK_INFO` | Network details |
| `USER_SESSIONS` | Logged-in users |
| `GPU_INFO` | GPU information |
| `HEALTH` | Disk S.M.A.R.T. status |

#### Usage Examples

**Java:**
```java
// Request from specific agent
server.requestData(agentId, DataRequestType.DATA_REQUEST_STATIC);

// Broadcast to all agents
server.broadcastDataRequest(DataRequestType.DATA_REQUEST_FULL);
```

**Go:**
```go
server.RequestData(agentID, int32(pb.DataRequestType_DATA_REQUEST_STATIC))
server.BroadcastDataRequest(int32(pb.DataRequestType_DATA_REQUEST_FULL))
```

**Python:**
```python
server.request_data(agent_id, DataRequestType.STATIC)
server.broadcast_data_request(DataRequestType.FULL)
```

#### Response Handling

Responses arrive through existing callbacks. Example - getting GPU count:

**Java:**
```java
server.onStaticInfo(info -> {
    int gpuCount = info.getGpusList().size();
    int npuCount = info.getNpusList().size();
    System.out.println("GPUs: " + gpuCount + ", NPUs: " + npuCount);

    for (var gpu : info.getGpusList()) {
        System.out.println("  " + gpu.getName() + " - " + gpu.getMemoryTotal() / 1024/1024/1024 + "GB");
    }
});
server.requestData(agentId, DataRequestType.DATA_REQUEST_STATIC);
```

#### Available Data Fields

<details>
<summary><b>STATIC - Hardware Info</b></summary>

| Category | Fields |
|----------|--------|
| CPU | model, vendor, physical_cores, logical_cores, architecture, frequency_max, cache sizes |
| Memory | total, swap_total, memory_type (DDR4/DDR5), speed_mhz, slots |
| Disks[] | device, mount_point, fs_type, model, serial, disk_type (SSD/HDD/NVMe), health_status |
| Networks[] | interface, mac_address, ip_addresses[], speed_mbps, interface_type |
| **GPUs[]** | index, name, vendor, memory_total, driver_version, pcie_generation, power_limit |
| **NPUs[]** | index, name, vendor, memory_total, driver_version |
| System | os_name, os_version, kernel, hostname, uptime, motherboard, bios |

</details>

<details>
<summary><b>FULL - Complete Metrics</b></summary>

All static info plus realtime: CPU usage/temp, memory used, disk IO, network IO, GPU usage/temp/power, load average, user sessions.

</details>

#### Security

> **Important:** Data Request is **read-only**. It can only request monitoring data, not execute commands.

| Feature | Data Request | Command Execution |
|---------|--------------|-------------------|
| Purpose | Request monitoring data | Execute operations |
| Security | Read-only | Requires authentication + permission |
| Risk Level | Low | High (can modify system) |

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
