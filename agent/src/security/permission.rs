use std::path::{Component, Path};
use std::sync::{Arc, OnceLock};

use glob::Pattern;
use regex::Regex;
use subtle::ConstantTimeEq;
use tracing::warn;

use crate::config::Config;
use crate::proto::CommandType;

/// Remote queries that are safe for the NAS read-only runtime. Keep this list
/// deliberately narrower than permission level 0: filesystem/log/config reads
/// and arbitrary connectivity probes can still expose sensitive NAS data.
pub(crate) fn remote_read_only_allows(command_type: CommandType) -> bool {
    matches!(
        command_type,
        CommandType::ProcessList
            | CommandType::ServiceStatus
            | CommandType::ServiceList
            | CommandType::DockerList
            | CommandType::AgentGetVersion
            | CommandType::PackageList
    )
}

/// 常量时间字符串比较，防止时序攻击
fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    a.ct_eq(b).into()
}

/// Permission checker for commands
pub struct PermissionChecker {
    config: Arc<Config>,
}

impl PermissionChecker {
    /// Create a new permission checker
    pub fn new(config: Arc<Config>) -> Self {
        Self { config }
    }

    /// Check if a command type is allowed at the given permission level
    pub fn check_permission(&self, command_type: CommandType, permission_level: u8) -> bool {
        let required = self.required_level(command_type);
        permission_level >= required
    }

    /// Get the required permission level for a command type
    pub fn required_level(&self, command_type: CommandType) -> u8 {
        match command_type {
            // Read-only operations (level 0)
            CommandType::ProcessList => 0,
            CommandType::ServiceStatus => 0,
            CommandType::ServiceList => 0,
            CommandType::DockerList => 0,
            CommandType::FileTail => 0,
            CommandType::FileList => 0,

            // Basic write operations (level 1)
            CommandType::FileDownload => 1,
            CommandType::FileTruncate => 1,
            CommandType::DockerLogs => 1,

            // Service control operations (level 2)
            CommandType::ProcessKill => 2,
            CommandType::ServiceStart => 2,
            CommandType::ServiceStop => 2,
            CommandType::ServiceRestart => 2,
            CommandType::DockerStart => 2,
            CommandType::DockerStop => 2,
            CommandType::DockerRestart => 2,

            // System admin operations (level 3)
            CommandType::SystemReboot => 3,
            CommandType::ShellExecute => 3,
            CommandType::FileUpload => 3,

            // Agent update operations (level 3 - SYSTEM_ADMIN required)
            CommandType::AgentCheckUpdate => 3,
            CommandType::AgentDownloadUpdate => 3,
            CommandType::AgentApplyUpdate => 3,
            CommandType::AgentGetVersion => 0, // Version info is read-only

            // Log query commands (level 0-2 with sanitization)
            CommandType::ServiceLogs => 0, // All levels can query, but output is sanitized
            CommandType::SystemLogs => 1,  // Requires BASIC_WRITE, path whitelist enforced
            CommandType::AuditLogs => 2,   // Requires SERVICE_CONTROL
            CommandType::LogStream => 1,   // Realtime log stream

            // Package management commands
            CommandType::PackageList => 0, // Read-only, all levels
            CommandType::PackageCheckUpdates => 0, // Read-only, all levels
            CommandType::PackageUpdate => 3, // SYSTEM_ADMIN only
            CommandType::PackageInstall => 3, // SYSTEM_ADMIN only
            CommandType::SystemUpdate => 3, // SYSTEM_ADMIN only

            // Script execution commands
            CommandType::ScriptList => 0,    // Read-only, all levels
            CommandType::ScriptExecute => 2, // SERVICE_CONTROL for whitelisted scripts
            CommandType::ScriptUpload => 3,  // SYSTEM_ADMIN only

            // Config management commands
            CommandType::ConfigRead => 0, // All levels can read (with sanitization)
            CommandType::ConfigWrite => 2, // SERVICE_CONTROL with auto-backup
            CommandType::ConfigValidate => 0, // All levels can validate
            CommandType::ConfigRollback => 2, // SERVICE_CONTROL
            CommandType::ConfigListBackups => 0, // Read-only

            // Health check commands
            CommandType::HealthCheck => 0,      // All levels
            CommandType::ConnectivityTest => 0, // All levels

            // Application deployment is a privileged filesystem + service action.
            CommandType::DeployExecute
            | CommandType::DeployRollback
            | CommandType::BuildExecute
            | CommandType::BuildCancel
            | CommandType::BuildGitStatus => 3,

            // Unknown commands require highest level
            _ => 3,
        }
    }

