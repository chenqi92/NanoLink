//! Internationalization (i18n) module for NanoLink Agent
//!
//! Provides bilingual support (English/Chinese) with automatic language detection.

use sys_locale::get_locale;

/// Supported languages
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Lang {
    #[default]
    En,
    Zh,
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
