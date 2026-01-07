# NanoLink

[![Test](https://github.com/chenqi92/NanoLink/actions/workflows/test.yml/badge.svg)](https://github.com/chenqi92/NanoLink/actions/workflows/test.yml)
[![Release](https://github.com/chenqi92/NanoLink/actions/workflows/release.yml/badge.svg)](https://github.com/chenqi92/NanoLink/actions/workflows/release.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[English](README.md) | 中文

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
                        gRPC + Protocol Buffers (TLS)
                              端口: 39100
                                   │
         ┌─────────────────────────┼─────────────────────────┐
         ▼                         ▼                         ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Java 服务     │     │    Go 服务      │     │  Python 服务    │
│   (集成 SDK)    │     │   (集成 SDK)    │     │   (集成 SDK)    │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                      WebSocket  │  端口: 9100
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

NanoLink 使用分层通信架构：

| 协议 | 端口 | 用途 | 特点 |
|------|------|------|------|
| **gRPC** | 39100 | Agent ↔ Server 通信 | 高性能、双向流、类型安全 |
| **WebSocket** | 9100 | Dashboard ↔ Server 通信 | 浏览器原生支持、实时更新 |
| **HTTP API** | 8080 | REST 管理接口 | 标准 HTTP 调用 |

> **注意**: Agent 现在只使用 gRPC 协议连接到服务端。Dashboard 仍使用 WebSocket 进行实时通信。

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
  --url "monitor.example.com:39100" \
  --token "your_token" \
  --permission 2
```

### Cloudflare R2 镜像（国内加速）☁️

国内用户推荐使用 R2 镜像源，下载速度更快：

**Linux/macOS:**
```bash
curl -fsSL https://agent.download.kkape.com/newest/install.sh | sudo bash
```

**Windows (PowerShell 管理员):**
```powershell
irm https://agent.download.kkape.com/newest/install.ps1 | iex
```

<details>
<summary><b>Agent 直接下载 (R2 镜像)</b></summary>

| 平台 | 架构 | 下载链接 |
|------|------|----------|
| Linux | x86_64 | [nanolink-agent-linux-x86_64](https://agent.download.kkape.com/newest/nanolink-agent-linux-x86_64) |
| Linux | ARM64 | [nanolink-agent-linux-aarch64](https://agent.download.kkape.com/newest/nanolink-agent-linux-aarch64) |
| macOS | Intel | [nanolink-agent-macos-x86_64](https://agent.download.kkape.com/newest/nanolink-agent-macos-x86_64) |
| macOS | Apple Silicon | [nanolink-agent-macos-aarch64](https://agent.download.kkape.com/newest/nanolink-agent-macos-aarch64) |
| Windows | x64 | [nanolink-agent-windows-x86_64.exe](https://agent.download.kkape.com/newest/nanolink-agent-windows-x86_64.exe) |

</details>

---

## 安装脚本详解（交互模式）

运行安装脚本时，会依次提示以下配置选项：

### 第一步：服务器地址

```
Server address (e.g., monitor.example.com:39100): 
```

| 格式 | 示例 | 说明 |
|------|------|------|
| `主机:端口` | `api.example.com:39100` | 完整格式，自定义端口 |
| `主机` | `api.example.com` | 使用默认端口 39100 |

> **注意:** 这是 NanoLink Server 的 gRPC 端点，不是 Web 地址。

### 第二步：认证令牌

```
Authentication Token: 
```

用于 Agent 向服务端验证身份的令牌。

| 来源 | 说明 |
|------|------|
| 服务端配置 `auth.tokens[].token` | 在服务端 `config.yaml` 中配置 |
| 管理后台 | 通过 Dashboard 界面生成 |

> **提示:** 如果服务端 `auth.enabled: false`，任何令牌值都会被接受。

### 第三步：权限级别

```
Permission Level
  1) Read Only (monitoring only)
  2) Read + Process Control
  3) Read + Process + Limited Shell
  4) Full Access (all operations)