    /// Check if a shell command is allowed (P0-2 增强版本)
    pub fn check_shell_command(&self, command: &str, super_token: &str) -> Result<(), String> {
        // Check if shell is enabled
        if !self.config.shell.enabled {
            return Err("Shell commands are disabled".to_string());
        }

        // Validate super token using constant-time comparison
        let valid_token = self
            .config
            .shell
            .super_token
            .as_ref()
            .map(|t| constant_time_eq(t.as_bytes(), super_token.as_bytes()))
            .unwrap_or(false);

        if !valid_token {
            return Err("Invalid super token".to_string());
        }

        // P0-2: 规范化命令字符串
        let normalized = Self::normalize_command(command);

        // P0-2: 检测危险模式 (正则表达式)
        if let Some(pattern) = Self::contains_dangerous_pattern(&normalized) {
            warn!("[SECURITY] Dangerous shell pattern detected: {}", pattern);
            return Err(format!(
                "Command blocked: dangerous pattern detected ({pattern})"
            ));
        }

        // P0-2: 检测命令注入。A single read-only pipeline is handled by the
        // structured validator below; all other shell control syntax is denied.
        if Self::detect_command_injection(command) {
            warn!("[SECURITY] Shell command injection pattern detected");
            return Err("Command blocked: potential command injection detected".to_string());
        }

        let safe_readonly = self.config.shell.readonly_profile
            && if command.contains('|') {
                self.is_safe_readonly_pipeline(command)
            } else {
                self.is_safe_readonly_command(command)
            };

        if command.contains('|') && !safe_readonly {
            return Err(
                "Command blocked: only validated read-only pipelines are allowed".to_string(),
            );
        }

        // Check blacklist (both original and normalized). A legacy literal `|`
        // blacklist entry may coexist with the structured read-only profile;
        // it is skipped only after the entire pipeline has validated.
        for pattern in &self.config.shell.blacklist {
            if pattern == "|" && safe_readonly && command.contains('|') {
                continue;
            }
            if command.contains(pattern) || normalized.contains(pattern) {
                return Err(format!("Command contains blacklisted pattern: {pattern}"));
            }
        }

        // Check whitelist (if not empty, command must match at least one pattern)
        if !self.config.shell.whitelist.is_empty() {
            let matched = self
                .config
                .shell
                .whitelist
                .iter()
                .any(|p| Self::matches_pattern(&p.pattern, command));

            if !matched && !safe_readonly {
                return Err("Command not in whitelist".to_string());
            }
        } else if self.config.shell.readonly_profile && !safe_readonly {
            return Err("Command is outside the built-in read-only profile".to_string());
        }

        Ok(())
    }

    /// Validate a requested per-session working directory. Root is allowed only
    /// as the root itself; it never implicitly grants every descendant.
    pub fn check_shell_cwd(&self, cwd: &str) -> Result<(), String> {
        let canonical = Path::new(cwd)
            .canonicalize()
            .map_err(|_| "Working directory does not exist".to_string())?;
        if !canonical.is_dir() {
            return Err("Working directory is not a directory".to_string());
        }
        let allowed = &self.config.shell.allowed_working_directories;
        let matched = if allowed.is_empty() {
            canonical == Path::new("/")
        } else {
            allowed.iter().any(|root| {
                let root_path = Path::new(root);
                let normalized = root_path
                    .canonicalize()
                    .unwrap_or_else(|_| root_path.to_path_buf());
                if normalized == Path::new("/") {
                    canonical == normalized
                } else {
                    canonical.starts_with(normalized)
                }
            })
        };
        if matched {
            Ok(())
        } else {
            Err("Working directory is outside the allowed roots".to_string())
        }
    }

