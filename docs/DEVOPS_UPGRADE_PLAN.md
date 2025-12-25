# NanoLink DevOps 运维功能升级计划

本文档详细描述了将 NanoLink 从监控平台升级为完整运维操作平台所需的各组件升级内容。

---

## 目录

- [升级概述](#升级概述)
- [Agent 升级计划](#agent-升级计划)
- [SDK 升级计划](#sdk-升级计划)
- [Server 升级计划](#server-升级计划)
- [Proto 协议升级](#proto-协议升级)
- [安全考量](#安全考量)
- [实施路线图](#实施路线图)

---

## 升级概述

### 当前能力

| 功能类别 | 已支持 | 待升级 |
|----------|:------:|:------:|
| 系统监控 | ✅ | - |
| 进程管理 | ✅ | - |
| 服务管理 | ✅ | 扩展日志 |
| Docker 管理 | ✅ | - |
| 文件操作 | ✅ | - |
| Shell 执行 | ✅ | - |
| **日志查询** | ⚠️ | 需扩展 |
| **版本管理** | ❌ | 需新增 |
| **审计日志** | ❌ | 需新增 |
| **配置管理** | ❌ | 需新增 |

### 升级目标

1. **日志查询增强** - 查询 systemd/journald/审计日志
2. **版本管理** - 包更新、Agent 自更新
3. **预定义脚本** - 比 Shell 更安全的运维脚本执行
4. **操作审计** - 完整的操作日志追踪
5. **配置管理** - 远程配置读写

---

## Agent 升级计划

### 新增 Executor 模块

#### 1. `log_ops.rs` - 日志操作模块

```rust
// 新增文件: agent/src/executor/log_ops.rs

pub struct LogExecutor;

impl LogExecutor {
    /// 查询 journald/systemd 日志
    pub async fn get_service_logs(&self, service: &str, lines: u32, since: Option<&str>) -> Result<String>;
    
    /// 查询系统日志 (/var/log)
    pub async fn get_system_logs(&self, log_file: &str, lines: u32, filter: Option<&str>) -> Result<String>;
    
    /// 查询审计日志 (auditd)
    pub async fn get_audit_logs(&self, since: Option<&str>, filter: Option<&str>) -> Result<String>;
    
    /// 实时日志流 (类似 tail -f)
    pub async fn stream_logs(&self, target: &str) -> Result<impl Stream<Item = String>>;
}
```

**需验证的输入:**
- `service` - 必须是有效的 systemd 服务名
- `log_file` - 必须在白名单路径内
- `filter` - 必须过滤危险字符

#### 2. `package_mgr.rs` - 包管理模块

```rust
// 新增文件: agent/src/executor/package_mgr.rs

pub struct PackageExecutor;

impl PackageExecutor {
    /// 列出已安装包
    pub async fn list_packages(&self, filter: Option<&str>) -> Result<Vec<PackageInfo>>;
    
    /// 检查可更新的包
    pub async fn check_updates(&self) -> Result<Vec<UpdateInfo>>;
    
    /// 更新指定包 (危险操作, 需高权限)
    pub async fn update_package(&self, package: &str) -> Result<String>;
    
    /// 更新系统 (危险操作, 需最高权限)
    pub async fn update_system(&self) -> Result<String>;
}
```

**平台适配:**
- Linux: `apt`, `yum`, `dnf`, `pacman`
- macOS: `brew`
- Windows: `winget`, `choco`

#### 3. `script_executor.rs` - 预定义脚本执行

```rust
// 新增文件: agent/src/executor/script_executor.rs

pub struct ScriptExecutor {
    scripts_dir: PathBuf,  // 预定义脚本目录
}

impl ScriptExecutor {
    /// 列出可用脚本
    pub fn list_scripts(&self) -> Result<Vec<ScriptInfo>>;
    
    /// 执行预定义脚本 (比 shell 更安全)
    pub async fn execute_script(&self, script_name: &str, args: &[&str]) -> Result<String>;
    
    /// 验证脚本签名 (可选安全增强)
    pub fn verify_script(&self, script_name: &str) -> Result<bool>;
}
```

**安全设计:**
- 只能执行 `scripts/` 目录下的预定义脚本
- 可选: 脚本签名验证
- 参数白名单验证

#### 4. `config_mgr.rs` - 配置管理模块

```rust
// 新增文件: agent/src/executor/config_mgr.rs

pub struct ConfigExecutor {
    allowed_configs: Vec<PathBuf>,  // 允许操作的配置文件列表
}

impl ConfigExecutor {
    /// 读取配置文件
    pub fn read_config(&self, path: &str) -> Result<String>;
    
    /// 写入配置文件 (需备份)
    pub fn write_config(&self, path: &str, content: &str, backup: bool) -> Result<()>;
    
    /// 验证配置语法
    pub fn validate_config(&self, path: &str, config_type: ConfigType) -> Result<ValidationResult>;
    
    /// 回滚配置
    pub fn rollback_config(&self, path: &str) -> Result<()>;
}
```

### 权限系统升级

```rust
// 修改文件: agent/src/security/permission.rs

pub fn required_level(&self, command_type: CommandType) -> u8 {
    match command_type {
        // 新增 Level 0 (只读)
        CommandType::ServiceLogs => 0,
        CommandType::SystemLogs => 0,
        CommandType::AuditLogs => 0,
        CommandType::PackageList => 0,
        CommandType::PackageCheck => 0,
        CommandType::ScriptList => 0,
        CommandType::ConfigRead => 0,
        
        // 新增 Level 1 (基础写入)
        // ... 暂无新增
        
        // 新增 Level 2 (服务控制)
        CommandType::ScriptExecute => 2,
        CommandType::ConfigWrite => 2,
        
        // 新增 Level 3 (系统管理)
        CommandType::PackageUpdate => 3,
        CommandType::SystemUpdate => 3,
        CommandType::AgentUpdate => 3,
        
        // ... 保留现有权限
    }
}
```

### 输入验证升级

```rust
// 修改文件: agent/src/security/validation.rs

/// 验证日志文件路径
pub fn validate_log_path(path: &str) -> Result<(), String> {
    let allowed_prefixes = ["/var/log/", "/tmp/", "C:\\Windows\\Logs\\"];
    // ...
}

/// 验证包名
pub fn validate_package_name(name: &str) -> Result<(), String> {
    // 只允许字母数字和 -_.
    let pattern = Regex::new(r"^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$").unwrap();
    // ...
}

/// 验证脚本名
pub fn validate_script_name(name: &str) -> Result<(), String> {
    // 禁止路径遍历
    if name.contains("..") || name.contains("/") || name.contains("\\") {
        return Err("Invalid script name".to_string());
    }
    // ...
}
```

### 配置文件升级

```yaml
# 修改文件: agent/config.example.yaml

# 新增日志配置
logs:
  allowed_paths:
    - /var/log/syslog
    - /var/log/messages
    - /var/log/auth.log
  max_lines: 10000
  audit_log_path: /var/log/audit/audit.log

# 新增脚本配置
scripts:
  enabled: true
  scripts_dir: /opt/nanolink/scripts
  allow_custom_args: false
  require_signature: false

# 新增配置管理
config_management:
  enabled: true
  allowed_configs:
    - /etc/nginx/nginx.conf
    - /etc/redis/redis.conf
    - /etc/mysql/my.cnf
  backup_on_change: true
  max_backups: 10

# 新增包管理
package_management:
  enabled: true
  allow_update: false  # 默认禁用, 需显式开启
  package_manager: auto  # auto/apt/yum/dnf/brew
```

---

## SDK 升级计划

### Proto 更新后重新生成

所有 SDK 需要在 Proto 更新后重新生成代码。

### Java SDK

#### 新增 Command 构建器

```java
// 新增文件: sdk/java/src/main/java/com/kkape/sdk/command/LogCommands.java

public class LogCommands {
    public static Command serviceLogs(String serviceName, int lines) {
        return Command.newBuilder()
            .setType(CommandType.SERVICE_LOGS)
            .setTarget(serviceName)
            .putParams("lines", String.valueOf(lines))
            .build();
    }
    
    public static Command systemLogs(String logFile, int lines, String filter) {
        return Command.newBuilder()
            .setType(CommandType.SYSTEM_LOGS)
            .setTarget(logFile)
            .putParams("lines", String.valueOf(lines))
            .putParams("filter", filter)
            .build();
    }
    
    public static Command auditLogs(String since, String filter) {
        return Command.newBuilder()
            .setType(CommandType.AUDIT_LOGS)
            .putParams("since", since)
            .putParams("filter", filter)
            .build();
    }
}
```

```java
// 新增文件: sdk/java/src/main/java/com/kkape/sdk/command/PackageCommands.java

public class PackageCommands {
    public static Command listPackages(String filter) { ... }
    public static Command checkUpdates() { ... }
    public static Command updatePackage(String packageName, String superToken) { ... }
}
```

```java
// 新增文件: sdk/java/src/main/java/com/kkape/sdk/command/ScriptCommands.java

public class ScriptCommands {
    public static Command listScripts() { ... }
    public static Command executeScript(String scriptName, Map<String, String> args) { ... }
}
```

### Go SDK

#### 新增 Command 辅助函数

```go
// 新增文件: sdk/go/nanolink/commands.go

package nanolink

import pb "github.com/chenqi92/NanoLink/sdk/go/nanolink/proto"

// Log Commands
func ServiceLogsCommand(serviceName string, lines int) *pb.Command { ... }
func SystemLogsCommand(logFile string, lines int, filter string) *pb.Command { ... }
func AuditLogsCommand(since, filter string) *pb.Command { ... }

// Package Commands
func ListPackagesCommand(filter string) *pb.Command { ... }
func CheckUpdatesCommand() *pb.Command { ... }
func UpdatePackageCommand(packageName, superToken string) *pb.Command { ... }

// Script Commands
func ListScriptsCommand() *pb.Command { ... }
func ExecuteScriptCommand(scriptName string, args map[string]string) *pb.Command { ... }

// Config Commands
func ReadConfigCommand(path string) *pb.Command { ... }
func WriteConfigCommand(path, content string, backup bool) *pb.Command { ... }
```

### Python SDK

#### 新增 Command 类

```python
# 新增文件: sdk/python/nanolink/commands.py

from dataclasses import dataclass
from typing import Optional, Dict
from .proto.nanolink_pb2 import Command, CommandType

class LogCommands:
    @staticmethod
    def service_logs(service_name: str, lines: int = 100) -> Command: ...
    
    @staticmethod
    def system_logs(log_file: str, lines: int = 100, filter: Optional[str] = None) -> Command: ...
    
    @staticmethod
    def audit_logs(since: Optional[str] = None, filter: Optional[str] = None) -> Command: ...


class PackageCommands:
    @staticmethod
    def list_packages(filter: Optional[str] = None) -> Command: ...
    
    @staticmethod
    def check_updates() -> Command: ...
    
    @staticmethod
    def update_package(package_name: str, super_token: str) -> Command: ...


class ScriptCommands:
    @staticmethod
    def list_scripts() -> Command: ...
    
    @staticmethod
    def execute_script(script_name: str, args: Optional[Dict[str, str]] = None) -> Command: ...
```

---

## Server 升级计划

### 操作审计系统

```go
// 新增文件: apps/server/internal/service/audit.go

package service

type AuditService struct {
    db     *database.DB
    logger *zap.SugaredLogger
}

type AuditLog struct {
    ID          uint64    `json:"id"`
    Timestamp   time.Time `json:"timestamp"`
    UserID      uint      `json:"user_id"`
    Username    string    `json:"username"`
    AgentID     string    `json:"agent_id"`
    AgentHost   string    `json:"agent_hostname"`
    CommandType string    `json:"command_type"`
    Target      string    `json:"target"`
    Params      string    `json:"params"` // JSON
    Success     bool      `json:"success"`
    Error       string    `json:"error,omitempty"`
    Duration    int64     `json:"duration_ms"`
}

func (s *AuditService) LogOperation(ctx context.Context, log AuditLog) error { ... }
func (s *AuditService) QueryLogs(ctx context.Context, filter AuditFilter) ([]AuditLog, error) { ... }
func (s *AuditService) GetUserOperations(ctx context.Context, userID uint, limit int) ([]AuditLog, error) { ... }
func (s *AuditService) GetAgentOperations(ctx context.Context, agentID string, limit int) ([]AuditLog, error) { ... }
```

### 数据库迁移

```sql
-- 新增表: audit_logs
CREATE TABLE audit_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    user_id INTEGER NOT NULL,
    username VARCHAR(255) NOT NULL,
    agent_id VARCHAR(64) NOT NULL,
    agent_hostname VARCHAR(255),
    command_type VARCHAR(50) NOT NULL,
    target VARCHAR(1024),
    params TEXT,
    success BOOLEAN NOT NULL DEFAULT FALSE,
    error TEXT,
    duration_ms INTEGER,
    
    INDEX idx_timestamp (timestamp),
    INDEX idx_user_id (user_id),
    INDEX idx_agent_id (agent_id),
    INDEX idx_command_type (command_type)
);
```

### REST API 扩展

```go
// 修改文件: apps/server/cmd/main.go

// 新增审计日志 API
api.GET("/audit/logs", authMiddleware, h.GetAuditLogs)
api.GET("/audit/logs/user/:userId", authMiddleware, h.GetUserAuditLogs)
api.GET("/audit/logs/agent/:agentId", authMiddleware, h.GetAgentAuditLogs)

// 新增运维操作 API
api.POST("/agents/:id/logs/service", authMiddleware, h.GetServiceLogs)
api.POST("/agents/:id/logs/system", authMiddleware, h.GetSystemLogs)
api.POST("/agents/:id/logs/audit", authMiddleware, h.GetAgentAuditLogs)
api.GET("/agents/:id/packages", authMiddleware, h.GetPackages)
api.POST("/agents/:id/packages/update", authMiddleware, superAdminOnly, h.UpdatePackage)
api.GET("/agents/:id/scripts", authMiddleware, h.GetScripts)
api.POST("/agents/:id/scripts/execute", authMiddleware, h.ExecuteScript)
api.GET("/agents/:id/config", authMiddleware, h.GetConfig)
api.PUT("/agents/:id/config", authMiddleware, h.UpdateConfig)
```

### gRPC 服务扩展

```go
// 修改文件: apps/server/internal/grpc/server.go

// 在 SendCommand 中添加审计日志
func (s *Server) SendCommand(ctx context.Context, req *pb.DashboardCommandRequest) (*pb.CommandResult, error) {
    startTime := time.Now()
    
    // ... 现有逻辑 ...
    
    // 记录审计日志
    s.auditService.LogOperation(ctx, service.AuditLog{
        UserID:      getUserIDFromContext(ctx),
        Username:    getUsernameFromContext(ctx),
        AgentID:     req.AgentId,
        AgentHost:   agent.Hostname,
        CommandType: req.Command.Type.String(),
        Target:      req.Command.Target,
        Params:      jsonEncode(req.Command.Params),
        Success:     result.Success,
        Error:       result.Error,
        Duration:    time.Since(startTime).Milliseconds(),
    })
    
    return result, nil
}
```

### Dashboard 权限细化

```go
// 新增文件: apps/server/internal/service/command_permission.go

type CommandPermissionService struct {
    db *database.DB
}

// 用户对特定 agent 的命令权限
type UserAgentPermission struct {
    UserID          uint
    AgentID         string
    AllowedCommands []CommandType  // 空表示全部允许
    DeniedCommands  []CommandType
    MaxPermLevel    int  // 最高权限级别
}

func (s *CommandPermissionService) CanExecute(userID uint, agentID string, cmdType CommandType) bool { ... }
func (s *CommandPermissionService) SetPermissions(userID uint, agentID string, perms UserAgentPermission) error { ... }
```

---

## Proto 协议升级

### 新增 CommandType

```protobuf
// 修改文件: sdk/protocol/nanolink.proto

enum CommandType {
  COMMAND_TYPE_UNSPECIFIED = 0;
  
  // === 现有命令 (保持不变) ===
  PROCESS_LIST = 1;
  PROCESS_KILL = 2;
  SERVICE_START = 10;
  SERVICE_STOP = 11;
  SERVICE_RESTART = 12;
  SERVICE_STATUS = 13;
  FILE_TAIL = 20;
  FILE_DOWNLOAD = 21;
  FILE_UPLOAD = 22;
  FILE_TRUNCATE = 23;
  DOCKER_LIST = 30;
  DOCKER_START = 31;
  DOCKER_STOP = 32;
  DOCKER_RESTART = 33;
  DOCKER_LOGS = 34;
  SYSTEM_REBOOT = 40;
  SHELL_EXECUTE = 50;
  
  // === 新增日志命令 ===
  SERVICE_LOGS = 60;     // 查询服务日志 (journald)
  SYSTEM_LOGS = 61;      // 查询系统日志 (/var/log)
  AUDIT_LOGS = 62;       // 查询审计日志
  LOG_STREAM = 63;       // 实时日志流
  
  // === 新增包管理命令 ===
  PACKAGE_LIST = 70;     // 列出已安装包
  PACKAGE_CHECK = 71;    // 检查可更新包
  PACKAGE_UPDATE = 72;   // 更新指定包
  SYSTEM_UPDATE = 73;    // 系统全量更新
  AGENT_UPDATE = 74;     // Agent 自更新
  
  // === 新增脚本命令 ===
  SCRIPT_LIST = 80;      // 列出可用脚本
  SCRIPT_EXECUTE = 81;   // 执行预定义脚本
  SCRIPT_UPLOAD = 82;    // 上传新脚本 (管理员)
  
  // === 新增配置命令 ===
  CONFIG_READ = 90;      // 读取配置文件
  CONFIG_WRITE = 91;     // 写入配置文件
  CONFIG_VALIDATE = 92;  // 验证配置语法
  CONFIG_ROLLBACK = 93;  // 回滚配置
  
  // === 新增健康检查命令 ===
  HEALTH_CHECK = 100;    // 自定义健康检查
  CONNECTIVITY_TEST = 101; // 网络连通性测试
}
```

### 新增响应消息

```protobuf
// 新增日志查询响应
message LogQueryResult {
  repeated string lines = 1;
  int64 total_lines = 2;
  string log_source = 3;
  uint64 oldest_timestamp = 4;
  uint64 newest_timestamp = 5;
}

// 新增包信息
message PackageInfo {
  string name = 1;
  string version = 2;
  string description = 3;
  string installed_size = 4;
  string repository = 5;
  bool update_available = 6;
  string new_version = 7;
}

// 新增脚本信息
message ScriptInfo {
  string name = 1;
  string description = 2;
  string category = 3;
  repeated string required_args = 4;
  int32 required_permission = 5;
  uint64 last_modified = 6;
}

// 扩展 CommandResult
message CommandResult {
  // ... 现有字段 ...
  
  // 新增响应类型
  LogQueryResult log_result = 10;
  repeated PackageInfo packages = 11;
  repeated ScriptInfo scripts = 12;
  string config_content = 13;
}
```

---

## 安全考量

### ⚠️ 核心安全风险

在实施运维功能前，必须认识到以下核心风险：

| 功能 | 风险类型 | 风险等级 | 典型场景 |
|------|---------|:--------:|---------|
| 日志查询 | 敏感信息泄露 | 🔴 高 | 日志中包含数据库密码、API 密钥 |
| 配置读取 | 凭证泄露 | 🔴 高 | 配置文件包含明文密码 |
| 配置写入 | 后门植入 | 🔴 高 | 修改 SSH 配置允许未授权访问 |
| 脚本执行 | 命令注入 | 🟠 中 | 参数注入恶意命令 |
| 包管理 | 供应链攻击 | 🟠 中 | 安装被篡改的软件包 |

---

### 1. 日志脱敏系统 (必须实现)

日志中常见的敏感信息：
```
[ERROR] Database: mysql://admin:P@ssw0rd123@localhost/db  # 数据库密码
[DEBUG] Authorization: Bearer eyJhbGciOiJIUzI1NiIs...    # JWT Token
[INFO] AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG...    # 云服务密钥
[ERROR] Redis AUTH failed with password: redis123        # Redis 密码
```

#### 脱敏模块设计

```rust
// 新增文件: agent/src/security/log_sanitizer.rs

use regex::Regex;
use lazy_static::lazy_static;

lazy_static! {
    static ref SENSITIVE_PATTERNS: Vec<(Regex, &'static str)> = vec![
        // 密码模式 (password=xxx, passwd:xxx, pwd = xxx)
        (Regex::new(r"(?i)(password|passwd|pwd)\s*[:=]\s*\S+").unwrap(), "$1=[REDACTED]"),

        // API 密钥模式
        (Regex::new(r"(?i)(api[_-]?key|apikey|secret[_-]?key|access[_-]?key)\s*[:=]\s*\S+").unwrap(), "$1=[REDACTED]"),

        // Bearer Token
        (Regex::new(r"(?i)Bearer\s+[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+").unwrap(), "Bearer [REDACTED]"),

        // 数据库连接字符串 (隐藏密码部分)
        (Regex::new(r"(?i)(mysql|postgres|mongodb|redis|amqp)://([^:]+):([^@]+)@").unwrap(), "$1://$2:[REDACTED]@"),

        // AWS 密钥
        (Regex::new(r"(?i)(AKIA[A-Z0-9]{16})").unwrap(), "[AWS_KEY_REDACTED]"),
        (Regex::new(r"(?i)(aws_secret_access_key\s*=\s*)\S+").unwrap(), "$1[REDACTED]"),

        // 私钥内容
        (Regex::new(r"-----BEGIN\s+(RSA\s+)?PRIVATE KEY-----[\s\S]*?-----END\s+(RSA\s+)?PRIVATE KEY-----").unwrap(), "[PRIVATE_KEY_REDACTED]"),

        // 常见 Token 格式
        (Regex::new(r"(?i)(token|auth|authorization)\s*[:=]\s*\S{20,}").unwrap(), "$1=[REDACTED]"),

        // IP:Port 后的认证信息 (如 Redis)
        (Regex::new(r"(?i)AUTH\s+\S+").unwrap(), "AUTH [REDACTED]"),
    ];
}

pub struct LogSanitizer {
    enabled: bool,
    custom_patterns: Vec<(Regex, String)>,
}

impl LogSanitizer {
    pub fn new(enabled: bool) -> Self {
        Self {
            enabled,
            custom_patterns: Vec::new(),
        }
    }

    /// 添加自定义脱敏规则
    pub fn add_pattern(&mut self, pattern: &str, replacement: &str) -> Result<(), regex::Error> {
        self.custom_patterns.push((Regex::new(pattern)?, replacement.to_string()));
        Ok(())
    }

    /// 对日志内容进行脱敏
    pub fn sanitize(&self, content: &str) -> String {
        if !self.enabled {
            return content.to_string();
        }

        let mut result = content.to_string();

        // 应用内置规则
        for (pattern, replacement) in SENSITIVE_PATTERNS.iter() {
            result = pattern.replace_all(&result, *replacement).to_string();
        }

        // 应用自定义规则
        for (pattern, replacement) in &self.custom_patterns {
            result = pattern.replace_all(&result, replacement.as_str()).to_string();
        }

        result
    }

    /// 检测日志中是否可能包含敏感信息 (用于警告)
    pub fn detect_sensitive(&self, content: &str) -> Vec<String> {
        let mut warnings = Vec::new();
        for (pattern, _) in SENSITIVE_PATTERNS.iter() {
            if pattern.is_match(content) {
                warnings.push(format!("Detected potential sensitive data matching: {}", pattern.as_str()));
            }
        }
        warnings
    }
}
```

#### 日志查询接口更新

```rust
// 修改文件: agent/src/executor/log_ops.rs

pub struct LogExecutor {
    sanitizer: LogSanitizer,
    allowed_paths: Vec<PathBuf>,
    max_lines: u32,
}

impl LogExecutor {
    /// 查询日志 (自动脱敏)
    pub async fn get_logs(
        &self,
        target: &str,
        lines: u32,
        sanitize: bool,  // 是否脱敏，默认 true
    ) -> Result<LogQueryResult> {
        // 1. 验证路径
        self.validate_path(target)?;

        // 2. 读取日志
        let raw_content = self.read_log_file(target, lines).await?;

        // 3. 脱敏处理
        let content = if sanitize {
            self.sanitizer.sanitize(&raw_content)
        } else {
            raw_content
        };

        Ok(LogQueryResult {
            lines: content.lines().map(String::from).collect(),
            sanitized: sanitize,
            ..Default::default()
        })
    }
}
```

---

### 2. 配置文件分级管理

#### 配置敏感度分级

```rust
// 新增文件: agent/src/security/config_policy.rs

use std::path::PathBuf;
use std::collections::HashMap;

/// 配置文件敏感度级别
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ConfigSensitivity {
    /// 公开 - 可直接读取，无需脱敏
    Public,
    /// 敏感 - 可读取但需要脱敏处理
    Sensitive,
    /// 机密 - 禁止通过 API 读取
    Secret,
}

/// 配置文件访问策略
pub struct ConfigPolicy {
    /// 文件路径 -> 敏感度映射
    sensitivity_map: HashMap<PathBuf, ConfigSensitivity>,

    /// 始终禁止访问的文件
    blocked_paths: Vec<PathBuf>,

    /// 敏感内容正则 (用于自动检测)
    sensitive_patterns: Vec<Regex>,
}

impl ConfigPolicy {
    pub fn new() -> Self {
        Self {
            sensitivity_map: Self::default_sensitivity_map(),
            blocked_paths: Self::default_blocked_paths(),
            sensitive_patterns: Self::default_sensitive_patterns(),
        }
    }

    /// 默认禁止访问的路径
    fn default_blocked_paths() -> Vec<PathBuf> {
        vec![
            // 系统凭证
            PathBuf::from("/etc/shadow"),
            PathBuf::from("/etc/gshadow"),
            PathBuf::from("/etc/sudoers.d"),

            // SSH 私钥
            PathBuf::from("/etc/ssh/ssh_host_rsa_key"),
            PathBuf::from("/etc/ssh/ssh_host_ecdsa_key"),
            PathBuf::from("/etc/ssh/ssh_host_ed25519_key"),
            PathBuf::from("/root/.ssh"),

            // SSL/TLS 私钥
            PathBuf::from("/etc/ssl/private"),
            PathBuf::from("/etc/pki/tls/private"),

            // 数据库数据文件
            PathBuf::from("/var/lib/mysql"),
            PathBuf::from("/var/lib/postgresql"),
        ]
    }

    /// 默认敏感度映射
    fn default_sensitivity_map() -> HashMap<PathBuf, ConfigSensitivity> {
        let mut map = HashMap::new();

        // 机密级别 - 包含密码的配置
        map.insert(PathBuf::from("/etc/mysql/debian.cnf"), ConfigSensitivity::Secret);
        map.insert(PathBuf::from("/etc/grafana/grafana.ini"), ConfigSensitivity::Secret);

        // 敏感级别 - 可能包含密码
        map.insert(PathBuf::from("/etc/mysql/my.cnf"), ConfigSensitivity::Sensitive);
        map.insert(PathBuf::from("/etc/redis/redis.conf"), ConfigSensitivity::Sensitive);
        map.insert(PathBuf::from("/etc/postgresql/*/pg_hba.conf"), ConfigSensitivity::Sensitive);

        // 公开级别 - 不包含敏感信息
        map.insert(PathBuf::from("/etc/nginx/nginx.conf"), ConfigSensitivity::Public);
        map.insert(PathBuf::from("/etc/hosts"), ConfigSensitivity::Public);
        map.insert(PathBuf::from("/etc/resolv.conf"), ConfigSensitivity::Public);

        map
    }

    /// 检查文件访问权限
    pub fn check_access(&self, path: &PathBuf, permission_level: u8) -> Result<ConfigSensitivity, String> {
        // 检查是否在禁止列表
        for blocked in &self.blocked_paths {
            if path.starts_with(blocked) {
                return Err(format!("Access denied: {} is in blocked list", path.display()));
            }
        }

        // 获取敏感度级别
        let sensitivity = self.sensitivity_map
            .get(path)
            .copied()
            .unwrap_or(ConfigSensitivity::Sensitive); // 默认为敏感

        // 机密文件需要最高权限
        if sensitivity == ConfigSensitivity::Secret && permission_level < 3 {
            return Err("Secret config requires SYSTEM_ADMIN permission".to_string());
        }

        Ok(sensitivity)
    }
}
```

#### 配置读取脱敏

```rust
// 配置文件内容脱敏
pub struct ConfigSanitizer;

impl ConfigSanitizer {
    /// 对配置文件内容进行脱敏
    pub fn sanitize(content: &str, file_type: ConfigType) -> String {
        match file_type {
            ConfigType::Ini | ConfigType::Conf => Self::sanitize_ini(content),
            ConfigType::Yaml => Self::sanitize_yaml(content),
            ConfigType::Json => Self::sanitize_json(content),
            ConfigType::Env => Self::sanitize_env(content),
            _ => Self::sanitize_generic(content),
        }
    }

    fn sanitize_ini(content: &str) -> String {
        let password_pattern = Regex::new(r"(?im)^(\s*(?:password|passwd|secret|key|token|auth)\s*=\s*)(.+)$").unwrap();
        password_pattern.replace_all(content, "$1[REDACTED]").to_string()
    }

    fn sanitize_env(content: &str) -> String {
        let secret_pattern = Regex::new(r"(?im)^((?:.*(?:PASSWORD|SECRET|KEY|TOKEN|AUTH).*)\s*=\s*)(.+)$").unwrap();
        secret_pattern.replace_all(content, "$1[REDACTED]").to_string()
    }

    // ... 其他格式的脱敏实现
}
```

---

### 3. 脚本执行安全增强

#### 参数验证与沙箱

```rust
// 新增文件: agent/src/security/script_security.rs

use std::collections::HashSet;

/// 危险的 Shell 元字符
const DANGEROUS_CHARS: &[char] = &[
    '|', '&', ';', '$', '`', '(', ')', '{', '}',
    '<', '>', '\n', '\r', '\'', '"', '\\',
];

/// 脚本执行策略
pub struct ScriptPolicy {
    /// 允许的脚本目录
    scripts_dir: PathBuf,

    /// 脚本参数白名单 (脚本名 -> 允许的参数格式)
    allowed_args: HashMap<String, Vec<ArgSpec>>,

    /// 是否启用沙箱
    use_sandbox: bool,

    /// 执行超时 (秒)
    timeout_secs: u64,

    /// 资源限制
    resource_limits: ResourceLimits,
}

/// 参数规格
pub struct ArgSpec {
    name: String,
    pattern: Regex,        // 参数值必须匹配的正则
    required: bool,
    max_length: usize,
}

impl ScriptPolicy {
    /// 验证脚本参数安全性
    pub fn validate_args(&self, script_name: &str, args: &[String]) -> Result<(), String> {
        // 1. 检查危险字符
        for arg in args {
            for &c in DANGEROUS_CHARS {
                if arg.contains(c) {
                    return Err(format!(
                        "Dangerous character '{}' detected in argument",
                        c.escape_default()
                    ));
                }
            }

            // 长度限制
            if arg.len() > 1024 {
                return Err("Argument too long (max 1024 chars)".to_string());
            }
        }

        // 2. 检查白名单规则
        if let Some(allowed) = self.allowed_args.get(script_name) {
            for (i, arg) in args.iter().enumerate() {
                if let Some(spec) = allowed.get(i) {
                    if !spec.pattern.is_match(arg) {
                        return Err(format!(
                            "Argument {} does not match required pattern: {}",
                            spec.name, spec.pattern.as_str()
                        ));
                    }
                }
            }
        }

        Ok(())
    }

    /// 构建沙箱执行命令
    pub fn build_sandboxed_command(&self, script_path: &Path, args: &[String]) -> Command {
        if self.use_sandbox {
            // 使用 firejail 或 bubblewrap 沙箱
            let mut cmd = Command::new("firejail");
            cmd.args(&[
                "--quiet",
                "--private-tmp",
                "--private-dev",
                "--net=none",           // 禁用网络
                "--no3d",
                "--nodvd",
                "--nosound",
                "--notv",
                "--novideo",
                "--x11=none",
                &format!("--timeout={}", self.timeout_secs),
                "--rlimit-as=256m",     // 内存限制
                "--rlimit-cpu=60",      // CPU 时间限制
                "--rlimit-fsize=10m",   // 文件大小限制
                "--rlimit-nproc=10",    // 进程数限制
            ]);
            cmd.arg(script_path);
            cmd.args(args);
            cmd
        } else {
            let mut cmd = Command::new(script_path);
            cmd.args(args);
            cmd
        }
    }
}
```

#### 脚本清单与签名

```rust
/// 脚本清单 (scripts/manifest.json)
#[derive(Serialize, Deserialize)]
pub struct ScriptManifest {
    pub scripts: Vec<ScriptEntry>,
}

#[derive(Serialize, Deserialize)]
pub struct ScriptEntry {
    pub name: String,
    pub description: String,
    pub category: String,
    pub required_permission: u8,
    pub args: Vec<ArgSpec>,
    pub sha256: String,  // 脚本文件 SHA256 校验
}

impl ScriptExecutor {
    /// 验证脚本完整性
    pub fn verify_script(&self, script_name: &str) -> Result<bool, String> {
        let manifest = self.load_manifest()?;

        if let Some(entry) = manifest.scripts.iter().find(|s| s.name == script_name) {
            let script_path = self.scripts_dir.join(&entry.name);
            let actual_hash = sha256_file(&script_path)?;

            if actual_hash != entry.sha256 {
                return Err(format!(
                    "Script integrity check failed: expected {}, got {}",
                    entry.sha256, actual_hash
                ));
            }

            Ok(true)
        } else {
            Err(format!("Script {} not found in manifest", script_name))
        }
    }
}
```

---

### 4. 权限矩阵 (更新版)

| 命令类型 | Level 0 | Level 1 | Level 2 | Level 3 | 额外要求 |
|----------|:-------:|:-------:|:-------:|:-------:|---------|
| **日志查询** |
| SERVICE_LOGS | ✅¹ | ✅¹ | ✅ | ✅ | ¹ 强制脱敏 |
| SYSTEM_LOGS | ❌ | ✅¹ | ✅ | ✅ | ¹ 强制脱敏 + 路径白名单 |
| AUDIT_LOGS | ❌ | ❌ | ✅ | ✅ | 敏感操作 |
| LOG_STREAM | ❌ | ❌ | ✅ | ✅ | 实时流需审批 |
| **包管理** |
| PACKAGE_LIST | ✅ | ✅ | ✅ | ✅ | 只读 |
| PACKAGE_CHECK | ✅ | ✅ | ✅ | ✅ | 只读 |
| PACKAGE_UPDATE | ❌ | ❌ | ❌ | ✅² | ² 需二次确认 |
| SYSTEM_UPDATE | ❌ | ❌ | ❌ | ✅² | ² 需二次确认 + 维护窗口 |
| **脚本执行** |
| SCRIPT_LIST | ✅ | ✅ | ✅ | ✅ | 只读 |
| SCRIPT_EXECUTE | ❌ | ❌ | ✅³ | ✅ | ³ 仅白名单脚本 |
| SCRIPT_UPLOAD | ❌ | ❌ | ❌ | ✅ | 需签名验证 |
| **配置管理** |
| CONFIG_READ (Public) | ✅ | ✅ | ✅ | ✅ | 无敏感信息 |
| CONFIG_READ (Sensitive) | ❌ | ✅¹ | ✅ | ✅ | ¹ 强制脱敏 |
| CONFIG_READ (Secret) | ❌ | ❌ | ❌ | ✅ | 需审计日志 |
| CONFIG_WRITE | ❌ | ❌ | ✅⁴ | ✅ | ⁴ 自动备份 + 语法验证 |
| CONFIG_ROLLBACK | ❌ | ❌ | ✅ | ✅ | |
| **系统管理** |
| AGENT_UPDATE | ❌ | ❌ | ❌ | ✅² | ² 需二次确认 |
| SYSTEM_REBOOT | ❌ | ❌ | ❌ | ✅² | ² 需二次确认 + 维护窗口 |

**图例说明：**
- ✅ 允许
- ❌ 禁止
- ¹ 强制脱敏
- ² 需要二次确认
- ³ 仅限白名单
- ⁴ 需要自动备份

---

### 5. 安全增强机制

#### 5.1 二次确认机制

```rust
// 新增文件: agent/src/security/confirmation.rs

/// 需要二次确认的命令类型
const REQUIRE_CONFIRMATION: &[CommandType] = &[
    CommandType::PackageUpdate,
    CommandType::SystemUpdate,
    CommandType::AgentUpdate,
    CommandType::SystemReboot,
    CommandType::ConfigWrite,
];

/// 确认令牌
pub struct ConfirmationToken {
    pub token: String,
    pub command_type: CommandType,
    pub target: String,
    pub expires_at: DateTime<Utc>,
    pub user_id: String,
}

impl ConfirmationService {
    /// 生成确认令牌 (有效期 5 分钟)
    pub fn generate_token(&self, cmd: &Command, user_id: &str) -> ConfirmationToken {
        ConfirmationToken {
            token: generate_secure_token(32),
            command_type: cmd.command_type,
            target: cmd.target.clone(),
            expires_at: Utc::now() + Duration::minutes(5),
            user_id: user_id.to_string(),
        }
    }

    /// 验证确认令牌
    pub fn verify_token(&self, token: &str, cmd: &Command) -> Result<(), String> {
        // 验证令牌有效性、匹配性、过期时间
    }
}
```

#### 5.2 操作时间窗口

```yaml
# 配置文件: agent/config.yaml

security:
  # 维护时间窗口 (只在此时间段允许危险操作)
  maintenance_windows:
    - day_of_week: [1, 2, 3, 4, 5]  # 周一到周五
      start_time: "02:00"
      end_time: "06:00"
      timezone: "Asia/Shanghai"

  # 紧急操作绕过 (需要特殊令牌)
  emergency_bypass:
    enabled: true
    token_env: "NANOLINK_EMERGENCY_TOKEN"
```

#### 5.3 IP 白名单

```rust
/// IP 白名单检查
pub struct IpWhitelist {
    allowed_ips: Vec<IpNetwork>,
    allowed_for_commands: HashSet<CommandType>,
}

impl IpWhitelist {
    pub fn check(&self, client_ip: &IpAddr, command_type: CommandType) -> bool {
        // 如果命令不在受限列表，放行
        if !self.allowed_for_commands.contains(&command_type) {
            return true;
        }

        // 检查 IP 是否在白名单
        self.allowed_ips.iter().any(|net| net.contains(*client_ip))
    }
}
```

#### 5.4 敏感文件检测

```rust
/// 检测配置文件中的敏感信息
pub fn detect_sensitive_content(content: &str) -> Vec<SensitiveMatch> {
    let mut matches = Vec::new();

    // 检测私钥
    if content.contains("-----BEGIN") && content.contains("PRIVATE KEY-----") {
        matches.push(SensitiveMatch {
            type_: "PRIVATE_KEY",
            severity: Severity::Critical,
            line: find_line_number(content, "PRIVATE KEY"),
        });
    }

    // 检测硬编码密码
    let password_pattern = Regex::new(r"(?i)(password|passwd|pwd)\s*[:=]\s*['\"]?([^'\"\\s]{8,})").unwrap();
    for cap in password_pattern.captures_iter(content) {
        matches.push(SensitiveMatch {
            type_: "HARDCODED_PASSWORD",
            severity: Severity::High,
            line: find_line_number(content, cap.get(0).unwrap().as_str()),
        });
    }

    matches
}
```

---

### 6. 安全配置模板

```yaml
# agent/config.security.yaml - 安全配置模板

# 日志查询安全配置
log_security:
  # 是否启用脱敏 (强烈建议开启)
  sanitize_enabled: true

  # 自定义脱敏规则
  custom_patterns:
    - pattern: "(?i)my_company_secret_\\w+"
      replacement: "[COMPANY_SECRET]"

  # 允许查询的日志路径
  allowed_paths:
    - /var/log/syslog
    - /var/log/messages
    - /var/log/nginx/access.log
    - /var/log/nginx/error.log

  # 禁止查询的日志 (即使在 allowed_paths 中)
  blocked_paths:
    - /var/log/auth.log     # 包含认证信息
    - /var/log/secure       # 包含认证信息

# 配置管理安全配置
config_security:
  # 配置分级
  classifications:
    secret:  # 禁止 API 读取
      - /etc/mysql/debian.cnf
      - /etc/shadow
    sensitive:  # 需要脱敏
      - /etc/mysql/my.cnf
      - /etc/redis/redis.conf
    public:  # 可直接读取
      - /etc/nginx/nginx.conf
      - /etc/hosts

  # 写入配置时自动备份
  auto_backup: true
  max_backups: 10

  # 写入前语法验证
  validate_before_write: true

# 脚本执行安全配置
script_security:
  # 启用沙箱
  sandbox_enabled: true
  sandbox_type: firejail  # firejail / bubblewrap / none

  # 执行超时
  timeout_secs: 300

  # 资源限制
  limits:
    max_memory_mb: 256
    max_cpu_seconds: 60
    max_file_size_mb: 10
    max_processes: 10

  # 需要验证脚本签名
  require_signature: false

# 包管理安全配置
package_security:
  # 是否允许包更新 (默认禁用)
  allow_update: false

  # 允许更新的包白名单
  update_whitelist:
    - nginx
    - redis-server

  # 禁止更新的包
  update_blacklist:
    - openssh-server
    - sudo
    - kernel*
```

---

## 实施路线图

### Phase 1: 日志查询 (2-3 周)

**Agent:**
- [ ] 新增 `log_ops.rs` 模块
- [ ] 实现 journald 日志查询
- [ ] 实现 /var/log 日志查询
- [ ] 实现审计日志查询 (Linux auditd)
- [ ] 添加输入验证

**Server:**
- [ ] 新增日志查询 REST API
- [ ] 更新 gRPC 服务

**SDK:**
- [ ] 更新 Proto 并重新生成
- [ ] 添加日志命令辅助函数

### Phase 2: 操作审计 (1-2 周)

**Server:**
- [ ] 新增 `audit.go` 服务
- [ ] 数据库迁移 (audit_logs 表)
- [ ] 在 SendCommand 中记录审计日志
- [ ] 新增审计日志 REST API

**Dashboard:**
- [ ] 审计日志查询界面
- [ ] 操作历史面板

### Phase 3: 脚本执行 (2 周)

**Agent:**
- [ ] 新增 `script_executor.rs` 模块
- [ ] 实现脚本目录管理
- [ ] 实现脚本执行 (含参数验证)
- [ ] 可选: 脚本签名验证

**Server/SDK:**
- [ ] 更新 Proto
- [ ] 添加脚本命令 API

### Phase 4: 配置管理 (1-2 周)

**Agent:**
- [ ] 新增 `config_mgr.rs` 模块
- [ ] 实现配置读取
- [ ] 实现配置写入 (带备份)
- [ ] 实现配置回滚

### Phase 5: 包管理 (2 周)

**Agent:**
- [ ] 新增 `package_mgr.rs` 模块
- [ ] 实现多平台包管理器适配
- [ ] 实现包列表/检查更新
- [ ] 实现包更新 (高权限)

---

## 附录

### 文件变更清单

| 组件 | 新增文件 | 修改文件 |
|------|----------|----------|
| **Proto** | - | `nanolink.proto` |
| **Agent** | `log_ops.rs`, `package_mgr.rs`, `script_executor.rs`, `config_mgr.rs` | `permission.rs`, `validation.rs`, `handler.rs`, `mod.rs` |
| **Server** | `audit.go`, `command_permission.go` | `server.go`, `handler.go`, `main.go` |
| **Java SDK** | `LogCommands.java`, `PackageCommands.java`, `ScriptCommands.java` | 重新生成 Proto |
| **Go SDK** | `commands.go` | 重新生成 Proto |
| **Python SDK** | `commands.py` | 重新生成 Proto |