Select [1-4]: 
```

| 级别 | 名称 | 可执行操作 |
|------|------|-----------|
| **0** (选项 1) | 只读 | 读取监控数据、查看进程、查看日志 |
| **1** (选项 2) | 基础写入 | + 下载文件、清理临时文件、上传文件 |
| **2** (选项 3) | 服务控制 | + 重启服务、Docker 容器、杀死进程 |
| **3** (选项 4) | 系统管理员 | + 重启服务器、执行 Shell 命令（需 SuperToken） |

### 第四步：TLS 配置

```
Enable TLS? [y/N]: 
```

| 选择 | 适用场景 |
|------|----------|
| **N** (否) | 服务端**未配置** HTTPS/TLS（自建服务器常见） |
| **Y** (是) | 服务端使用 TLS 证书（Let's Encrypt 等） |

如果选择是：

```
Verify TLS certificate? [Y/n]: 
```

| 选择 | 适用场景 |
|------|----------|
| **Y** (是) | 生产环境：服务端有有效的受信任证书 |
| **N** (否) | 仅测试：自签名证书（会有安全警告） |

> **⚠️ 常见错误:** 如果服务端没有配置 TLS，但 Agent 启用了 TLS，连接会失败并提示 "Cannot reach server"。

### 第五步：连接测试

```
Test server connection before installing? [Y/n]: 
```

测试到服务端的 TCP 连接。如果测试失败：
- 检查服务端是否运行
- 确认防火墙/安全组允许 39100 端口
- 确认 TLS 设置与服务端一致

### 第六步：主机名配置

```
Use system hostname (服务器名)? [Y/n]: 
```

| 选择 | 结果 |
|------|------|
| **Y** | 使用自动检测的主机名（如 `ubuntu-server`） |
| **N** | 输入自定义的显示名称 |

自定义主机名有助于识别服务器：
```
Custom hostname: prod-web-01
```

### 第七步：Shell 命令（权限 ≥ 2 时显示）

```
Enable shell command execution? (requires super token) [y/N]: 
```

| 选择 | 说明 |
|------|------|
| **N** | 禁用 Shell 访问（更安全） |
| **Y** | 启用 Shell，需要**独立的** SuperToken |

如果启用：
```
Shell Super Token (different from auth token): 
```

> **安全提示:** Shell SuperToken 与认证令牌不同，这为危险操作增加了额外的安全层。

---

## Token 类型说明

NanoLink 使用**多种不同类型的 Token**，用途各不相同：

| Token 类型 | 用途 | 配置位置 |
|------------|------|----------|
| **认证令牌 (Authentication Token)** | Agent ↔ Server 连接认证 | Agent: `servers[].token`<br>Server: `auth.tokens[].token` |
| **API 令牌 (API Token)** | 本地管理 API 访问 | Agent: `management.api_token` |
| **Shell 超级令牌 (Shell SuperToken)** | Shell 命令执行 | Agent: `shell.super_token` |

### 认证流程

```
Agent                                Server
  │                                    │
  │  携带 token="xxx" 连接              │
  ├───────────────────────────────────►│
  │                                    │
  │  Server 验证 auth.tokens[]          │
  │  ◄─────────────────────────────────┤
  │  返回：权限级别                     │
  │                                    │
```

### 服务端配置示例

```yaml
# Server config.yaml
auth:
  enabled: true
  tokens:
    - token: "prod-agent-token-1"
      permission: 2
      name: "生产服务器"
    
    - token: "dev-agent-token"
      permission: 3
      name: "开发环境"