    fn is_safe_readonly_pipeline(&self, command: &str) -> bool {
        let parts: Vec<&str> = command.split('|').map(str::trim).collect();
        if !(2..=3).contains(&parts.len()) || parts.iter().any(|part| part.is_empty()) {
            return false;
        }
        if !self.is_safe_readonly_command(parts[0]) {
            return false;
        }
        parts[1..]
            .iter()
            .all(|part| Self::is_safe_pipeline_filter(part))
    }

    fn is_safe_readonly_command(&self, command: &str) -> bool {
        let Some(tokens) = shlex::split(command) else {
            return false;
        };
        if tokens.is_empty() || tokens[0].contains('/') {
            return false;
        }

        let normalized = tokens.join(" ");
        const EXACT: &[&str] = &[
            "pwd",
            "whoami",
            "id",
            "uname -a",
            "hostname",
            "hostname -f",
            "hostnamectl",
            "uptime",
            "date",
            "timedatectl",
            "who",
            "w",
            "users",
            "last -n 20",
            "df -h",
            "df -hT",
            "free -h",
            "free -m",
            "vmstat",
            "vmstat 1 5",
            "lsblk",
            "lsblk -f",
            "findmnt",
            "mount",
            "ps -ef",
            "ps aux",
            "pstree -ap",
            "top -b -n 1",
            "ss -s",
            "ss -lntp",
            "ss -lntup",
            "netstat -s",
            "netstat -lntp",
            "netstat -lntup",
            "ip addr show",
            "ip link show",
            "ip route show",
            "ip neigh show",
            "lscpu",
            "ipcs -a",
            "getenforce",
            "sestatus",
            "ulimit -a",
            "firewall-cmd --state",
            "firewall-cmd --list-all",
            "jps -lv",
            "jcmd -l",
            "rpm -qa",
            "systemctl list-units --type=service --all --no-pager",
            "systemctl list-unit-files --type=service --no-pager",
        ];
        if EXACT.contains(&normalized.as_str()) {
            return true;
        }

        match tokens[0].as_str() {
            "ls" => self.validate_ls(&tokens[1..]),
            "cat" => self.validate_file_args(&tokens[1..], false),
            "head" | "tail" => self.validate_head_tail(&tokens[1..]),
            "stat" => self.validate_file_args(&tokens[1..], false),
            "du" => self.validate_du(&tokens[1..]),
            "grep" => self.validate_grep_files(&tokens[1..]),
            "find" => self.validate_find(&tokens[1..]),
            "file" | "readlink" | "realpath" | "md5sum" | "sha256sum" => {
                self.validate_path_utility(tokens[0].as_str(), &tokens[1..])
            }
            "wc" => self.validate_wc_files(&tokens[1..]),
            "which" | "whereis" => Self::validate_binary_lookup(&tokens[1..]),
            "pgrep" => Self::validate_pgrep(&tokens[1..]),
            "sysctl" => Self::validate_sysctl_read(&tokens[1..]),
            "systemctl" => Self::validate_systemctl_read(&tokens[1..]),
            "journalctl" => Self::validate_journalctl_read(&tokens[1..]),
            "rpm" => Self::validate_rpm_read(&tokens[1..]),
            "yum" => Self::validate_yum_read(&tokens[1..]),
            _ => false,
        }
    }

    fn validate_ls(&self, args: &[String]) -> bool {
        let mut paths = 0usize;
        for arg in args {
            if let Some(flags) = arg.strip_prefix('-') {
                if arg == "--" || !flags.chars().all(|c| "alhtrS1dA".contains(c)) {
                    return false;
                }
            } else {
                paths += 1;
                if !self.is_allowed_read_path(arg, true) {
                    return false;
                }
            }
        }
        paths <= 8
    }

    fn validate_file_args(&self, args: &[String], allow_options: bool) -> bool {
        if args.is_empty() || args.len() > 8 {
            return false;
        }
        args.iter().all(|arg| {
            (allow_options && arg.starts_with('-')) || self.is_allowed_read_path(arg, false)
        })
    }

