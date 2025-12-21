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

### 权限矩阵

| 命令类型 | Level 0 | Level 1 | Level 2 | Level 3 |
|----------|:-------:|:-------:|:-------:|:-------:|
| SERVICE_LOGS | ✅ | ✅ | ✅ | ✅ |
| SYSTEM_LOGS | ✅ | ✅ | ✅ | ✅ |
| AUDIT_LOGS | ✅ | ✅ | ✅ | ✅ |
| PACKAGE_LIST | ✅ | ✅ | ✅ | ✅ |
| PACKAGE_CHECK | ✅ | ✅ | ✅ | ✅ |
| SCRIPT_LIST | ✅ | ✅ | ✅ | ✅ |
| CONFIG_READ | ✅ | ✅ | ✅ | ✅ |
| SCRIPT_EXECUTE | ❌ | ❌ | ✅ | ✅ |
| CONFIG_WRITE | ❌ | ❌ | ✅ | ✅ |
| PACKAGE_UPDATE | ❌ | ❌ | ❌ | ✅ |
| SYSTEM_UPDATE | ❌ | ❌ | ❌ | ✅ |
| AGENT_UPDATE | ❌ | ❌ | ❌ | ✅ |

### 安全增强建议

1. **双重确认机制**
   - 危险操作 (PACKAGE_UPDATE, SYSTEM_UPDATE, CONFIG_WRITE) 需要二次确认
   - 可配置短信/邮件验证码确认

2. **操作时间窗口**
   - 可配置允许执行危险操作的时间窗口
   - 如: 只允许工作日 9:00-18:00 执行

3. **IP 白名单**
   - Dashboard 用户可绑定 IP 白名单
   - 从非白名单 IP 执行危险操作需要额外验证

4. **操作回退**
   - CONFIG_WRITE 自动备份
   - 支持一键回滚最近 N 次配置变更

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