```

---

## 静默安装参数

用于自动化/脚本化部署：

```bash
curl -fsSL URL | sudo bash -s -- [参数]
```

| 参数 | 说明 | 示例 |
|------|------|------|
| `--silent` | 非交互模式 | `--silent` |
| `--url` | 服务器地址 (host:port) | `--url "api.example.com:39100"` |
| `--token` | 认证令牌 | `--token "your_token"` |
| `--permission` | 权限级别 (0-3) | `--permission 2` |
| `--no-tls` | 禁用 TLS | `--no-tls` |
| `--hostname` | 自定义主机名 | `--hostname "prod-01"` |
| `--shell-enabled` | 启用 Shell | `--shell-enabled` |
| `--shell-token` | Shell SuperToken | `--shell-token "super_secret"` |
| `--lang` | 语言 (en/zh) | `--lang zh` |

**示例：**

```bash
# 最小化安装（禁用 TLS）
curl -fsSL URL | sudo bash -s -- --silent \
  --url "192.168.1.100:39100" \
  --token "my_token" \
  --no-tls

# 生产环境完整配置（启用 TLS）
curl -fsSL URL | sudo bash -s -- --silent \
  --url "monitor.example.com:39100" \
  --token "prod_token" \
  --permission 2 \
  --hostname "web-server-01"

# 启用 Shell 访问
curl -fsSL URL | sudo bash -s -- --silent \
  --url "monitor.example.com:39100" \
  --token "admin_token" \
  --permission 3 \
  --shell-enabled \
  --shell-token "super_admin_token"
```

---

## 安装问题排查

### "Cannot reach server" 无法连接服务器

| 原因 | 解决方案 |
|------|----------|
| TLS 不匹配 | 如果服务端没有 TLS，选择 `Enable TLS? [y/N]: N` |
| 防火墙 | 开放 39100 端口（或你的自定义端口） |
| 服务端未运行 | 先启动 NanoLink Server |
| 端口错误 | 确认 gRPC 端口（默认：39100） |

### "Management API token not set" 管理 API 令牌未设置

Agent 配置中 `management.enabled: true` 但未设置 `api_token`：

```bash
# 修复：编辑配置文件
sudo nano /etc/nanolink/nanolink.yaml

# 修改为：
management:
  enabled: false  # 如果不需要，直接禁用
  # 或者设置 token：
  # enabled: true
  # api_token: "your_local_api_token"

# 重启服务
sudo systemctl restart nanolink-agent
```

### 查看 Agent 日志

```bash
# Linux
sudo journalctl -u nanolink-agent -f

# macOS
tail -f /var/log/nanolink/agent.log

# Windows (PowerShell)
Get-Content "C:\ProgramData\NanoLink\logs\agent.log" -Wait
```

### 交互式 CLI 模式

直接运行 `nanolink-agent`（不带参数）即可进入交互式模式，提供用户友好的菜单界面。CLI 会自动检测系统语言（支持中文/英文）。

```
$ nanolink-agent

╭──────────────────────────────────────╮
│       NanoLink Agent v1.0.0          │
╰──────────────────────────────────────╯

? 请选择操作:
❯ 启动 Agent
  管理服务器
  查看状态
  初始化配置
  退出
```

**服务器管理菜单:**
```
? 已配置的服务器:
❯ 192.168.1.100:39100 [只读]
  10.0.0.5:39100 [系统管理员]
  ──────────────────
  + 添加新服务器
  ← 返回主菜单
```

**服务器操作:**
```
? 对 192.168.1.100:39100 执行操作:
❯ 更新配置
  删除服务器
  测试连接
  返回
```

交互式模式支持：
- **添加服务器**：分步向导添加新的服务器连接
- **更新服务器**：修改令牌、权限或 TLS 设置
- **删除服务器**：移除服务器配置
- **测试连接**：在使用前验证服务器连通性
- **查看状态**：检查 Agent 运行状态和已连接的服务器

> **提示**: 你仍然可以使用命令行参数进行脚本化操作。交互式模式仅在不提供任何参数时激活。

### 多服务端管理

Agent 支持同时连接多个服务端，可以动态添加/删除/更新服务端配置。

**添加新服务端:**
```bash
# 使用安装脚本
sudo ./install.sh --add-server --host "second.example.com" --port 39100 --token "token2"

