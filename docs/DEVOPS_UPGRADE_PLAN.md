# NanoLink DevOps 运维功能升级计划

本文档描述将 NanoLink 从监控平台升级为完整运维操作平台所需的各组件升级内容。

---

## 目录

- [功能现状](#功能现状)
- [升级目标](#升级目标)
- [Agent 升级计划](#agent-升级计划)
- [SDK 升级计划](#sdk-升级计划)
- [Server 升级计划](#server-升级计划)
- [Proto 协议升级](#proto-协议升级)
- [安全考量](#安全考量)
- [实施路线图](#实施路线图)

---

## 功能现状

### 已实现功能

| 功能类别 | 状态 | 说明 |
|----------|:----:|------|
| 系统监控 | ✅ | CPU/内存/磁盘/网络/GPU/NPU 200+ 指标 |
| 进程管理 | ✅ | 列表、杀死进程 |
| 服务管理 | ✅ | 启动/停止/重启/状态查询 |
| Docker 管理 | ✅ | 容器列表/启停/日志 |
| 文件操作 | ✅ | 读取/下载/上传/截断 |
| Shell 执行 | ✅ | 命令执行 (需 SuperToken) |
| Agent 自更新 | ✅ | 检查/下载/应用更新 |
| 按需数据请求 | ✅ | Server 可主动请求 Agent 发送特定数据 |
| 分层数据传输 | ✅ | Static/Realtime/Periodic 三层架构 |
| 权限控制 | ✅ | 4 级权限 (READ_ONLY/BASIC_WRITE/SERVICE_CONTROL/SYSTEM_ADMIN) |

### 已升级功能

| 功能类别 | 状态 | 说明 |
|----------|:----:|------|
| 日志查询 | ✅ | journald/系统日志/审计日志查询 + 敏感信息脱敏 |
| 版本管理 | ✅ | 包列表/检查更新/更新包/系统更新 (多平台支持) |
| 预定义脚本 | ✅ | 安全的脚本执行框架 + 参数验证 + 可选签名验证 |
| 操作审计 | ✅ | Server 端完整的操作日志追踪 + REST API |
| 配置管理 | ✅ | 远程配置读写 + 自动备份 + 回滚支持 |

---

## 升级目标

1. **日志查询增强** - 查询 systemd/journald/审计日志，支持脱敏
2. **版本管理** - 包列表/检查更新/更新包
3. **预定义脚本** - 在沙箱中执行预定义的安全脚本
4. **操作审计** - 记录所有命令执行历史
5. **配置管理** - 远程读写配置文件，自动备份和回滚

---

## Agent 升级计划

### 新增 Executor 模块

| 模块 | 文件 | 功能 |
|------|------|------|
| 日志操作 | `log_ops.rs` | journald 日志、系统日志、审计日志查询 |
| 包管理 | `package_mgr.rs` | 列出包、检查更新、更新包 |
| 脚本执行 | `script_executor.rs` | 预定义脚本列表和执行 |
| 配置管理 | `config_mgr.rs` | 配置读取、写入、回滚 |

### 日志操作模块 (`log_ops.rs`)

**功能:**
- `get_service_logs()` - 查询 journald/systemd 服务日志
- `get_system_logs()` - 查询 /var/log 系统日志
- `get_audit_logs()` - 查询 auditd 审计日志
- `stream_logs()` - 实时日志流 (类似 tail -f)

**输入验证要求:**
- 服务名必须是有效的 systemd 服务名
- 日志文件路径必须在白名单内
- 过滤器必须过滤危险字符

### 包管理模块 (`package_mgr.rs`)

**功能:**
- `list_packages()` - 列出已安装包
- `check_updates()` - 检查可更新的包
- `update_package()` - 更新指定包 (危险操作)
- `update_system()` - 系统全量更新 (危险操作)

**平台适配:**
| 平台 | 包管理器 |
|------|---------|
| Debian/Ubuntu | apt |
| RHEL/CentOS | yum, dnf |
| Arch | pacman |
| macOS | brew |
| Windows | winget, choco |

### 脚本执行模块 (`script_executor.rs`)

**功能:**
- `list_scripts()` - 列出可用脚本
- `execute_script()` - 执行预定义脚本
- `verify_script()` - 验证脚本签名

**安全设计:**
- 只能执行 `scripts/` 目录下的预定义脚本
- 可选脚本签名验证 (SHA256)
- 参数白名单验证
- 沙箱执行 (firejail/bubblewrap)

### 配置管理模块 (`config_mgr.rs`)

**功能:**
- `read_config()` - 读取配置文件
- `write_config()` - 写入配置文件 (自动备份)
- `validate_config()` - 验证配置语法
- `rollback_config()` - 回滚到上一版本

### 配置文件升级

新增配置项:

```yaml
# 日志配置
logs:
  allowed_paths: [/var/log/syslog, /var/log/messages]
  max_lines: 10000

# 脚本配置
scripts:
  enabled: true
  scripts_dir: /opt/nanolink/scripts
  require_signature: false

# 配置管理
config_management:
  enabled: true
  allowed_configs: [/etc/nginx/nginx.conf]
  backup_on_change: true
  max_backups: 10

# 包管理
package_management:
  enabled: true
  allow_update: false  # 默认禁用
```

---

## SDK 升级计划

### 各语言 SDK 更新

Proto 更新后，所有 SDK 需要重新生成代码并添加新的 Command 辅助函数。

| SDK | 新增文件 | 状态 |
|-----|---------|:----:|
| Java | `LogCommands.java`, `PackageCommands.java`, `ScriptCommands.java` | 待完成 |
| Go | `commands.go` | 待完成 |
| Python | `commands.py` | 待完成 |

### 新增命令辅助函数

**日志命令:**
- `serviceLogs(serviceName, lines)` - 查询服务日志
- `systemLogs(logFile, lines, filter)` - 查询系统日志
- `auditLogs(since, filter)` - 查询审计日志

**包管理命令:**
- `listPackages(filter)` - 列出包
- `checkUpdates()` - 检查更新
- `updatePackage(packageName, superToken)` - 更新包

**脚本命令:**
- `listScripts()` - 列出脚本
- `executeScript(scriptName, args)` - 执行脚本

**配置命令:**
- `readConfig(path)` - 读取配置
- `writeConfig(path, content, backup)` - 写入配置

---

## Server 升级计划

### 已完成功能

| 功能 | 文件 | 说明 |
|------|------|------|
| ✅ DataRequest | `grpc/server.go`, `handler/data_request.go` | 按需请求 Agent 数据 |

**DataRequest API:**
```
POST /api/agents/:id/data-request   # 请求单个 Agent
POST /api/agents/data-request       # 请求所有 Agent (需超管)
```

支持类型: `full`, `static`, `disk_usage`, `network_info`, `user_sessions`, `gpu_info`, `health`

### 待实现功能

#### 操作审计系统

**数据表结构:**

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER | 主键 |
| timestamp | DATETIME | 操作时间 |
| user_id | INTEGER | 用户 ID |
| username | VARCHAR | 用户名 |
| agent_id | VARCHAR | Agent ID |
| agent_hostname | VARCHAR | Agent 主机名 |
| command_type | VARCHAR | 命令类型 |
| target | VARCHAR | 操作目标 |
| params | TEXT | 参数 (JSON) |
| success | BOOLEAN | 是否成功 |
| error | TEXT | 错误信息 |
| duration_ms | INTEGER | 执行时长 |

**REST API:**
```
GET /audit/logs                    # 查询审计日志
GET /audit/logs/user/:userId       # 查询用户操作
GET /audit/logs/agent/:agentId     # 查询 Agent 操作
```

#### 运维操作 API

```
POST /agents/:id/logs/service      # 查询服务日志
POST /agents/:id/logs/system       # 查询系统日志
GET  /agents/:id/packages          # 获取包列表
POST /agents/:id/packages/update   # 更新包 (需超管)
GET  /agents/:id/scripts           # 获取脚本列表
POST /agents/:id/scripts/execute   # 执行脚本
GET  /agents/:id/config            # 读取配置
PUT  /agents/:id/config            # 写入配置
```

#### 权限细化

支持用户对特定 Agent 的命令级权限控制:
- 允许的命令列表
- 禁止的命令列表
- 最高权限级别

---

## Proto 协议升级

### 新增 CommandType

| Code | 命令 | 说明 |
|------|------|------|
| **日志命令** |
| 60 | SERVICE_LOGS | 查询服务日志 (journald) |
| 61 | SYSTEM_LOGS | 查询系统日志 (/var/log) |
| 62 | AUDIT_LOGS | 查询审计日志 |
| 63 | LOG_STREAM | 实时日志流 |
| **包管理命令** |
| 70 | PACKAGE_LIST | 列出已安装包 |
| 71 | PACKAGE_CHECK | 检查可更新包 |
| 72 | PACKAGE_UPDATE | 更新指定包 |
| 73 | SYSTEM_UPDATE | 系统全量更新 |
| **脚本命令** |
| 80 | SCRIPT_LIST | 列出可用脚本 |
| 81 | SCRIPT_EXECUTE | 执行预定义脚本 |
| 82 | SCRIPT_UPLOAD | 上传新脚本 |
| **配置命令** |
| 90 | CONFIG_READ | 读取配置文件 |
| 91 | CONFIG_WRITE | 写入配置文件 |
| 92 | CONFIG_VALIDATE | 验证配置语法 |
| 93 | CONFIG_ROLLBACK | 回滚配置 |
| **健康检查** |
| 100 | HEALTH_CHECK | 自定义健康检查 |
| 101 | CONNECTIVITY_TEST | 网络连通性测试 |

### 新增响应消息

| 消息 | 字段 |
|------|------|
| LogQueryResult | lines, total_lines, log_source, timestamps |
| PackageInfo | name, version, description, update_available, new_version |
| ScriptInfo | name, description, category, required_args, required_permission |

---

## 安全考量

### 核心安全风险

| 功能 | 风险类型 | 等级 | 典型场景 |
|------|---------|:----:|---------|
| 日志查询 | 敏感信息泄露 | 🔴 高 | 日志中包含数据库密码、API 密钥 |
| 配置读取 | 凭证泄露 | 🔴 高 | 配置文件包含明文密码 |
| 配置写入 | 后门植入 | 🔴 高 | 修改 SSH 配置允许未授权访问 |
| 脚本执行 | 命令注入 | 🟠 中 | 参数注入恶意命令 |
| 包管理 | 供应链攻击 | 🟠 中 | 安装被篡改的软件包 |

### 安全机制

#### 1. 日志脱敏系统 (必须实现)

**需要脱敏的敏感信息:**
- 密码模式: `password=xxx`, `passwd:xxx`
- API 密钥: `api_key=xxx`, `secret_key=xxx`
- Bearer Token: `Bearer eyJhbGci...`
- 数据库连接串: `mysql://user:password@host`
- AWS 密钥: `AKIA...`, `aws_secret_access_key`
- 私钥内容: `-----BEGIN PRIVATE KEY-----`

#### 2. 配置文件分级

| 级别 | 说明 | 示例 |
|------|------|------|
| Public | 可直接读取 | /etc/nginx/nginx.conf, /etc/hosts |
| Sensitive | 需脱敏 | /etc/mysql/my.cnf, /etc/redis/redis.conf |
| Secret | 禁止 API 读取 | /etc/shadow, SSH 私钥 |

**始终禁止访问:**
- /etc/shadow, /etc/gshadow
- /etc/ssh/ssh_host_*_key
- /root/.ssh/*
- /etc/ssl/private/*
- /var/lib/mysql, /var/lib/postgresql

#### 3. 脚本执行安全

**危险字符过滤:**
`| & ; $ \` ( ) { } < > \n \r ' " \`

**沙箱执行选项:**
- firejail - 轻量级沙箱
- bubblewrap - 更严格的沙箱

**资源限制:**
- 内存: 256MB
- CPU 时间: 60秒
- 文件大小: 10MB
- 进程数: 10

#### 4. 权限矩阵

| 命令类型 | Level 0 | Level 1 | Level 2 | Level 3 | 额外要求 |
|----------|:-------:|:-------:|:-------:|:-------:|---------|
| **日志查询** |
| SERVICE_LOGS | ✅¹ | ✅¹ | ✅ | ✅ | ¹强制脱敏 |
| SYSTEM_LOGS | ❌ | ✅¹ | ✅ | ✅ | ¹强制脱敏+路径白名单 |
| AUDIT_LOGS | ❌ | ❌ | ✅ | ✅ | |
| **包管理** |
| PACKAGE_LIST | ✅ | ✅ | ✅ | ✅ | 只读 |
| PACKAGE_UPDATE | ❌ | ❌ | ❌ | ✅² | ²需二次确认 |
| **脚本执行** |
| SCRIPT_LIST | ✅ | ✅ | ✅ | ✅ | 只读 |
| SCRIPT_EXECUTE | ❌ | ❌ | ✅³ | ✅ | ³仅白名单脚本 |
| **配置管理** |
| CONFIG_READ (Public) | ✅ | ✅ | ✅ | ✅ | |
| CONFIG_READ (Sensitive) | ❌ | ✅¹ | ✅ | ✅ | ¹强制脱敏 |
| CONFIG_WRITE | ❌ | ❌ | ✅⁴ | ✅ | ⁴自动备份+语法验证 |

**图例:** ✅允许 ❌禁止 ¹强制脱敏 ²需二次确认 ³仅白名单 ⁴需自动备份

#### 5. 其他安全机制

- **二次确认机制** - 危险操作需要确认令牌 (有效期 5 分钟)
- **维护时间窗口** - 只在指定时间段允许危险操作
- **IP 白名单** - 敏感命令只允许特定 IP 执行
- **紧急绕过** - 需要特殊令牌

---

## 实施路线图

### Phase 1: 日志查询 ✅

**Agent:**
- [x] 新增 `log_ops.rs` 模块
- [x] 实现 journald 日志查询
- [x] 实现 /var/log 日志查询
- [x] 实现日志脱敏 (密码、API 密钥、Token、AWS 凭证等)
- [x] 添加输入验证

**Server:**
- [x] 新增日志查询 REST API (`log_query.go`)
- [x] 更新 gRPC 服务

**SDK:**
- [x] 更新 Proto 并重新生成
- [x] 添加日志命令 (SERVICE_LOGS=70, SYSTEM_LOGS=71, AUDIT_LOGS=72)

### Phase 2: 操作审计 ✅

**Server:**
- [x] 新增 `audit.go` 服务
- [x] 数据库迁移 (audit_logs 表)
- [x] 在日志查询中记录审计日志
- [x] 新增审计日志 REST API

**REST API:**
```
GET /api/audit/logs              # 查询审计日志
GET /api/audit/logs/user/:userId # 查询用户操作
GET /api/audit/logs/agent/:agentId # 查询 Agent 操作
GET /api/audit/stats             # 获取审计统计
GET /api/audit/recent            # 获取最近日志
```

### Phase 3: 脚本执行 ✅

**Agent:**
- [x] 新增 `script_executor.rs` 模块
- [x] 实现脚本目录管理
- [x] 实现脚本执行 (含参数验证)
- [x] 实现脚本签名验证
- [x] 添加危险字符过滤

**配置:**
```yaml
scripts:
  enabled: true
  scripts_dir: /opt/nanolink/scripts
  require_signature: false
  timeout_seconds: 60
```

### Phase 4: 配置管理 ✅

**Agent:**
- [x] 新增 `config_mgr.rs` 模块
- [x] 实现配置读取 (含脱敏)
- [x] 实现配置写入 (带自动备份)
- [x] 实现配置回滚
- [x] 实现备份清理

**配置:**
```yaml
config_management:
  enabled: true
  allowed_configs: [/etc/nginx/nginx.conf]
  backup_on_change: true
  max_backups: 10
```

### Phase 5: 包管理 ✅

**Agent:**
- [x] 新增 `package_mgr.rs` 模块
- [x] 实现多平台包管理器适配 (apt/yum/dnf/pacman/brew/winget/choco)
- [x] 实现包列表/检查更新
- [x] 实现包更新 (高权限)
- [x] 实现系统更新 (需 SYSTEM_ADMIN)

**配置:**
```yaml
package_management:
  enabled: true
  allow_update: false
  allow_system_update: false
```

---

## 附录

### 文件变更清单

| 组件 | 新增文件 | 修改文件 | 状态 |
|------|----------|----------|:----:|
| **Proto** | - | `nanolink.proto` | ✅ 完成 |
| **Agent** | `log_ops.rs`, `package_mgr.rs`, `script_executor.rs`, `config_mgr.rs` | `permission.rs`, `handler.rs`, `mod.rs`, `config.rs` | ✅ 完成 |
| **Server** | `audit.go`, `log_query.go` | `main.go`, `models.go`, `database.go` | ✅ 完成 |
| **SDK** | - | Proto 重新生成 (Go) | ✅ 完成 |

### 已完成变更

| 日期 | 组件 | 变更 |
|------|------|------|
| 2026-01-07 | Server | 新增 `data_request.go` - DataRequest HTTP API |
| 2026-01-07 | Server | `server.go` 新增 `RequestDataFromAgent()` 方法 |
| 2026-01-07 | Docs | 新增 `FEATURE_COMPARISON.md` 功能对比文档 |
| 2026-01-07 | Proto | 升级协议添加 DevOps 命令 (70-111) |
| 2026-01-07 | Agent | 新增 `log_ops.rs` - 日志查询模块 |
| 2026-01-07 | Server | 新增 `log_query.go` - 日志查询 HTTP API |
| 2026-01-07 | Server | 新增 `audit.go` - 操作审计服务 |
| 2026-01-07 | Server | `models.go` 新增 AuditLog 模型 |
| 2026-01-07 | Agent | 新增 `script_executor.rs` - 脚本执行模块 |
| 2026-01-07 | Agent | 新增 `config_mgr.rs` - 配置管理模块 |
| 2026-01-07 | Agent | 新增 `package_mgr.rs` - 包管理模块 |
| 2026-01-07 | Agent | `config.rs` 新增 ScriptsConfig/ConfigManagementConfig/PackageManagementConfig |

---

*文档更新时间: 2026-01-07*
*DevOps 功能升级完成: 2026-01-07*
