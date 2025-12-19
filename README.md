# NanoLink

[![Test](https://github.com/chenqi92/NanoLink/actions/workflows/test.yml/badge.svg)](https://github.com/chenqi92/NanoLink/actions/workflows/test.yml)
[![Release](https://github.com/chenqi92/NanoLink/actions/workflows/release.yml/badge.svg)](https://github.com/chenqi92/NanoLink/actions/workflows/release.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[English](README_EN.md) | 中文

**NanoLink** 是一个轻量级、跨平台的服务器监控系统，包含 Agent、SDK、Dashboard 和独立应用程序。

## 核心组件

| 组件 | 描述 | 技术栈 |
|------|------|--------|
| [Agent](./agent) | 部署在目标服务器的监控代理 | Rust |
| [SDK](./sdk) | 嵌入现有服务的客户端库 | Java / Go / Python |
| [Dashboard](./dashboard) | Web 可视化面板 | Vue 3 + TailwindCSS |
| [Apps](./apps) | 独立部署的完整应用 | Go + Tauri |

## 系统架构

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              目标服务器                                      │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                         NanoLink Agent (Rust)                          │  │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐          │  │
│  │  │   CPU   │ │  Memory │ │  Disk   │ │ Network │ │   GPU   │          │  │
│  │  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘          │  │
│  │       └───────────┴───────────┴───────────┴───────────┘               │  │
│  │                               │                                        │  │
│  │                    ┌──────────▼──────────┐                             │  │
│  │                    │     Ring Buffer     │  ← 10分钟离线数据缓存        │  │
│  │                    └──────────┬──────────┘                             │  │
│  │                               │                                        │  │
│  │                    ┌──────────▼──────────┐                             │  │
│  │                    │   Connection Mgr    │  ← 多服务端连接 + 自动重连    │  │
│  │                    └──────────┬──────────┘                             │  │
│  └───────────────────────────────┼───────────────────────────────────────┘  │
└──────────────────────────────────┼──────────────────────────────────────────┘
                                   │
                    WebSocket / gRPC + Protocol Buffers (TLS)
                                   │
         ┌─────────────────────────┼─────────────────────────┐
         ▼                         ▼                         ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Java 服务     │     │    Go 服务      │     │  Python 服务    │
│   (集成 SDK)    │     │   (集成 SDK)    │     │   (集成 SDK)    │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         └───────────────────────┴───────────────────────┘
                                 │
                      ┌──────────▼──────────┐
                      │     Dashboard       │
                      │     (Vue 3)         │
                      └─────────────────────┘
```

### 独立应用架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    NanoLink Applications                         │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │  Linux Server   │  │ Windows Desktop │  │  macOS Desktop  │  │
│  │   (Go + Web)    │  │    (Tauri)      │  │    (Tauri)      │  │
│  │                 │  │                 │  │                 │  │
│  │  Docker 部署    │  │   原生桌面应用   │  │   原生桌面应用   │  │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘  │
│           └────────────────────┴────────────────────┘           │
│                                │                                 │
│                     ┌──────────▼──────────┐                      │
│                     │   NanoLink Server   │                      │
│                     │ (WebSocket/gRPC+API)│                      │
│                     └─────────────────────┘                      │
└─────────────────────────────────────────────────────────────────┘
```

## 功能特性

### Agent 功能

| 功能 | 描述 |
|------|------|
| 硬件监控 | CPU、内存、磁盘、网络、GPU 全面采集 |
| 断线缓存 | Ring Buffer 存储 10 分钟数据，重连后补发 |
| 多服务端 | 支持同时连接多个服务端，不同权限级别 |
| 自动重连 | 指数退避重连策略，最大延迟可配置 |
| 命令执行 | 进程管理、服务控制、文件操作、Docker 操作 |
| 跨平台 | Linux、macOS、Windows 全平台支持 |

### 监控指标

<details>
<summary><b>CPU</b></summary>

- 总使用率、每核使用率、负载均衡
- 型号、厂商 (Intel/AMD/Apple)
- 当前频率、最大频率、基础频率
- 物理核心数、逻辑核心数
- 架构 (x86_64/aarch64)
- 温度 (Linux/macOS)
- L1/L2/L3 缓存大小

</details>

<details>
<summary><b>内存</b></summary>

- 总量、已用、可用、使用率
- Swap 总量、已用
- 缓存、缓冲区 (Linux)
- 内存类型 (DDR4/DDR5)
- 内存速度 (MHz)

</details>

<details>
<summary><b>磁盘</b></summary>

- 挂载点、设备名、文件系统类型
- 总容量、已用、可用
- 读写速率 (bytes/s)、IOPS
- 型号、序列号、厂商
- 类型 (SSD/HDD/NVMe)
- 温度、S.M.A.R.T. 健康状态

</details>

<details>
<summary><b>网络</b></summary>

- 接口名、类型 (物理/虚拟)
- 收发速率 (bytes/s)、数据包/秒
- MAC 地址、IPv4/IPv6 地址
- 链路速度、MTU
- 连接状态

</details>

<details>
<summary><b>GPU (NVIDIA/AMD/Intel)</b></summary>

- 型号、厂商、驱动版本
- GPU 使用率、显存使用量
- 温度、风扇转速
- 功耗、功耗限制
- 核心频率、显存频率
- PCIe 信息 (代数、带宽)
- 编码器/解码器使用率

</details>

<details>
<summary><b>系统信息</b></summary>

- 操作系统名称、版本
- 内核版本
- 主机名
- 启动时间、运行时间
- 主板型号、厂商
- BIOS 版本

</details>

### 权限等级

| 等级 | 名称 | 可执行操作 |
|------|------|-----------|
| 0 | READ_ONLY | 读取监控数据、查看进程列表、查看日志 |
| 1 | BASIC_WRITE | 下载日志文件、清理临时文件、上传文件 |
| 2 | SERVICE_CONTROL | 重启服务、重启 Docker 容器、杀死进程 |
| 3 | SYSTEM_ADMIN | 重启服务器、执行 Shell 命令 (需 SuperToken) |

### 通信协议

NanoLink 支持两种通信协议，可根据场景选择：

| 协议 | 适用场景 | 特点 |
|------|----------|------|
| **WebSocket** | 浏览器 Dashboard、兼容性要求高 | 浏览器原生支持，JSON-friendly |
| **gRPC** | 高性能 Agent 连接、服务间通信 | 双向流、高吞吐、低延迟 |

**URL 格式：**
- WebSocket: `ws://` / `wss://` (推荐使用 TLS)
- gRPC: `grpc://` / `grpcs://` (推荐使用 TLS)

**端口默认值：**
- WebSocket: 9100
- gRPC: 9200
- HTTP API: 8080

### 安全机制

| 机制 | 描述 |
|------|------|
| TLS 加密 | 所有通信 (WebSocket/gRPC) 强制 TLS |
| Token 认证 | 每个连接使用独立 Token |
| 命令白名单 | 只允许执行预定义的命令模式 |
| 命令黑名单 | 危险命令始终被阻止 |
| SuperToken | Shell 命令需要独立的超级令牌 |
| 审计日志 | 记录所有命令执行到本地文件 |
| 速率限制 | 防止命令洪水攻击 |

## 快速开始

### 一键安装 Agent

**Linux/macOS (交互式):**
```bash
curl -fsSL https://raw.githubusercontent.com/chenqi92/NanoLink/main/agent/scripts/install.sh | sudo bash
```

**Windows (PowerShell 管理员):**
```powershell
irm https://raw.githubusercontent.com/chenqi92/NanoLink/main/agent/scripts/install.ps1 | iex
```

**静默安装 (自动化部署):**
```bash
curl -fsSL https://raw.githubusercontent.com/chenqi92/NanoLink/main/agent/scripts/install.sh | sudo bash -s -- \
  --silent \
  --url "wss://monitor.example.com:9100" \
  --token "your_token" \
  --permission 2
```

### 多服务端管理

Agent 支持同时连接多个服务端，可以动态添加/删除/更新服务端配置。

**添加新服务端:**
```bash
# 使用安装脚本
sudo ./install.sh --add-server --url "wss://second.example.com:9100" --token "token2"

# 使用 Agent CLI
nanolink-agent server add --url "wss://second.example.com:9100" --token "token2" --permission 1

# 使用管理 API (热更新)
curl -X POST http://localhost:9101/api/servers \
  -H "Content-Type: application/json" \
  -d '{"url":"wss://second.example.com:9100","token":"token2","permission":1}'
```

**删除服务端:**
```bash
# 使用安装脚本
sudo ./install.sh --remove-server --url "wss://old.example.com:9100"

# 使用 Agent CLI
nanolink-agent server remove --url "wss://old.example.com:9100"

# 使用管理 API
curl -X DELETE "http://localhost:9101/api/servers?url=wss://old.example.com:9100"
```

**查看当前服务端:**
```bash
nanolink-agent server list
```

### 使用 Docker 部署服务端

```bash
# 使用 docker-compose
cd apps/docker
docker-compose up -d

# 或直接运行
docker run -d \
  -p 8080:8080 \
  -p 9100:9100 \
  ghcr.io/chenqi92/nanolink-server:latest
```

访问 Dashboard: http://localhost:8080/dashboard

### Agent 配置

```yaml
# /etc/nanolink/nanolink.yaml
agent:
  hostname: ""  # 留空自动检测
  heartbeat_interval: 30
  reconnect_delay: 5
  max_reconnect_delay: 300

servers:
  # WebSocket 连接 (兼容浏览器 Dashboard)
  - url: "wss://monitor.example.com:9100"
    token: "your-auth-token"
    permission: 0
    tls_verify: true
  # gRPC 连接 (高性能双向流)
  - url: "grpcs://monitor.example.com:9200"
    token: "your-auth-token"
    permission: 2
    tls_verify: true

collector:
  cpu_interval_ms: 1000
  disk_interval_ms: 3000
  network_interval_ms: 1000
  enable_per_core_cpu: true

buffer:
  capacity: 600  # 10分钟 (1秒采样)

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

## SDK 集成

### Java SDK

```xml
<dependency>
    <groupId>com.kkape</groupId>
    <artifactId>nanolink-sdk</artifactId>
    <version>0.1.0</version>
</dependency>
```

```java
NanoLinkServer server = NanoLinkServer.builder()
    .port(9100)
    .enableDashboard(true)
    .onAgentConnect(agent -> {
        log.info("Agent 连接: {} ({})", agent.getHostname(), agent.getOs());
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
    Port:            9100,
    EnableDashboard: true,
})

server.OnAgentConnect(func(agent *nanolink.Agent) {
    log.Printf("Agent 连接: %s (%s)", agent.Hostname, agent.OS)
})

server.OnMetrics(func(m *nanolink.Metrics) {
    log.Printf("CPU: %.1f%% | Memory: %.1f%%",
        m.Cpu.UsagePercent, m.Memory.UsedPercent)
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
    server = NanoLinkServer(ServerConfig(port=9100))

    @server.on_agent_connect
    async def on_connect(agent):
        print(f"Agent 连接: {agent.hostname} ({agent.os})")

    @server.on_metrics
    async def on_metrics(metrics):
        print(f"CPU: {metrics.cpu.usage_percent:.1f}%")

    await server.run_forever()

asyncio.run(main())
```

## 项目结构

```
NanoLink/
├── agent/                      # Rust Agent
│   ├── src/
│   │   ├── collector/          # 数据采集器
│   │   │   ├── cpu.rs
│   │   │   ├── memory.rs
│   │   │   ├── disk.rs
│   │   │   ├── network.rs
│   │   │   └── gpu.rs
│   │   ├── connection/         # WebSocket/gRPC 客户端
│   │   ├── executor/           # 命令执行器
│   │   ├── buffer/             # Ring Buffer
│   │   ├── security/           # 权限系统
│   │   └── platform/           # 平台特定代码
│   ├── scripts/                # 安装/卸载脚本
│   └── systemd/                # Linux 服务配置
│
├── sdk/                        # 多语言 SDK
│   ├── protocol/               # Protocol Buffers 定义
│   │   └── nanolink.proto
│   ├── java/                   # Java SDK (Maven)
│   ├── go/                     # Go SDK (Module)
│   └── python/                 # Python SDK (PyPI)
│
├── dashboard/                  # Web Dashboard
│   ├── src/
│   │   ├── components/         # Vue 组件
│   │   └── composables/        # WebSocket 组合式函数
│   └── package.json
│
├── apps/                       # 独立应用程序
│   ├── server/                 # Go Web 服务端
│   │   ├── cmd/                # 入口
│   │   ├── internal/           # 内部模块
│   │   │   ├── grpc/           # gRPC 服务端
│   │   │   ├── handler/        # HTTP/WebSocket 处理器
│   │   │   └── proto/          # 生成的 Proto 代码
│   │   └── web/                # 嵌入式 Dashboard
│   ├── desktop/                # Tauri 桌面应用
│   │   ├── src/                # Vue 前端
│   │   └── src-tauri/          # Rust 后端
│   └── docker/                 # Docker 配置
│       ├── Dockerfile
│       ├── docker-compose.yml
│       └── docker-compose.build.yml
│
├── demo/                       # 集成示例
│   └── spring-boot/            # Spring Boot 示例
│
├── scripts/                    # 工具脚本
│   ├── bump-version.sh         # 版本更新 (Linux/macOS)
│   └── bump-version.ps1        # 版本更新 (Windows)
│
└── .github/workflows/          # CI/CD
    ├── test.yml                # 测试
    ├── release.yml             # Agent 发布
    ├── sdk-release.yml         # SDK 发布
    └── apps-release.yml        # 应用发布
```

## 构建

### Agent (Rust)

```bash
cd agent
cargo build --release
# 输出: target/release/nanolink-agent
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

### 独立应用

```bash
# Linux Server (Docker)
cd apps/docker && docker-compose build

# Desktop (需要 Rust + Node.js)
cd apps/desktop && npm install && npm run tauri build
```

## 服务管理

### Linux (systemd)

```bash
sudo systemctl start nanolink-agent    # 启动
sudo systemctl stop nanolink-agent     # 停止
sudo systemctl restart nanolink-agent  # 重启
sudo systemctl status nanolink-agent   # 状态
sudo journalctl -u nanolink-agent -f   # 日志
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

| 工作流 | 触发条件 | 产物 |
|--------|----------|------|
| Test | PR / Push | 测试报告 |
| Release Agent | Tag `v*` | 多平台二进制 |
| SDK Release | Tag `sdk-v*` | Maven / PyPI / GitHub |
| Apps Release | Tag `app-v*` | Docker 镜像 / 安装包 |

## 许可证

MIT License - 详见 [LICENSE](LICENSE)

## 贡献

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/xxx`)
3. 提交更改 (`git commit -m 'Add xxx'`)
4. 推送分支 (`git push origin feature/xxx`)
5. 创建 Pull Request