# 使用 Agent CLI
nanolink-agent server add --host "second.example.com" --port 39100 --token "token2" --permission 1

# 使用管理 API (热更新)
curl -X POST http://localhost:9101/api/servers \
  -H "Content-Type: application/json" \
  -d '{"host":"second.example.com","port":39100,"token":"token2","permission":1}'
```

**删除服务端:**
```bash
# 使用 Agent CLI
nanolink-agent server remove --host "old.example.com" --port 39100

# 使用管理 API
curl -X DELETE "http://localhost:9101/api/servers?host=old.example.com&port=39100"
```

**查看当前服务端:**
```bash
nanolink-agent server list
```

### Web Dashboard - 添加代理向导

Dashboard 提供分步向导帮助你轻松部署代理。点击仪表盘上的 **"添加代理"** 按钮即可开始。

**第一步：选择平台**
```
┌─────────────────────────────────────┐
│  添加代理 - 步骤 1/3                │
├─────────────────────────────────────┤
│  选择目标操作系统:                  │
│                                     │
│  ┌─────────┐ ┌─────────┐ ┌────────┐ │
│  │  Linux  │ │ Windows │ │ macOS  │ │
│  └─────────┘ └─────────┘ └────────┘ │
│                                     │
│            [下一步]                 │
└─────────────────────────────────────┘
```

**第二步：配置代理**
```
┌─────────────────────────────────────┐
│  添加代理 - 步骤 2/3                │
├─────────────────────────────────────┤
│  代理名称: [可选，自动生成]         │
│                                     │
│  权限级别:                          │
│  ○ 只读 (READ_ONLY)                 │
│  ● 基本写入 (BASIC_WRITE)           │
│  ○ 服务控制 (SERVICE_CONTROL)       │
│  ○ 系统管理员 (SYSTEM_ADMIN)        │
│                                     │
│  ☐ 启用远程终端                     │
│  ☐ 启用 TLS 加密                    │
│                                     │
│     [上一步]        [下一步]        │
└─────────────────────────────────────┘
```

**第三步：获取安装命令**
```
┌─────────────────────────────────────┐
│  添加代理 - 步骤 3/3                │
├─────────────────────────────────────┤
│  在目标服务器上运行以下命令:        │
│                                     │
│  ┌─────────────────────────────────┐│
│  │ curl -sSL https://xxx/install  ││
│  │   | bash -s -- \               ││
│  │   --server "192.168.1.100:391" ││
│  │   --token "eyJhbGci..."        ││
│  └─────────────────────────────────┘│
│                         [复制]      │
│                                     │
│  或下载预配置的安装包:              │
│  [Linux] [Windows] [macOS]          │
│                                     │
│     [完成]                          │
└─────────────────────────────────────┘
```

向导自动完成以下功能：
- 生成一次性认证令牌
- 从当前连接自动检测服务器 URL
- 创建平台特定的安装命令
- 提供 YAML 配置供手动配置使用

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
  # gRPC 连接 (高性能、类型安全)
  - host: monitor.example.com
    port: 39100           # 默认 gRPC 端口
    token: "your-auth-token"
    permission: 2
    tls_enabled: false    # 生产环境推荐使用 true
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
    <version>0.3.7</version>
</dependency>
```

