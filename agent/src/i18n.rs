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