    fn validate_head_tail(&self, args: &[String]) -> bool {
        if args.is_empty() {
            return false;
        }
        let mut index = 0usize;
        if args.get(index).is_some_and(|arg| arg == "-n") {
            let Some(lines) = args
                .get(index + 1)
                .and_then(|value| value.parse::<u32>().ok())
            else {
                return false;
            };
            if lines > 5000 {
                return false;
            }
            index += 2;
        } else if let Some(value) = args.get(index).and_then(|arg| arg.strip_prefix('-')) {
            if value.is_empty() || value.parse::<u32>().ok().is_none_or(|lines| lines > 5000) {
                return false;
            }
            index += 1;
        }
        self.validate_file_args(&args[index..], false)
    }

    fn validate_du(&self, args: &[String]) -> bool {
        let mut paths = 0usize;
        for arg in args {
            if arg.starts_with('-') {
                let ok = matches!(arg.as_str(), "-h" | "-s" | "-sh" | "-ah")
                    || arg
                        .strip_prefix("--max-depth=")
                        .and_then(|v| v.parse::<u8>().ok())
                        .is_some_and(|v| v <= 5);
                if !ok {
                    return false;
                }
            } else {
                paths += 1;
                if !self.is_allowed_read_path(arg, false) {
                    return false;
                }
            }
        }
        paths == 1
    }

    fn validate_grep_files(&self, args: &[String]) -> bool {
        let mut positional = Vec::new();
        for arg in args {
            if arg.starts_with('-') {
                if !matches!(arg.as_str(), "-i" | "-v" | "-E" | "-F" | "-n" | "-w" | "-x") {
                    return false;
                }
            } else {
                positional.push(arg);
            }
        }
        if positional.len() < 2 || !Self::safe_filter_pattern(positional[0]) {
            return false;
        }
        positional[1..]
            .iter()
            .all(|path| self.is_allowed_read_path(path, false))
    }

    fn validate_find(&self, args: &[String]) -> bool {
        if args.is_empty() || !self.is_allowed_read_path(&args[0], false) {
            return false;
        }
        const DENIED: &[&str] = &[
            "-exec", "-execdir", "-ok", "-okdir", "-delete", "-fls", "-fprint", "-fprintf",
        ];
        !args[1..].iter().any(|arg| {
            DENIED.contains(&arg.as_str())
                || arg
                    .chars()
                    .any(|c| matches!(c, ';' | '&' | '|' | '<' | '>' | '$' | '`'))
        })
    }

    fn validate_path_utility(&self, command: &str, args: &[String]) -> bool {
        let paths = if command == "readlink" && args.first().is_some_and(|arg| arg == "-f") {
            &args[1..]
        } else {
            args
        };
        self.validate_file_args(paths, false)
    }

    fn validate_wc_files(&self, args: &[String]) -> bool {
        let paths: Vec<String> = args
            .iter()
            .filter(|arg| !arg.starts_with('-'))
            .cloned()
            .collect();
        args.iter()
            .all(|arg| !arg.starts_with('-') || matches!(arg.as_str(), "-l" | "-w" | "-c" | "-m"))
            && self.validate_file_args(&paths, false)
    }