```java
NanoLinkServer server = NanoLinkServer.builder()
    .wsPort(9100)       // Dashboard WebSocket 端口
    .grpcPort(39100)    // Agent gRPC 端口
    .staticFilesPath("/path/to/dashboard")  // 可选：外部 Dashboard 路径
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
    WsPort:   9100,    // Dashboard WebSocket 端口
    GrpcPort: 39100,   // Agent gRPC 端口
    // StaticFilesPath: "/path/to/dashboard",  // 可选
})

server.OnAgentConnect(func(agent *nanolink.AgentConnection) {
    log.Printf("Agent 连接: %s (%s)", agent.Hostname, agent.OS)
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
        ws_port=9100,    # Dashboard WebSocket 端口
        grpc_port=39100  # Agent gRPC 端口
    )
    server = NanoLinkServer(config)

    @server.on_agent_connect
    async def on_connect(agent):
        print(f"Agent 连接: {agent.hostname} ({agent.os})")

    @server.on_metrics
    async def on_metrics(metrics):
        print(f"CPU: {metrics.cpu.usage_percent:.1f}%")

    await server.run_forever()

asyncio.run(main())
```

### 数据请求 API

SDK 可以主动向 Agent 请求特定数据，适用于实时仪表盘场景。

#### 分层数据推送机制

| 层级 | 数据类型 | 默认间隔 | 描述 |
|------|----------|----------|------|
| 静态层 | 硬件信息 | 连接时一次 | CPU 型号、内存大小、磁盘设备 |
| 实时层 | 动态指标 | 5 秒 | CPU 使用率、内存、磁盘/网络 IO |
| 周期层 | 低频数据 | 30-60 秒 | 磁盘使用量、用户会话 |

#### 支持的请求类型

| 类型 | 描述 |
|------|------|
| `FULL` | 完整指标 |
| `STATIC` | 静态硬件信息 |
| `DISK_USAGE` | 磁盘容量 |
| `NETWORK_INFO` | 网络详情 |
| `USER_SESSIONS` | 登录用户 |
| `GPU_INFO` | GPU 信息 |
| `HEALTH` | 磁盘 S.M.A.R.T. 状态 |

#### 使用示例

**Java:**
```java
// 向特定 Agent 请求
server.requestData(agentId, DataRequestType.DATA_REQUEST_STATIC);

// 向所有 Agent 广播
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

#### 响应处理

响应通过现有回调到达。示例 - 获取 GPU 个数：

**Java:**
```java
server.onStaticInfo(info -> {
    int gpuCount = info.getGpusList().size();
    int npuCount = info.getNpusList().size();
    System.out.println("GPU 数量: " + gpuCount + ", NPU 数量: " + npuCount);

    for (var gpu : info.getGpusList()) {
        System.out.println("  " + gpu.getName() + " - " + gpu.getMemoryTotal() / 1024/1024/1024 + "GB");
    }
});
server.requestData(agentId, DataRequestType.DATA_REQUEST_STATIC);
```

#### 可用数据字段

<details>
<summary><b>STATIC - 硬件信息</b></summary>

| 类别 | 字段 |
|------|------|
| CPU | 型号、厂商、物理核心、逻辑核心、架构、最大频率、缓存大小 |
| 内存 | 总量、Swap、类型 (DDR4/DDR5)、速度、插槽数 |
| 磁盘[] | 设备、挂载点、文件系统、型号、序列号、类型 (SSD/HDD/NVMe)、健康状态 |
| 网络[] | 接口、MAC 地址、IP 地址列表、速度、接口类型 |
| **GPU[]** | 索引、名称、厂商、显存总量、驱动版本、PCIe 代数、功耗限制 |
| **NPU[]** | 索引、名称、厂商、内存总量、驱动版本 |
| 系统 | 操作系统、版本、内核、主机名、运行时间、主板、BIOS |

</details>

<details>
<summary><b>FULL - 完整指标</b></summary>

所有静态信息 + 实时数据：CPU 使用率/温度、内存使用、磁盘 IO、网络 IO、GPU 使用率/温度/功耗、负载均衡、用户会话。

</details>

#### 安全性

> **重要:** 数据请求是**只读**的，只能请求监控数据，不能执行命令。

| 特性 | 数据请求 | 命令执行 |
|------|----------|----------|
| 目的 | 请求监控数据 | 执行操作 |
| 安全性 | 只读 | 需要认证 + 权限 |
| 风险级别 | 低 | 高（可修改系统） |

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
