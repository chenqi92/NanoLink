//! Internationalization (i18n) module for NanoLink Agent
//!
//! Provides bilingual support (English/Chinese) with automatic language detection.

use serde::{Deserialize, Serialize};
use sys_locale::get_locale;

/// Supported languages
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Lang {
    #[default]
    En,
    Zh,
}

impl Lang {
    /// Convert from string (for config loading)
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "en" | "english" => Some(Lang::En),
            "zh" | "chinese" | "zh-cn" | "zh-tw" => Some(Lang::Zh),
            _ => None,
        }
    }

    /// Convert to string (for config saving)
    pub fn as_str(&self) -> &'static str {
        match self {
            Lang::En => "en",
            Lang::Zh => "zh",
        }
    }
}

/// Detect system language and return the appropriate Lang variant
pub fn detect_language() -> Lang {
    get_locale()
        .map(|locale| {
            let locale_lower = locale.to_lowercase();
            if locale_lower.starts_with("zh") {
                Lang::Zh
            } else {
                Lang::En
            }
        })
        .unwrap_or(Lang::En)
}

/// Get translated string for the given key and language
pub fn t(key: &str, lang: Lang) -> &'static str {
    match (key, lang) {
        // Main menu
        ("menu.title", Lang::Zh) => "NanoLink Agent",
        ("menu.title", Lang::En) => "NanoLink Agent",
        ("menu.select_action", Lang::Zh) => "请选择操作",
        ("menu.select_action", Lang::En) => "Select an action",
        ("menu.start_agent", Lang::Zh) => "启动 Agent",
        ("menu.start_agent", Lang::En) => "Start Agent",
        ("menu.manage_servers", Lang::Zh) => "管理服务器",
        ("menu.manage_servers", Lang::En) => "Manage Servers",
        ("menu.view_status", Lang::Zh) => "查看状态",
        ("menu.view_status", Lang::En) => "View Status",
        ("menu.init_config", Lang::Zh) => "初始化配置",
        ("menu.init_config", Lang::En) => "Initialize Config",
        ("menu.exit", Lang::Zh) => "退出",
        ("menu.exit", Lang::En) => "Exit",
        ("menu.switch_language", Lang::Zh) => "切换语言 / Switch Language",
        ("menu.switch_language", Lang::En) => "Switch Language / 切换语言",
        ("menu.current_language", Lang::Zh) => "当前语言",
        ("menu.current_language", Lang::En) => "Current language",
        ("menu.select_language", Lang::Zh) => "选择语言",
        ("menu.select_language", Lang::En) => "Select language",
        ("menu.language_switched", Lang::Zh) => "语言已切换",
        ("menu.language_switched", Lang::En) => "Language switched",
        ("lang.english", Lang::Zh) => "English (英语)",
        ("lang.english", Lang::En) => "English",
        ("lang.chinese", Lang::Zh) => "中文",
        ("lang.chinese", Lang::En) => "Chinese (中文)",

        // Server management
        ("server.configured_servers", Lang::Zh) => "已配置的服务器",
        ("server.configured_servers", Lang::En) => "Configured Servers",
        ("server.add_new", Lang::Zh) => "+ 添加新服务器",
        ("server.add_new", Lang::En) => "+ Add New Server",
        ("server.back_to_menu", Lang::Zh) => "← 返回主菜单",
        ("server.back_to_menu", Lang::En) => "← Back to Main Menu",
        ("server.no_servers", Lang::Zh) => "暂无配置的服务器",
        ("server.no_servers", Lang::En) => "No servers configured",

        // Server actions
        ("server.select_action", Lang::Zh) => "选择操作",
        ("server.select_action", Lang::En) => "Select action",
        ("server.update_config", Lang::Zh) => "更新配置",
        ("server.update_config", Lang::En) => "Update Config",
        ("server.delete", Lang::Zh) => "删除服务器",
        ("server.delete", Lang::En) => "Delete Server",
        ("server.test_connection", Lang::Zh) => "测试连接",
        ("server.test_connection", Lang::En) => "Test Connection",
        ("server.back", Lang::Zh) => "返回",
        ("server.back", Lang::En) => "Back",

        // Add server prompts
        ("server.enter_address", Lang::Zh) => "服务器地址 (host:port)",
        ("server.enter_address", Lang::En) => "Server address (host:port)",
        ("server.enter_token", Lang::Zh) => "认证 Token",
        ("server.enter_token", Lang::En) => "Authentication Token",
        ("server.select_permission", Lang::Zh) => "权限级别",
        ("server.select_permission", Lang::En) => "Permission Level",
        ("server.enable_tls", Lang::Zh) => "启用 TLS 加密?",
        ("server.enable_tls", Lang::En) => "Enable TLS encryption?",
        ("server.verify_tls", Lang::Zh) => "验证 TLS 证书?",
        ("server.verify_tls", Lang::En) => "Verify TLS certificate?",

        // Permission levels
        ("permission.read_only", Lang::Zh) => "只读 (0) - 仅查看指标",
        ("permission.read_only", Lang::En) => "READ_ONLY (0) - View metrics only",
        ("permission.basic_write", Lang::Zh) => "基本写入 (1) - 基本操作",
        ("permission.basic_write", Lang::En) => "BASIC_WRITE (1) - Basic operations",
        ("permission.service_control", Lang::Zh) => "服务控制 (2) - 管理服务",
        ("permission.service_control", Lang::En) => "SERVICE_CONTROL (2) - Manage services",
        ("permission.system_admin", Lang::Zh) => "系统管理 (3) - 完全控制",
        ("permission.system_admin", Lang::En) => "SYSTEM_ADMIN (3) - Full control",

        // Status messages
        ("status.testing_connection", Lang::Zh) => "正在测试连接...",
        ("status.testing_connection", Lang::En) => "Testing connection...",
        ("status.connection_success", Lang::Zh) => "连接成功！",
        ("status.connection_success", Lang::En) => "Connection successful!",
        ("status.connection_failed", Lang::Zh) => "连接失败",
        ("status.connection_failed", Lang::En) => "Connection failed",
        ("status.server_version", Lang::Zh) => "服务器版本",
        ("status.server_version", Lang::En) => "Server version",
        ("status.server_added", Lang::Zh) => "服务器添加成功！",
        ("status.server_added", Lang::En) => "Server added successfully!",
        ("status.server_updated", Lang::Zh) => "服务器配置已更新！",
        ("status.server_updated", Lang::En) => "Server configuration updated!",
        ("status.server_deleted", Lang::Zh) => "服务器已删除！",
        ("status.server_deleted", Lang::En) => "Server deleted!",
        ("status.config_saved", Lang::Zh) => "配置已保存",
        ("status.config_saved", Lang::En) => "Configuration saved",

        // Server update prompts
        ("server.current_config", Lang::Zh) => "当前配置:",
        ("server.current_config", Lang::En) => "Current configuration:",
        ("server.update_host", Lang::Zh) => "修改服务器地址?",
        ("server.update_host", Lang::En) => "Update server address?",
        ("server.new_host", Lang::Zh) => "新地址 (host:port)",
        ("server.new_host", Lang::En) => "New address (host:port)",
        ("server.update_token", Lang::Zh) => "修改 Token?",
        ("server.update_token", Lang::En) => "Update Token?",
        ("server.new_token", Lang::Zh) => "新 Token",
        ("server.new_token", Lang::En) => "New Token",
        ("server.update_permission", Lang::Zh) => "修改权限级别?",
        ("server.update_permission", Lang::En) => "Update permission level?",
        ("server.permission_level", Lang::Zh) => "选择权限级别",
        ("server.permission_level", Lang::En) => "Select permission level",
        ("server.update_tls", Lang::Zh) => "修改 TLS 设置?",
        ("server.update_tls", Lang::En) => "Update TLS settings?",

        // Confirmations
        ("confirm.delete_server", Lang::Zh) => "确定要删除这个服务器吗?",
        ("confirm.delete_server", Lang::En) => "Are you sure you want to delete this server?",
        ("confirm.yes", Lang::Zh) => "是",
        ("confirm.yes", Lang::En) => "Yes",
        ("confirm.no", Lang::Zh) => "否",
        ("confirm.no", Lang::En) => "No",

        // Errors
        ("error.no_config", Lang::Zh) => "未找到配置文件，请先初始化配置",
        ("error.no_config", Lang::En) => "No configuration file found, please initialize first",
        ("error.invalid_address", Lang::Zh) => "无效的服务器地址",
        ("error.invalid_address", Lang::En) => "Invalid server address",
        ("error.save_failed", Lang::Zh) => "保存配置失败",
        ("error.save_failed", Lang::En) => "Failed to save configuration",

        // Init config
        ("init.output_path", Lang::Zh) => "配置文件输出路径",
        ("init.output_path", Lang::En) => "Configuration file output path",
        ("init.use_toml", Lang::Zh) => "使用 TOML 格式?",
        ("init.use_toml", Lang::En) => "Use TOML format?",
        ("init.success", Lang::Zh) => "配置文件已创建",
        ("init.success", Lang::En) => "Configuration file created",

        // Misc
        ("misc.press_enter", Lang::Zh) => "按 Enter 键继续...",
        ("misc.press_enter", Lang::En) => "Press Enter to continue...",

        // Update menu
        ("menu.check_update", Lang::Zh) => "检查更新",
        ("menu.check_update", Lang::En) => "Check for Updates",
        ("update.checking", Lang::Zh) => "正在检查更新...",
        ("update.checking", Lang::En) => "Checking for updates...",
        ("update.up_to_date", Lang::Zh) => "已是最新版本",
        ("update.up_to_date", Lang::En) => "Already up to date",
        ("update.new_version", Lang::Zh) => "发现新版本",
        ("update.new_version", Lang::En) => "New version available",
        ("update.current_version", Lang::Zh) => "当前版本",
        ("update.current_version", Lang::En) => "Current version",
        ("update.latest_version", Lang::Zh) => "最新版本",
        ("update.latest_version", Lang::En) => "Latest version",
        ("update.download_prompt", Lang::Zh) => "是否下载更新?",
        ("update.download_prompt", Lang::En) => "Download update?",
        ("update.downloading", Lang::Zh) => "正在下载...",
        ("update.downloading", Lang::En) => "Downloading...",
        ("update.download_success", Lang::Zh) => "下载完成",
        ("update.download_success", Lang::En) => "Download complete",
        ("update.apply_prompt", Lang::Zh) => "是否应用更新?",
        ("update.apply_prompt", Lang::En) => "Apply update?",
        ("update.applying", Lang::Zh) => "正在应用更新...",
        ("update.applying", Lang::En) => "Applying update...",
        ("update.success", Lang::Zh) => "更新成功！",
        ("update.success", Lang::En) => "Update successful!",
        ("update.restart_required", Lang::Zh) => "需要重启 Agent 以完成更新",
        ("update.restart_required", Lang::En) => "Agent restart required to complete update",
        ("update.restart_prompt", Lang::Zh) => "是否立即重启 Agent?",
        ("update.restart_prompt", Lang::En) => "Restart Agent now?",
        ("update.check_failed", Lang::Zh) => "检查更新失败",
        ("update.check_failed", Lang::En) => "Failed to check for updates",
        ("update.download_failed", Lang::Zh) => "下载更新失败",
        ("update.download_failed", Lang::En) => "Failed to download update",
        ("update.apply_failed", Lang::Zh) => "应用更新失败",
        ("update.apply_failed", Lang::En) => "Failed to apply update",
        ("update.source", Lang::Zh) => "更新源",
        ("update.source", Lang::En) => "Update source",
        ("update.select_source", Lang::Zh) => "选择下载源",
        ("update.select_source", Lang::En) => "Select download source",
        ("update.changelog", Lang::Zh) => "更新日志",
        ("update.changelog", Lang::En) => "Changelog",

        // Config change restart
        ("config.restart_prompt", Lang::Zh) => "配置已更新，是否立即重启 Agent?",
        ("config.restart_prompt", Lang::En) => "Configuration updated. Restart Agent now?",
        ("config.restarting", Lang::Zh) => "正在重启 Agent...",
        ("config.restarting", Lang::En) => "Restarting Agent...",
        ("config.restart_success", Lang::Zh) => "Agent 已重启",
        ("config.restart_success", Lang::En) => "Agent restarted",
        ("config.restart_manual", Lang::Zh) => "请手动重启 Agent 以应用更改",
        ("config.restart_manual", Lang::En) => "Please restart Agent manually to apply changes",
        ("config.restart_failed", Lang::Zh) => "重启失败",
        ("config.restart_failed", Lang::En) => "Restart failed",

        // New menu items
        ("menu.modify_config", Lang::Zh) => "修改配置",
        ("menu.modify_config", Lang::En) => "Modify Config",
        ("menu.test_all_connections", Lang::Zh) => "测试所有连接",
        ("menu.test_all_connections", Lang::En) => "Test All Connections",
        ("menu.realtime_metrics", Lang::Zh) => "查看实时指标",
        ("menu.realtime_metrics", Lang::En) => "View Real-time Metrics",
        ("menu.install_service", Lang::Zh) => "安装为系统服务",
        ("menu.install_service", Lang::En) => "Install as Service",
        ("menu.diagnostics", Lang::Zh) => "系统诊断",
        ("menu.diagnostics", Lang::En) => "System Diagnostics",
        ("menu.view_logs", Lang::Zh) => "查看日志",
        ("menu.view_logs", Lang::En) => "View Logs",
        ("menu.export_config", Lang::Zh) => "导出配置",
        ("menu.export_config", Lang::En) => "Export Config",
        ("menu.separator", Lang::Zh) => "──────────────",
        ("menu.separator", Lang::En) => "──────────────",

        // Modify config
        ("config.title", Lang::Zh) => "修改配置",
        ("config.title", Lang::En) => "Modify Configuration",
        ("config.realtime_interval", Lang::Zh) => "实时采集频率 (毫秒)",
        ("config.realtime_interval", Lang::En) => "Realtime interval (ms)",
        ("config.buffer_capacity", Lang::Zh) => "缓冲区容量",
        ("config.buffer_capacity", Lang::En) => "Buffer capacity",
        ("config.data_compensation", Lang::Zh) => "数据补偿发送",
        ("config.data_compensation", Lang::En) => "Data Compensation",
        ("config.data_compensation_prompt", Lang::Zh) => "启用断线重连后补发缓冲数据",
        ("config.data_compensation_prompt", Lang::En) => {
            "Enable resending buffered data after reconnection"
        }
        ("config.data_compensation_info", Lang::Zh) => {
            "提示: 重连后将自动发送断线期间缓存的指标数据"
        }
        ("config.data_compensation_info", Lang::En) => {
            "Note: Buffered metrics during disconnection will be automatically resent after reconnection"
        }
        ("common.enabled", Lang::Zh) => "已启用",
        ("common.enabled", Lang::En) => "Enabled",
        ("common.disabled", Lang::Zh) => "已禁用",
        ("common.disabled", Lang::En) => "Disabled",
        ("config.management_enabled", Lang::Zh) => "启用管理 API",
        ("config.management_enabled", Lang::En) => "Enable Management API",
        ("config.management_port", Lang::Zh) => "管理 API 端口",
        ("config.management_port", Lang::En) => "Management API port",
        ("config.management_token", Lang::Zh) => "管理 API Token",
        ("config.management_token", Lang::En) => "Management API Token",
        ("config.select_option", Lang::Zh) => "选择要修改的配置项",
        ("config.select_option", Lang::En) => "Select configuration to modify",
        ("config.current_value", Lang::Zh) => "当前值",
        ("config.current_value", Lang::En) => "Current value",
        ("config.new_value", Lang::Zh) => "新值",
        ("config.new_value", Lang::En) => "New value",
        ("config.saved", Lang::Zh) => "配置已保存",
        ("config.saved", Lang::En) => "Configuration saved",
        ("config.heartbeat_interval", Lang::Zh) => "心跳间隔 (秒)",
        ("config.heartbeat_interval", Lang::En) => "Heartbeat interval (seconds)",
        ("config.log_level", Lang::Zh) => "日志级别",
        ("config.log_level", Lang::En) => "Log level",

        // Test connections
        ("test.title", Lang::Zh) => "测试所有连接",
        ("test.title", Lang::En) => "Test All Connections",
        ("test.testing", Lang::Zh) => "正在测试",
        ("test.testing", Lang::En) => "Testing",
        ("test.success", Lang::Zh) => "连接成功",
        ("test.success", Lang::En) => "Connection successful",
        ("test.failed", Lang::Zh) => "连接失败",
        ("test.failed", Lang::En) => "Connection failed",
        ("test.summary", Lang::Zh) => "测试完成",
        ("test.summary", Lang::En) => "Test complete",
        ("test.passed", Lang::Zh) => "通过",
        ("test.passed", Lang::En) => "passed",

        // Realtime metrics
        ("metrics.title", Lang::Zh) => "实时系统指标",
        ("metrics.title", Lang::En) => "Real-time System Metrics",
        ("metrics.cpu_overview", Lang::Zh) => "CPU 概览",
        ("metrics.cpu_overview", Lang::En) => "CPU Overview",
        ("metrics.cpu_cores", Lang::Zh) => "CPU 各核心",
        ("metrics.cpu_cores", Lang::En) => "CPU Cores",
        ("metrics.memory", Lang::Zh) => "内存",
        ("metrics.memory", Lang::En) => "Memory",
        ("metrics.disk_io", Lang::Zh) => "磁盘 I/O",
        ("metrics.disk_io", Lang::En) => "Disk I/O",
        ("metrics.network", Lang::Zh) => "网络",
        ("metrics.network", Lang::En) => "Network",
        ("metrics.gpu", Lang::Zh) => "GPU",
        ("metrics.gpu", Lang::En) => "GPU",
        ("metrics.processes", Lang::Zh) => "进程列表",
        ("metrics.processes", Lang::En) => "Processes",
        ("metrics.ports", Lang::Zh) => "端口监听",
        ("metrics.ports", Lang::En) => "Listening Ports",
        ("metrics.press_q", Lang::Zh) => "按 q 返回, 方向键切换",
        ("metrics.press_q", Lang::En) => "Press q to return, arrow keys to navigate",
        ("metrics.refreshing", Lang::Zh) => "刷新中...",
        ("metrics.refreshing", Lang::En) => "Refreshing...",
        ("metrics.no_gpu", Lang::Zh) => "未检测到 GPU",
        ("metrics.no_gpu", Lang::En) => "No GPU detected",
        ("metrics.usage", Lang::Zh) => "使用率",
        ("metrics.usage", Lang::En) => "Usage",
        ("metrics.temperature", Lang::Zh) => "温度",
        ("metrics.temperature", Lang::En) => "Temperature",
        ("metrics.power", Lang::Zh) => "功耗",
        ("metrics.power", Lang::En) => "Power",
        ("metrics.logical_cores", Lang::Zh) => "逻辑核心",
        ("metrics.logical_cores", Lang::En) => "Logical Cores",
        ("metrics.load_average", Lang::Zh) => "平均负载",
        ("metrics.load_average", Lang::En) => "Load Average",
        ("metrics.core", Lang::Zh) => "核心",
        ("metrics.core", Lang::En) => "Core",
        ("metrics.progress", Lang::Zh) => "进度",
        ("metrics.progress", Lang::En) => "Progress",
        ("metrics.scroll_hint", Lang::Zh) => "↑↓ 滚动",
        ("metrics.scroll_hint", Lang::En) => "↑↓ to scroll",
        ("metrics.total", Lang::Zh) => "总计",
        ("metrics.total", Lang::En) => "Total",
        ("metrics.ram", Lang::Zh) => "内存",
        ("metrics.ram", Lang::En) => "RAM",
        ("metrics.used", Lang::Zh) => "已用",
        ("metrics.used", Lang::En) => "Used",
        ("metrics.swap", Lang::Zh) => "交换空间",
        ("metrics.swap", Lang::En) => "Swap",
        ("metrics.mount", Lang::Zh) => "挂载点",
        ("metrics.mount", Lang::En) => "Mount",
        ("metrics.filesystem", Lang::Zh) => "文件系统",
        ("metrics.filesystem", Lang::En) => "File System",
        ("metrics.disk_storage", Lang::Zh) => "磁盘存储",
        ("metrics.disk_storage", Lang::En) => "Disk Storage",
        ("metrics.interface", Lang::Zh) => "接口",
        ("metrics.interface", Lang::En) => "Interface",
        ("metrics.received", Lang::Zh) => "接收",
        ("metrics.received", Lang::En) => "Received",
        ("metrics.transmitted", Lang::Zh) => "发送",
        ("metrics.transmitted", Lang::En) => "Transmitted",
        ("metrics.network_interfaces", Lang::Zh) => "网络接口",
        ("metrics.network_interfaces", Lang::En) => "Network Interfaces",
        ("metrics.gpu_information", Lang::Zh) => "GPU 信息",
        ("metrics.gpu_information", Lang::En) => "GPU Information",
        ("metrics.memory_percent", Lang::Zh) => "内存%",
        ("metrics.memory_percent", Lang::En) => "MEM%",
        ("metrics.memory_mb", Lang::Zh) => "内存(MB)",
        ("metrics.memory_mb", Lang::En) => "MEM(MB)",
        ("metrics.name", Lang::Zh) => "名称",
        ("metrics.name", Lang::En) => "Name",
        ("metrics.protocol", Lang::Zh) => "协议",
        ("metrics.protocol", Lang::En) => "Protocol",
        ("metrics.address", Lang::Zh) => "地址",
        ("metrics.address", Lang::En) => "Address",
        ("metrics.process", Lang::Zh) => "进程",
        ("metrics.process", Lang::En) => "Process",

        // Install service
        ("service.title", Lang::Zh) => "安装为系统服务",
        ("service.title", Lang::En) => "Install as System Service",
        ("service.install", Lang::Zh) => "安装服务",
        ("service.install", Lang::En) => "Install Service",
        ("service.uninstall", Lang::Zh) => "卸载服务",
        ("service.uninstall", Lang::En) => "Uninstall Service",
        ("service.start", Lang::Zh) => "启动服务",
        ("service.start", Lang::En) => "Start Service",
        ("service.stop", Lang::Zh) => "停止服务",
        ("service.stop", Lang::En) => "Stop Service",
        ("service.status", Lang::Zh) => "查看服务状态",
        ("service.status", Lang::En) => "View Service Status",
        ("service.installing", Lang::Zh) => "正在安装服务...",
        ("service.installing", Lang::En) => "Installing service...",
        ("service.installed", Lang::Zh) => "服务安装成功",
        ("service.installed", Lang::En) => "Service installed successfully",
        ("service.uninstalling", Lang::Zh) => "正在卸载服务...",
        ("service.uninstalling", Lang::En) => "Uninstalling service...",
        ("service.uninstalled", Lang::Zh) => "服务卸载成功",
        ("service.uninstalled", Lang::En) => "Service uninstalled successfully",
        ("service.starting", Lang::Zh) => "正在启动服务...",
        ("service.starting", Lang::En) => "Starting service...",
        ("service.started", Lang::Zh) => "服务已启动",
        ("service.started", Lang::En) => "Service started",
        ("service.stopping", Lang::Zh) => "正在停止服务...",
        ("service.stopping", Lang::En) => "Stopping service...",
        ("service.stopped", Lang::Zh) => "服务已停止",
        ("service.stopped", Lang::En) => "Service stopped",
        ("service.error", Lang::Zh) => "服务操作失败",
        ("service.error", Lang::En) => "Service operation failed",
        ("service.not_supported", Lang::Zh) => "当前平台不支持此操作",
        ("service.not_supported", Lang::En) => "Operation not supported on this platform",

        // Diagnostics
        ("diag.title", Lang::Zh) => "系统诊断",
        ("diag.title", Lang::En) => "System Diagnostics",
        ("diag.checking", Lang::Zh) => "正在检查...",
        ("diag.checking", Lang::En) => "Checking...",
        ("diag.network", Lang::Zh) => "网络连通性",
        ("diag.network", Lang::En) => "Network Connectivity",
        ("diag.dns", Lang::Zh) => "DNS 解析",
        ("diag.dns", Lang::En) => "DNS Resolution",
        ("diag.permissions", Lang::Zh) => "权限检查",
        ("diag.permissions", Lang::En) => "Permission Check",
        ("diag.disk_space", Lang::Zh) => "磁盘空间",
        ("diag.disk_space", Lang::En) => "Disk Space",
        ("diag.config_valid", Lang::Zh) => "配置文件验证",
        ("diag.config_valid", Lang::En) => "Config Validation",
        ("diag.server_reach", Lang::Zh) => "服务器可达性",
        ("diag.server_reach", Lang::En) => "Server Reachability",
        ("diag.ok", Lang::Zh) => "正常",
        ("diag.ok", Lang::En) => "OK",
        ("diag.warning", Lang::Zh) => "警告",
        ("diag.warning", Lang::En) => "Warning",
        ("diag.error", Lang::Zh) => "错误",
        ("diag.error", Lang::En) => "Error",
        ("diag.complete", Lang::Zh) => "诊断完成",
        ("diag.complete", Lang::En) => "Diagnostics complete",
        ("diag.dns_failed", Lang::Zh) => "DNS 解析失败",
        ("diag.dns_failed", Lang::En) => "DNS resolution failed",

        // View logs
        ("logs.title", Lang::Zh) => "查看日志",
        ("logs.title", Lang::En) => "View Logs",
        ("logs.last_lines", Lang::Zh) => "最近日志条目",
        ("logs.last_lines", Lang::En) => "Recent log entries",
        ("logs.no_logs", Lang::Zh) => "没有找到日志文件",
        ("logs.no_logs", Lang::En) => "No log file found",
        ("logs.audit", Lang::Zh) => "审计日志",
        ("logs.audit", Lang::En) => "Audit Logs",
        ("logs.system", Lang::Zh) => "系统日志",
        ("logs.system", Lang::En) => "System Logs",
        ("logs.lines_count", Lang::Zh) => "显示行数",
        ("logs.lines_count", Lang::En) => "Lines to show",
        ("logs.showing_minutes", Lang::Zh) => "（显示最近 {} 分钟的日志）",
        ("logs.showing_minutes", Lang::En) => "(Showing logs from the last {} minutes)",
        ("logs.event_viewer", Lang::Zh) => "请在事件查看器中查看 NanoLink Agent 日志",
        ("logs.event_viewer", Lang::En) => "Check Event Viewer for NanoLink Agent logs",

        // Export config
        ("export.title", Lang::Zh) => "导出配置",
        ("export.title", Lang::En) => "Export Configuration",
        ("export.path", Lang::Zh) => "导出路径",
        ("export.path", Lang::En) => "Export path",
        ("export.success", Lang::Zh) => "配置导出成功",
        ("export.success", Lang::En) => "Configuration exported successfully",
        ("export.failed", Lang::Zh) => "导出失败",
        ("export.failed", Lang::En) => "Export failed",
        ("export.format", Lang::Zh) => "导出格式",
        ("export.format", Lang::En) => "Export format",
        ("export.sensitive_warning", Lang::Zh) => "配置中包含敏感 Token！",
        ("export.sensitive_warning", Lang::En) => "Configuration contains sensitive tokens!",
        ("export.plaintext_warning", Lang::Zh) => "导出的文件会以明文包含认证 Token。",
        ("export.plaintext_warning", Lang::En) => {
            "The exported file will include authentication tokens in plaintext."
        }
        ("export.redact_prompt", Lang::Zh) => "隐藏敏感 Token？（推荐）",
        ("export.redact_prompt", Lang::En) => "Redact sensitive tokens? (Recommended)",
        ("export.redacted", Lang::Zh) => "导出时将隐藏 Token。",
        ("export.redacted", Lang::En) => "Tokens will be redacted in the export.",
        ("export.included", Lang::Zh) => "Token 将以明文导出，请谨慎处理！",
        ("export.included", Lang::En) => "Tokens will be included in plaintext. Handle with care!",
        ("export.path_traversal", Lang::Zh) => "不允许使用路径穿越",
        ("export.path_traversal", Lang::En) => "Path traversal is not allowed",
        ("export.system_directory", Lang::Zh) => "不能写入系统目录",
        ("export.system_directory", Lang::En) => "Cannot write to a system directory",

        // Immediate send / Connection control
        ("config.immediate_send", Lang::Zh) => "立即发送数据",
        ("config.immediate_send", Lang::En) => "Send Data Immediately",
        ("config.immediate_send_desc", Lang::Zh) => "立即触发重连并发送缓冲数据",
        ("config.immediate_send_desc", Lang::En) => {
            "Trigger immediate reconnection and send buffered data"
        }
        ("config.send_triggered", Lang::Zh) => "已触发立即发送",
        ("config.send_triggered", Lang::En) => "Immediate send triggered",
        ("config.send_failed", Lang::Zh) => "发送触发失败",
        ("config.send_failed", Lang::En) => "Failed to trigger send",
        ("config.agent_not_running", Lang::Zh) => "Agent 未运行，请先启动 Agent",
        ("config.agent_not_running", Lang::En) => "Agent not running, please start Agent first",
        ("config.management_required", Lang::Zh) => "请先启用管理 API",
        ("config.management_required", Lang::En) => "Please enable Management API first",

        // Graphical configuration wizard
        ("gui.title", Lang::Zh) => "NanoLink Agent 配置",
        ("gui.title", Lang::En) => "NanoLink Agent Configuration",
        ("gui.version", Lang::Zh) => "版本",
        ("gui.version", Lang::En) => "Version",
        ("gui.welcome", Lang::Zh) => "欢迎使用 NanoLink Agent！",
        ("gui.welcome", Lang::En) => "Welcome to NanoLink Agent!",
        ("gui.no_config", Lang::Zh) => "未找到配置文件。",
        ("gui.no_config", Lang::En) => "No configuration file was found.",
        ("gui.help", Lang::Zh) => "此向导将帮助你完成 Agent 配置。",
        ("gui.help", Lang::En) => "This wizard will help you set up the agent.",
        ("gui.start_config", Lang::Zh) => "开始配置",
        ("gui.start_config", Lang::En) => "Start Configuration",
        ("gui.server_config", Lang::Zh) => "服务器配置",
        ("gui.server_config", Lang::En) => "Server Configuration",
        ("gui.enter_details", Lang::Zh) => "请输入 NanoLink 服务器信息：",
        ("gui.enter_details", Lang::En) => "Enter the NanoLink server details:",
        ("gui.server_host", Lang::Zh) => "服务器地址：",
        ("gui.server_host", Lang::En) => "Server Host:",
        ("gui.server_host_hint", Lang::Zh) => "例如 192.168.1.100 或 server.example.com",
        ("gui.server_host_hint", Lang::En) => "e.g., 192.168.1.100 or server.example.com",
        ("gui.port", Lang::Zh) => "端口：",
        ("gui.port", Lang::En) => "Port:",
        ("gui.auth_token", Lang::Zh) => "认证 Token：",
        ("gui.auth_token", Lang::En) => "Auth Token:",
        ("gui.auth_token_hint", Lang::Zh) => "请输入认证 Token",
        ("gui.auth_token_hint", Lang::En) => "Enter your authentication token",
        ("gui.hide", Lang::Zh) => "隐藏",
        ("gui.hide", Lang::En) => "Hide",
        ("gui.show", Lang::Zh) => "显示",
        ("gui.show", Lang::En) => "Show",
        ("gui.permission", Lang::Zh) => "权限级别：",
        ("gui.permission", Lang::En) => "Permission Level:",
        ("gui.tls", Lang::Zh) => "TLS：",
        ("gui.tls", Lang::En) => "TLS:",
        ("gui.enable_tls", Lang::Zh) => "启用 TLS",
        ("gui.enable_tls", Lang::En) => "Enable TLS",
        ("gui.tls_required", Lang::Zh) => "必须验证服务器证书",
        ("gui.tls_required", Lang::En) => "Certificate verification is required",
        ("gui.save_start", Lang::Zh) => "保存并启动 Agent",
        ("gui.save_start", Lang::En) => "Save & Start Agent",
        ("gui.saved", Lang::Zh) => "配置已保存！",
        ("gui.saved", Lang::En) => "Configuration Saved!",
        ("gui.config_file", Lang::Zh) => "配置文件",
        ("gui.config_file", Lang::En) => "Config file",
        ("gui.start_hint", Lang::Zh) => "现在可以运行以下命令启动 Agent：",
        ("gui.start_hint", Lang::En) => "You can now start the agent by running:",
        ("gui.service_hint", Lang::Zh) => "或安装为 Windows 服务：",
        ("gui.service_hint", Lang::En) => "Or install as a Windows Service:",
        ("gui.close", Lang::Zh) => "关闭",
        ("gui.close", Lang::En) => "Close",
        ("gui.window_title", Lang::Zh) => "NanoLink Agent - 配置向导",
        ("gui.window_title", Lang::En) => "NanoLink Agent - Configuration Wizard",
        ("gui.error.host_required", Lang::Zh) => "服务器地址不能为空",
        ("gui.error.host_required", Lang::En) => "Server host is required",
        ("gui.error.port_required", Lang::Zh) => "端口不能为空",
        ("gui.error.port_required", Lang::En) => "Port is required",
        ("gui.error.port_invalid", Lang::Zh) => "端口必须是 1–65535 之间的有效数字",
        ("gui.error.port_invalid", Lang::En) => "Port must be a valid number (1-65535)",
        ("gui.error.port_zero", Lang::Zh) => "端口必须大于 0",
        ("gui.error.port_zero", Lang::En) => "Port must be greater than 0",
        ("gui.error.token_required", Lang::Zh) => "认证 Token 不能为空",
        ("gui.error.token_required", Lang::En) => "Authentication token is required",
        ("gui.error.serialize_failed", Lang::Zh) => "序列化配置失败",
        ("gui.error.serialize_failed", Lang::En) => "Failed to serialize config",
        ("gui.error.write_failed", Lang::Zh) => "写入配置文件失败",
        ("gui.error.write_failed", Lang::En) => "Failed to write config file",
        ("gui.error.run_failed", Lang::Zh) => "启动配置向导失败",
        ("gui.error.run_failed", Lang::En) => "Failed to run wizard",

        // Non-interactive CLI and status output
        ("cli.searched_locations", Lang::Zh) => "已搜索以下位置",
        ("cli.searched_locations", Lang::En) => "Searched locations",
        ("cli.quick_start", Lang::Zh) => "快速开始",
        ("cli.quick_start", Lang::En) => "Quick start",
        ("cli.init_config", Lang::Zh) => "初始化新配置",
        ("cli.init_config", Lang::En) => "Initialize a new config",
        ("cli.add_server", Lang::Zh) => "添加服务器",
        ("cli.add_server", Lang::En) => "Add a server",
        ("cli.run_agent", Lang::Zh) => "运行 Agent",
        ("cli.run_agent", Lang::En) => "Run the agent",
        ("cli.specify_config", Lang::Zh) => "或指定配置文件",
        ("cli.specify_config", Lang::En) => "Or specify a config file",
        ("cli.generate_config", Lang::Zh) => "生成示例配置",
        ("cli.generate_config", Lang::En) => "Generate sample config",
        ("cli.config_exists", Lang::Zh) => "配置文件已存在",
        ("cli.config_exists", Lang::En) => "Config file already exists",
        ("cli.use_other_output", Lang::Zh) => "请使用 --output 指定其他路径。",
        ("cli.use_other_output", Lang::En) => "Use --output to specify a different path.",
        ("cli.next_steps", Lang::Zh) => "后续步骤",
        ("cli.next_steps", Lang::En) => "Next steps",
        ("cli.config_file", Lang::Zh) => "配置文件",
        ("cli.config_file", Lang::En) => "Config file",
        ("cli.none", Lang::Zh) => "无",
        ("cli.none", Lang::En) => "none",
        ("cli.permission", Lang::Zh) => "权限",
        ("cli.permission", Lang::En) => "Permission",
        ("cli.verify", Lang::Zh) => "验证证书",
        ("cli.verify", Lang::En) => "Verify",
        ("cli.settings", Lang::Zh) => "设置",
        ("cli.settings", Lang::En) => "Settings",
        ("cli.port", Lang::Zh) => "端口",
        ("cli.port", Lang::En) => "port",
        ("cli.config_load_error", Lang::Zh) => "加载配置失败",
        ("cli.config_load_error", Lang::En) => "Error loading config",
        ("cli.not_found", Lang::Zh) => "未找到",
        ("cli.not_found", Lang::En) => "not found",
        ("cli.server_exists", Lang::Zh) => "服务器已存在：",
        ("cli.server_exists", Lang::En) => "Server already exists:",
        ("cli.use_server_update", Lang::Zh) => "请使用 server update 修改。",
        ("cli.use_server_update", Lang::En) => "Use 'server update' to modify it.",
        ("cli.select_remove", Lang::Zh) => "选择要删除的服务器",
        ("cli.select_remove", Lang::En) => "Select server to remove",
        ("cli.confirm_remove", Lang::Zh) => "确认删除服务器",
        ("cli.confirm_remove", Lang::En) => "Confirm removal of",
        ("cli.cancelled", Lang::Zh) => "已取消。",
        ("cli.cancelled", Lang::En) => "Cancelled.",
        ("cli.server_not_found", Lang::Zh) => "未找到服务器",
        ("cli.server_not_found", Lang::En) => "Server not found",
        ("cli.cannot_remove_last", Lang::Zh) => "不能删除最后一个服务器。",
        ("cli.cannot_remove_last", Lang::En) => "Cannot remove the last server.",
        ("cli.select_update", Lang::Zh) => "选择要更新的服务器",
        ("cli.select_update", Lang::En) => "Select server to update",
        ("cli.host", Lang::Zh) => "地址",
        ("cli.host", Lang::En) => "Host",
        ("cli.token", Lang::Zh) => "Token",
        ("cli.token", Lang::En) => "Token",

        // Default fallback - return empty string for unknown keys
        _ => "",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_detect_language() {
        // This test depends on the system locale, so we just verify it returns a valid Lang
        let lang = detect_language();
        assert!(lang == Lang::En || lang == Lang::Zh);
    }

    #[test]
    fn test_translation() {
        assert_eq!(t("menu.start_agent", Lang::Zh), "启动 Agent");
        assert_eq!(t("menu.start_agent", Lang::En), "Start Agent");
    }

    #[test]
    fn test_unknown_key_fallback() {
        assert_eq!(t("unknown.key", Lang::En), "");
        assert_eq!(t("unknown.key", Lang::Zh), "");
    }
}