    fn validate_binary_lookup(args: &[String]) -> bool {
        !args.is_empty()
            && args.len() <= 8
            && args.iter().all(|arg| {
                !arg.starts_with('-')
                    && arg.len() <= 128
                    && arg
                        .chars()
                        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '.' | '+'))
            })
    }

    fn validate_pgrep(args: &[String]) -> bool {
        if args.len() != 2 || !matches!(args[0].as_str(), "-af" | "-fl") {
            return false;
        }
        Self::safe_filter_pattern(&args[1])
    }

    fn validate_sysctl_read(args: &[String]) -> bool {
        matches!(args, [arg] if arg == "-a")
            || (!args.is_empty()
                && args.len() <= 8
                && args.iter().all(|arg| {
                    !arg.starts_with('-')
                        && !arg.contains('=')
                        && arg
                            .chars()
                            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '-'))
                }))
    }

    fn validate_systemctl_read(args: &[String]) -> bool {
        if args.is_empty() {
            return false;
        }
        let action = args[0].as_str();
        if !matches!(
            action,
            "status" | "is-active" | "is-enabled" | "show" | "cat"
        ) {
            return false;
        }
        let units: Vec<&String> = args[1..]
            .iter()
            .filter(|arg| arg.as_str() != "--no-pager")
            .collect();
        !units.is_empty() && units.len() <= 8 && units.iter().all(|unit| Self::safe_unit_name(unit))
    }

    fn validate_journalctl_read(args: &[String]) -> bool {
        if args.is_empty()
            || args.iter().any(|arg| {
                arg.starts_with("--vacuum")
                    || matches!(arg.as_str(), "--rotate" | "--flush" | "--sync")
            })
        {
            return false;
        }
        let mut has_limit = false;
        let mut index = 0usize;
        while index < args.len() {
            match args[index].as_str() {
                "-n" | "--lines" => {
                    let Some(lines) = args.get(index + 1).and_then(|v| v.parse::<u32>().ok())
                    else {
                        return false;
                    };
                    if lines > 5000 {
                        return false;
                    }
                    has_limit = true;
                    index += 2;
                }
                "-u" | "--unit" => {
                    if args
                        .get(index + 1)
                        .is_none_or(|unit| !Self::safe_unit_name(unit))
                    {
                        return false;
                    }
                    index += 2;
                }
                "-p" | "--priority" => {
                    if args
                        .get(index + 1)
                        .is_none_or(|v| !v.chars().all(|c| c.is_ascii_alphanumeric() || c == '.'))
                    {
                        return false;
                    }
                    index += 2;
                }
                "--no-pager" | "-r" | "--reverse" | "-b" => index += 1,
                value if value.starts_with("--since=") || value.starts_with("--until=") => {
                    if value
                        .chars()
                        .any(|c| matches!(c, '$' | '`' | ';' | '|' | '&'))
                    {
                        return false;
                    }
                    index += 1;
                }
                _ => return false,
            }
        }
        has_limit
    }

    fn validate_rpm_read(args: &[String]) -> bool {
        matches!(args, [arg] if arg == "-qa")
            || matches!(args, [flag, package] if matches!(flag.as_str(), "-qi" | "-ql") && Self::safe_package_name(package))
    }

    fn validate_yum_read(args: &[String]) -> bool {
        matches!(args, [a, b] if a == "list" && b == "installed")
            || matches!(args, [a, package] if a == "info" && Self::safe_package_name(package))
    }

    fn is_safe_pipeline_filter(command: &str) -> bool {
        let Some(tokens) = shlex::split(command) else {
            return false;
        };
        if tokens.is_empty() || tokens[0].contains('/') {
            return false;
        }
        match tokens[0].as_str() {
            "grep" => {
                let mut pattern = None;
                for arg in &tokens[1..] {
                    if arg.starts_with('-') {
                        if !matches!(arg.as_str(), "-i" | "-v" | "-E" | "-F" | "-n" | "-w" | "-x") {
                            return false;
                        }
                    } else if pattern.replace(arg).is_some() {
                        return false;
                    }
                }
                pattern.is_some_and(|value| Self::safe_filter_pattern(value))
            }
            "head" | "tail" => {
                matches!(tokens.as_slice(), [_, flag, value] if flag == "-n" && value.parse::<u32>().is_ok_and(|v| v <= 5000))
                    || matches!(tokens.as_slice(), [_, flag] if flag.strip_prefix('-').and_then(|v| v.parse::<u32>().ok()).is_some_and(|v| v <= 5000))
            }
            "sort" => {
                tokens.len() == 1
                    || matches!(tokens.as_slice(), [_, flag] if matches!(flag.as_str(), "-n" | "-r" | "-nr" | "-rn"))
            }
            "uniq" => {
                tokens.len() == 1
                    || matches!(tokens.as_slice(), [_, flag] if matches!(flag.as_str(), "-c" | "-d" | "-u"))
            }
            "wc" => {
                tokens.len() == 1
                    || matches!(tokens.as_slice(), [_, flag] if matches!(flag.as_str(), "-l" | "-w" | "-c"))
            }
            "cut" => {
                tokens.len() >= 2
                    && tokens[1..].iter().all(|arg| {
                        (arg.starts_with("-d") || arg.starts_with("-f") || arg.starts_with("-c"))
                            && !arg
                                .chars()
                                .any(|c| matches!(c, '/' | '$' | '`' | ';' | '|' | '&'))
                    })
            }
            _ => false,
        }
    }

    fn safe_filter_pattern(value: &str) -> bool {
        !value.is_empty()
            && value.len() <= 128
            && value.chars().all(|c| {
                c.is_alphanumeric() || matches!(c, '_' | '-' | '.' | ':' | '/' | '@' | '+')
            })
    }

    fn safe_unit_name(value: &str) -> bool {
        !value.is_empty()
            && value.len() <= 128
            && value
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '.' | '@'))
    }

    fn safe_package_name(value: &str) -> bool {
        !value.is_empty()
            && value.len() <= 128
            && value
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '.' | '+' | ':'))
    }

    fn is_allowed_read_path(&self, value: &str, allow_root: bool) -> bool {
        if value.is_empty()
            || value
                .chars()
                .any(|c| matches!(c, '*' | '?' | '[' | ']' | '{' | '}'))
        {
            return false;
        }
        let path = Path::new(value);
        if path
            .components()
            .any(|component| component == Component::ParentDir)
        {
            return false;
        }
        let Ok(canonical) = path.canonicalize() else {
            return false;
        };
        if allow_root && canonical == Path::new("/") {
            return true;
        }
        let canonical_str = canonical.to_string_lossy();
        if self.config.security.denied_paths.iter().any(|rule| {
            if rule.chars().any(|c| matches!(c, '*' | '?' | '[' | ']')) {
                Pattern::new(rule).is_ok_and(|pattern| pattern.matches(&canonical_str))
            } else {
                let denied = Path::new(rule)
                    .canonicalize()
                    .unwrap_or_else(|_| Path::new(rule).to_path_buf());
                canonical.starts_with(denied)
            }
        }) {
            return false;
        }
        self.config.security.allowed_paths.iter().any(|rule| {
            let allowed = Path::new(rule)
                .canonicalize()
                .unwrap_or_else(|_| Path::new(rule).to_path_buf());
            canonical.starts_with(allowed)
        })
    }

    /// 规范化命令字符串，移除可能用于绕过检测的字符
    fn normalize_command(command: &str) -> String {
        command
            .replace(['\\', '\'', '"'], "") // 移除反斜杠、单引号、双引号
            .split_whitespace() // 规范化空格
            .collect::<Vec<_>>()
            .join(" ")
    }

    /// 使用正则表达式检测危险模式，返回匹配的模式名称
    fn contains_dangerous_pattern(command: &str) -> Option<&'static str> {
        static DANGEROUS_PATTERNS: OnceLock<Vec<(Regex, &'static str)>> = OnceLock::new();

        let patterns = DANGEROUS_PATTERNS.get_or_init(|| {
            vec![
                // 破坏性命令
                (
                    Regex::new(r"\brm\s+(-[rfv]+\s+)*[/\*]").expect("BUG: invalid regex literal"),
                    "rm with root/wildcard",
                ),
                (
                    Regex::new(r"\bmkfs\b").expect("BUG: invalid regex literal"),
                    "mkfs",
                ),
                (
                    Regex::new(r"\bdd\s+if=").expect("BUG: invalid regex literal"),
                    "dd",
                ),
                (
                    Regex::new(r">\s*/dev/(sd|hd|nvme|vd)").expect("BUG: invalid regex literal"),
                    "write to device",
                ),
                // 权限提升
                (
                    Regex::new(r"\bchmod\s+[0-7]*777").expect("BUG: invalid regex literal"),
                    "chmod 777",
                ),
                (
                    Regex::new(r"\bchown\s+root").expect("BUG: invalid regex literal"),
                    "chown root",
                ),
                // 网络后门/反向shell
                (
                    Regex::new(r"\bnc\s+-[el]").expect("BUG: invalid regex literal"),
                    "netcat listener/exec",
                ),
                (
                    Regex::new(r"\bbash\s+-i\s+>&").expect("BUG: invalid regex literal"),
                    "bash reverse shell",
                ),
                (
                    Regex::new(r"/dev/tcp/").expect("BUG: invalid regex literal"),
                    "bash network redirection",
                ),
                (
                    Regex::new(r"python.*-c.*socket").expect("BUG: invalid regex literal"),
                    "python socket",
                ),
                (
                    Regex::new(r"perl.*-e.*socket").expect("BUG: invalid regex literal"),
                    "perl socket",
                ),
                // 敏感文件访问
                (
                    Regex::new(r"\bcat\s+.*/(etc/(shadow|sudoers)|\.ssh/)")
                        .expect("BUG: invalid regex literal"),
                    "sensitive file read",
                ),
                // Fork炸弹和相关
                (
                    Regex::new(r":\s*\(\s*\)\s*\{").expect("BUG: invalid regex literal"),
                    "fork bomb pattern",
                ),
                (
                    Regex::new(r"\bwhile\s+true\s*;?\s*do").expect("BUG: invalid regex literal"),
                    "infinite loop",
                ),
                (
                    Regex::new(r"\bfor\s*\(\s*;\s*;\s*\)").expect("BUG: invalid regex literal"),
                    "infinite for loop",
                ),
            ]
        });

        for (regex, name) in patterns.iter() {
            if regex.is_match(command) {
                return Some(name);
            }
        }
        None
    }

    /// 检测命令注入尝试
    ///
    /// This denylist is defense in depth for unrestricted L3 shells. Nodes using
    /// `readonly_profile` are additionally constrained by the structured command
    /// grammar above, which rejects shell control syntax before execution.
    fn detect_command_injection(command: &str) -> bool {
        // The shell executor uses `sh -c`, so every shell control operator must
        // be rejected before whitelist matching. A prefix/wildcard allowlist
        // such as `ps *` must never turn `ps -ef; <second command>` into an
        // implicit second-command execution primitive.
        if command.contains("||")
            || command
                .chars()
                .any(|c| matches!(c, ';' | '&' | '<' | '>' | '$' | '`' | '\n' | '\r' | '\0'))
        {
            return true;
        }

        // 命令替换 $(...) 或 `...`
        if command.contains("$(") || command.contains('`') {
            return true;
        }

        // 管道到危险解释器
        if command.contains('|') {
            let parts: Vec<&str> = command.split('|').collect();
            for part in parts.iter().skip(1) {
                let trimmed = part.trim();
                if trimmed.starts_with("sh")
                    || trimmed.starts_with("bash")
                    || trimmed.starts_with("python")
                    || trimmed.starts_with("perl")
                    || trimmed.starts_with("ruby")
                    || trimmed.starts_with("node")
                    || trimmed.starts_with("php")
                {
                    return true;
                }
            }
        }

        // base64编码执行
        if command.contains("base64")
            && (command.contains("-d") || command.contains("--decode"))
            && command.contains('|')
        {
            return true;
        }

        // eval执行
        if command.contains("eval ") || command.contains("eval\t") {
            return true;
        }

        false
    }

    /// Check if a command matches a pattern (supports * wildcard)
    fn matches_pattern(pattern: &str, command: &str) -> bool {
        // Simple wildcard matching
        if pattern == "*" {
            return true;
        }

        let parts: Vec<&str> = pattern.split('*').collect();

        if parts.len() == 1 {
            // No wildcard
            return pattern == command;
        }

        let mut pos = 0;
        for (i, part) in parts.iter().enumerate() {
            if part.is_empty() {
                continue;
            }

            if i == 0 {
                // Must start with first part
                if !command.starts_with(part) {
                    return false;
                }
                pos = part.len();
            } else if i == parts.len() - 1 {
                // Must end with last part
                if !command.ends_with(part) {
                    return false;
                }
            } else {
                // Must contain middle parts
                if let Some(found_pos) = command[pos..].find(part) {
                    pos += found_pos + part.len();
                } else {
                    return false;
                }
            }
        }

        true
    }

    /// Check if a command requires confirmation
    #[allow(dead_code)]
    pub fn requires_confirmation(&self, command: &str) -> bool {
        self.config
            .shell
            .require_confirmation
            .iter()
            .any(|p| Self::matches_pattern(&p.pattern, command))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;
    use std::sync::Arc;

    #[test]
    fn test_pattern_matching() {
        // Exact match
        assert!(PermissionChecker::matches_pattern("df -h", "df -h"));
        assert!(!PermissionChecker::matches_pattern("df -h", "df -m"));

        // Wildcard at end
        assert!(PermissionChecker::matches_pattern(
            "tail -n *",
            "tail -n 100"
        ));
        assert!(PermissionChecker::matches_pattern(
            "tail -n *",
            "tail -n 50"
        ));

        // Wildcard in middle
        assert!(PermissionChecker::matches_pattern(
            "tail -n * /var/log/*.log",
            "tail -n 100 /var/log/app.log"
        ));

        // Wildcard everywhere
        assert!(PermissionChecker::matches_pattern("*", "anything"));
    }

    #[test]
    fn shell_control_operators_are_always_treated_as_injection() {
        for command in [
            "ps -ef; id",
            "ps -ef && id",
            "ps -ef || id",
            "df -h > /tmp/out",
            "cat < /etc/passwd",
            "ps -ef\nid",
            "ps -ef\rid",
            "echo $PATH",
            "echo `id`",
        ] {
            assert!(
                PermissionChecker::detect_command_injection(command),
                "control operator was not blocked: {command:?}"
            );
        }

        // A pipe is not accepted by itself; it is delegated to the structured
        // read-only pipeline validator in check_shell_command.
        assert!(!PermissionChecker::detect_command_injection(
            "ps -ef | grep java"
        ));

        for command in ["ls", "ls -lah /data", "ps -ef", "df -hT", "pwd"] {
            assert!(
                !PermissionChecker::detect_command_injection(command),
                "read-only command was incorrectly blocked: {command:?}"
            );
        }
    }

    #[test]
    fn read_only_level_includes_listing_commands() {
        let checker = PermissionChecker::new(Arc::new(Config::sample()));

        assert!(checker.check_permission(CommandType::ServiceList, 0));
        assert!(checker.check_permission(CommandType::FileList, 0));
    }

    #[test]
    fn readonly_profile_allows_diagnostics_but_rejects_pipeline_escape() {
        let checker = PermissionChecker::new(Arc::new(Config::sample()));
        let token = "super_secret_token";

        for command in [
            "ps -ef",
            "ps -ef | grep java",
            "ps -ef | grep java | grep -v grep",
            "df -hT",
            "ss -lntp",
            "systemctl status nginx --no-pager",
            "journalctl -n 200 -u nginx --no-pager",
            "which java nginx",
            "sysctl net.ipv4.ip_forward",
        ] {
            assert!(
                checker.check_shell_command(command, token).is_ok(),
                "expected read-only command to be allowed: {command}"
            );
        }

        for command in [
            "ps -ef | xargs kill",
            "ps -ef | sh",
            "ps -ef | grep java > /tmp/pids",
            "ps -ef; id",
            "cat",
            "env",
            "curl http://127.0.0.1",
            "sysctl -w net.ipv4.ip_forward=1",
            "journalctl --vacuum-time=1s -n 20",
        ] {
            assert!(
                checker.check_shell_command(command, token).is_err(),
                "expected command to be blocked: {command}"
            );
        }
    }

    #[test]
    fn readonly_file_commands_remain_bounded_by_allowed_paths() {
        let mut config = Config::sample();
        let root = std::env::temp_dir().join(format!(
            "nanolink-readonly-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("clock")
                .as_nanos()
        ));
        std::fs::create_dir_all(&root).expect("create test dir");
        let file = root.join("app.log");
        std::fs::write(&file, "hello").expect("write test file");
        config.security.allowed_paths = vec![root.to_string_lossy().to_string()];
        config.security.denied_paths = Vec::new();
        let checker = PermissionChecker::new(Arc::new(config));
        let safe_path = file.to_string_lossy().replace('\\', "/");

        assert!(
            checker
                .check_shell_command(&format!("cat {safe_path}"), "super_secret_token")
                .is_ok()
        );
        assert!(
            checker
                .check_shell_command("cat /etc/passwd", "super_secret_token")
                .is_err()
        );
        let _ = std::fs::remove_dir_all(root);
    }
}
