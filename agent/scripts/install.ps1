#Requires -RunAsAdministrator
<#
.SYNOPSIS
    NanoLink Agent Interactive Installation Script for Windows

.DESCRIPTION
    Downloads and installs the NanoLink monitoring agent as a Windows Service.
    Supports both interactive and silent installation modes.

.PARAMETER Silent
    Run in silent mode (no prompts)

.PARAMETER Url
    Server address in host:port format (required in silent mode)

.PARAMETER Token
    Authentication token (required in silent mode)

.PARAMETER Permission
    Permission level (0-3, default: 0)

.PARAMETER NoTlsVerify
    Deprecated and rejected. Configure a trusted CA instead.

.PARAMETER NoTls
    Use plaintext gRPC. Only suitable when another trusted transport protects the connection.

.PARAMETER TlsCaCert
    PEM CA certificate path for an internal or private PKI.

.PARAMETER TlsServerName
    Certificate DNS name to verify when connecting through a tunnel endpoint.

.PARAMETER TlsClientCert
    PEM Agent client certificate path for mutual TLS.

.PARAMETER TlsClientKey
    PEM Agent private key path for mutual TLS.

.PARAMETER Hostname
    Override system hostname

.PARAMETER ShellEnabled
    Enable shell command execution

.PARAMETER ShellToken
    Shell super token (required if ShellEnabled)

.EXAMPLE
    # Interactive installation
    .\install.ps1

.EXAMPLE
    # Silent installation
    .\install.ps1 -Silent -Url "server.example.com:39100" -Token "your_token"
#>

[CmdletBinding()]
param(
    [switch]$Silent,
    [string]$Url,
    [string]$Token,
    [int]$Permission = 0,
    [switch]$NoTlsVerify,
    [switch]$NoTls,
    [string]$TlsCaCert,
    [string]$TlsServerName,
    [string]$TlsClientCert,
    [string]$TlsClientKey,
    [string]$Hostname,
    [switch]$ShellEnabled,
    [string]$ShellToken,
    [switch]$AddServer,
    [switch]$RemoveServer,
    [string]$FetchConfig,
    [switch]$Manage,
    [string]$Lang,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# =============================================================================
# Configuration
# =============================================================================
$Script:VERSION = "0.4.10"
$Script:ServiceName = "NanoLinkAgent"
$Script:ServiceDisplayName = "NanoLink Monitoring Agent"
$Script:InstallDir = "C:\Program Files\NanoLink"
$Script:ConfigDir = "C:\ProgramData\NanoLink"
$Script:LogDir = "C:\ProgramData\NanoLink\logs"
$Script:BinaryName = "nanolink-agent.exe"
$Script:GitHubRepo = "chenqi92/NanoLink"
$Script:TlsEnabled = -not $NoTls
$Script:TlsVerify = $true
$Script:TlsCaCert = $TlsCaCert
$Script:TlsServerName = $TlsServerName
$Script:TlsClientCert = $TlsClientCert
$Script:TlsClientKey = $TlsClientKey

# =============================================================================
# Internationalization (i18n)
# =============================================================================
$Script:ScriptLang = ""

# Message dictionaries
$Script:EnMsgs = @{
    # General
    "banner_subtitle"     = "Lightweight Server Monitoring Agent"
    "detected"            = "Detected"
    "version"             = "Version"
    
    # Status
    "info"                = "INFO"
    "success"             = "SUCCESS"
    "warn"                = "WARN"
    "error"               = "ERROR"
    
    # Installation
    "existing_detected"   = "Existing Installation Detected"
    "installed_version"   = "Installed version"
    "script_version"      = "Script version"
    "service_running"     = "Agent service is currently running"
    "service_stopped"     = "Agent service is stopped"
    "config_exists"       = "Configuration exists at"
    "what_to_do"          = "What would you like to do?"
    "select_action"       = "Select action"
    "opt_update"          = "Update agent (download latest binary, keep config)"
    "opt_manage"          = "Manage existing agent (open management menu)"
    "opt_fresh"           = "Fresh install (overwrite config and binary)"
    "opt_cancel"          = "Cancel"
    "stopping_service"    = "Stopping agent service before update..."
    "service_stopped_ok"  = "Service stopped"
    "warn_overwrite"      = "This will overwrite existing configuration!"
    "are_you_sure"        = "Are you sure?"
    "cancelled"           = "Installation cancelled"
    "keeping_config"      = "Keeping existing configuration"
    "update_success"      = "Agent updated successfully!"
    "update_config_choice" = "Do you want to update server configuration?"
    "skip_config"         = "Skip (keep existing configuration)"
    "update_config"       = "Update server configuration"

    # Server config
    "server_config"       = "Server Configuration"
    "server_url_prompt"   = "Server address (e.g., monitor.example.com:39100)"
    "url_invalid"         = "Invalid format. Use host:port (e.g., server.example.com:39100)"
    "token_prompt"        = "Authentication Token"
    "permission_level"    = "Permission Level"
    "perm_readonly"       = "Read Only (monitoring only)"
    "perm_basic"          = "Read + Process Control"
    "perm_shell"          = "Read + Process + Limited Shell"
    "perm_full"           = "Full Access (all operations)"
    "verify_tls"          = "Verify TLS certificate?"
    "tls_disabled_warn"   = "TLS verification disabled - only use for testing!"
    "test_connection"     = "Test server connection before installing?"
    "use_hostname"        = "Use system hostname"
    "custom_hostname"     = "Custom hostname"
    "enable_shell"        = "Enable shell command execution? (requires super token)"
    "shell_token_prompt"  = "Shell Super Token (different from auth token)"
    
    # Download & Install
    "downloading"         = "Downloading NanoLink Agent"
    "download_success"    = "Downloaded successfully"
    "download_failed"     = "Failed to download"
    "unsupported_arch"    = "Unsupported Windows architecture"
    "installing_binary"   = "Installing Binary"
    "installed_to"        = "Installed to"
    "creating_dirs"       = "Creating Directories"
    "dirs_created"        = "Directories created"
    "generating_config"   = "Generating Configuration"
    "config_saved"        = "Configuration saved to"
    
    # Service
    "installing_service"  = "Installing Windows Service"
    "service_installed"   = "Service installed"
    "starting_service"    = "Starting Service"
    "service_started"     = "Service started"
    "start_failed"        = "Failed to start service"
    "verifying"           = "Verifying Installation"
    "all_passed"          = "All checks passed!"
    
    # Summary
    "install_complete"    = "Installation Complete!"
    "install_details"     = "Installation Details"
    "binary"              = "Binary"
    "config"              = "Config"
    "logs"                = "Logs"
    "server"              = "Server"
    "useful_commands"     = "Useful Commands"
    "status"              = "Status"
    "restart"             = "Restart"
    "stop"                = "Stop"
    "permission"          = "Permission"
    "uninstall"           = "Uninstall"
    
    # Management menu
    "mgmt_menu_title"     = "NanoLink Agent Management Menu"
    "server_management"   = "Server Management"
    "add_server"          = "Add new server"
    "modify_server"       = "Modify server configuration"
    "remove_server"       = "Remove server"
    "list_servers"        = "List configured servers"
    "metrics_collection"  = "Metrics & Collection"
    "config_metrics"      = "Configure metrics collection intervals"
    "service_control"     = "Service Control"
    "show_status"         = "Show agent status"
    "start_agent"         = "Start agent"
    "stop_agent"          = "Stop agent"
    "restart_agent"       = "Restart agent"
    "reload_config"       = "Reload configuration (hot-reload)"
    "maintenance"         = "Maintenance"
    "view_logs_menu"      = "View logs"
    "uninstall_agent"     = "Uninstall agent"
    "exit"                = "Exit"
    "select_option"       = "Select option"
    "press_enter"         = "Press Enter to continue..."
    "goodbye"             = "Goodbye!"
    "invalid_option"      = "Invalid option"
    
    # Agent status
    "agent_status"        = "Agent Status"
    "service_status"      = "Service Status"
    "running"             = "Running"
    "stopped"             = "Stopped"
    "configuration"       = "Configuration"
    
    # Uninstall
    "uninstall_title"     = "Uninstall NanoLink Agent"
    "uninstall_warn"      = "This will remove the NanoLink Agent from your system."
    "confirm_uninstall"   = "Are you sure you want to uninstall?"
    "uninstall_cancelled" = "Uninstall cancelled"
    "binary_removed"      = "Binary removed"
    "remove_data"         = "Remove configuration and data?"
    "data_removed"        = "Configuration and data removed"
    "uninstall_complete"  = "NanoLink Agent has been uninstalled"
    
    # Logs
    "log_file_not_found"  = "Log file not found"
    "last_lines"          = "Last 30 lines of agent log"
    "follow_logs"         = "Follow logs in real-time?"
    "press_ctrl_c"        = "Press Ctrl+C to stop..."
    
    # Config
    "config_not_found"    = "Configuration file not found"
    "configured_servers"  = "Configured Servers"
    "metrics_config"      = "Metrics Configuration"
    "current_settings"    = "Current collector settings"
    "reload_now"          = "Reload configuration now?"
    "reload_success"      = "Configuration reloaded successfully!"
    "service_restarted"   = "Service restarted"

    # Runtime validation, maintenance, and help
    "required_field"      = "This field is required"
    "testing_connection"  = "Testing Connection"
    "testing_server"      = "Testing connection to"
    "server_reachable"    = "Server is reachable!"
    "cannot_reach"        = "Cannot reach server at"
    "continue_anyway"     = "Continue anyway?"
    "connection_failed"   = "Connection test failed"
    "enable_tls_transport" = "Enable TLS?"
    "tls_verification_required" = "TLS certificate verification is required. Configure tls_ca_cert for a private CA."
    "config_backed_up"    = "Existing config backed up to"
    "service_installed_recovery" = "Windows Service installed with auto-recovery"
    "check_logs"          = "Check logs at"
    "event_viewer"        = "Event Viewer"
    "binary_installed"    = "Binary installed"
    "config_exists_check" = "Configuration exists"
    "service_installed_check" = "Service installed"
    "service_running_check" = "Service running"
    "checks_passed"       = "checks passed"
    "service_management"  = "Service Management"
    "unknown"             = "Unknown"
    "stopping_existing_service" = "Stopping existing service..."
    "removing_existing_service" = "Removing existing service..."
    "fresh_install_first" = "Please run a fresh installation first"
    "agent_binary_not_found" = "Agent binary not found"
    "server_add_failed"   = "Failed to add server"
    "server_added"        = "Server added to configuration"
    "restart_to_apply"    = "Restart the agent to apply changes"
    "server_not_found"    = "Server not found in configuration"
    "server_removed"      = "Server removed from configuration"
    "server_removed_hot_reload" = "Server removed via management API (hot-reload)"
    "fetching_config"     = "Fetching configuration from"
    "invalid_config_response" = "Invalid configuration response from server"
    "config_fetched"      = "Configuration fetched successfully"
    "fetch_config_failed" = "Failed to fetch configuration"
    "no_servers"          = "No servers configured"
    "modify_intervals"    = "Modify collector intervals?"
    "cpu_interval"        = "CPU interval (ms)"
    "disk_interval"       = "Disk interval (ms)"
    "network_interval"    = "Network interval (ms)"
    "intervals_updated"   = "Collector intervals updated"
    "reload_failed"       = "Hot reload failed. Restarting service..."
    "reload_unavailable"  = "Hot reload not available. Restarting service..."
    "view_logs"           = "View Logs"
    "data_preserved"      = "Configuration and data preserved at"
    "service_removed"     = "Service removed"
    "add_mode_requires"   = "Add server mode requires -Url and -Token parameters"
    "remove_mode_requires" = "Remove server mode requires -Url parameter"
    "silent_requires_credentials" = "Silent mode requires -Url and -Token parameters"
    "no_tls_verify_rejected" = "-NoTlsVerify is no longer supported; configure a trusted CA or tls_ca_cert"
    "tls_options_conflict" = "TLS certificate options cannot be combined with -NoTls"
    "tls_client_pair_required" = "-TlsClientCert and -TlsClientKey must be provided together"
    "tls_file_not_found"  = "TLS file not found"

    # Help
    "help_title"          = "NanoLink Agent Installer for Windows"
    "usage"               = "Usage"
    "install_options"     = "Installation Options"
    "silent_mode"         = "Silent mode (no prompts)"
    "url_option"          = "Server address (host:port)"
    "token_option"        = "Authentication token"
    "permission_option"   = "Permission level (0-3)"
    "no_tls_option"       = "Use plaintext gRPC (trusted private transport only)"
    "tls_ca_option"       = "PEM CA for an internal/private PKI"
    "tls_server_name_option" = "Certificate DNS name when connecting through a tunnel"
    "tls_client_cert_option" = "PEM Agent certificate for mutual TLS"
    "tls_client_key_option" = "PEM Agent private key for mutual TLS"
    "no_tls_verify_option" = "Rejected (configure a trusted CA instead)"
    "hostname_option"     = "Override hostname"
    "shell_enabled_option" = "Enable shell commands"
    "shell_token_option"  = "Shell super token"
    "server_mgmt"         = "Server Management"
    "add_server_option"   = "Add server to existing installation"
    "remove_server_option" = "Remove server from existing installation"
    "fetch_config_option" = "Fetch configuration from server API"
    "management"          = "Management"
    "manage_option"       = "Interactive management menu"
    "lang_option"         = "Set language (en/zh)"
    "help_option"         = "Show this help"
    "examples"            = "Examples"
    "interactive_install" = "Interactive installation"
    "silent_install"      = "Silent installation"
    "add_server_example"  = "Add additional server to existing agent"
    "open_manage"         = "Open management menu"
    "remove_server_example" = "Remove a server"
    "fetch_config_example" = "Fetch config from server and install"
}

$Script:ZhMsgs = @{
    # General
    "banner_subtitle"     = "轻量级服务器监控代理"
    "detected"            = "检测到"
    "version"             = "版本"
    
    # Status
    "info"                = "信息"
    "success"             = "成功"
    "warn"                = "警告"
    "error"               = "错误"
    
    # Installation
    "existing_detected"   = "检测到已安装的 Agent"
    "installed_version"   = "已安装版本"
    "script_version"      = "脚本版本"
    "service_running"     = "Agent 服务正在运行"
    "service_stopped"     = "Agent 服务已停止"
    "config_exists"       = "配置文件位于"
    "what_to_do"          = "请选择操作"
    "select_action"       = "选择操作"
    "opt_update"          = "更新 Agent（下载最新版本，保留配置）"
    "opt_manage"          = "管理现有 Agent（打开管理菜单）"
    "opt_fresh"           = "全新安装（覆盖配置和二进制文件）"
    "opt_cancel"          = "取消"
    "stopping_service"    = "更新前停止 Agent 服务..."
    "service_stopped_ok"  = "服务已停止"
    "warn_overwrite"      = "这将覆盖现有配置！"
    "are_you_sure"        = "确定继续吗？"
    "cancelled"           = "安装已取消"
    "keeping_config"      = "保留现有配置"
    "update_success"      = "Agent 更新成功！"
    "update_config_choice" = "是否更新服务器配置？"
    "skip_config"         = "跳过（保留现有配置）"
    "update_config"       = "更新服务器配置"

    # Server config
    "server_config"       = "服务器配置"
    "server_url_prompt"   = "服务器地址（例如：monitor.example.com:39100）"
    "url_invalid"         = "格式无效，请使用 host:port 格式（例如：server.example.com:39100）"
    "token_prompt"        = "认证令牌"
    "permission_level"    = "权限级别"
    "perm_readonly"       = "只读（仅监控）"
    "perm_basic"          = "读取 + 进程控制"
    "perm_shell"          = "读取 + 进程 + 受限 Shell"
    "perm_full"           = "完全访问（所有操作）"
    "verify_tls"          = "验证 TLS 证书？"
    "tls_disabled_warn"   = "TLS 验证已禁用 - 仅用于测试环境！"
    "test_connection"     = "安装前测试服务器连接？"
    "use_hostname"        = "使用系统主机名"
    "custom_hostname"     = "自定义主机名"
    "enable_shell"        = "启用 Shell 命令执行？（需要超级令牌）"
    "shell_token_prompt"  = "Shell 超级令牌（与认证令牌不同）"
    
    # Download & Install
    "downloading"         = "正在下载 NanoLink Agent"
    "download_success"    = "下载成功"
    "download_failed"     = "下载失败"
    "unsupported_arch"    = "不支持的 Windows 处理器架构"
    "installing_binary"   = "安装二进制文件"
    "installed_to"        = "已安装到"
    "creating_dirs"       = "创建目录"
    "dirs_created"        = "目录创建完成"
    "generating_config"   = "生成配置文件"
    "config_saved"        = "配置已保存到"
    
    # Service
    "installing_service"  = "安装 Windows 服务"
    "service_installed"   = "服务已安装"
    "starting_service"    = "启动服务"
    "service_started"     = "服务已启动"
    "start_failed"        = "服务启动失败"
    "verifying"           = "验证安装"
    "all_passed"          = "所有检查通过！"
    
    # Summary
    "install_complete"    = "安装完成！"
    "install_details"     = "安装详情"
    "binary"              = "二进制文件"
    "config"              = "配置文件"
    "logs"                = "日志目录"
    "server"              = "服务器"
    "useful_commands"     = "常用命令"
    "status"              = "查看状态"
    "restart"             = "重启服务"
    "stop"                = "停止服务"
    "permission"          = "权限"
    "uninstall"           = "卸载"
    
    # Management menu
    "mgmt_menu_title"     = "NanoLink Agent 管理菜单"
    "server_management"   = "服务器管理"
    "add_server"          = "添加新服务器"
    "modify_server"       = "修改服务器配置"
    "remove_server"       = "删除服务器"
    "list_servers"        = "列出已配置的服务器"
    "metrics_collection"  = "指标采集"
    "config_metrics"      = "配置指标采集频率"
    "service_control"     = "服务控制"
    "show_status"         = "查看 Agent 状态"
    "start_agent"         = "启动 Agent"
    "stop_agent"          = "停止 Agent"
    "restart_agent"       = "重启 Agent"
    "reload_config"       = "重载配置（热更新）"
    "maintenance"         = "维护"
    "view_logs_menu"      = "查看日志"
    "uninstall_agent"     = "卸载 Agent"
    "exit"                = "退出"
    "select_option"       = "请选择"
    "press_enter"         = "按回车键继续..."
    "goodbye"             = "再见！"
    "invalid_option"      = "无效选项"
    
    # Agent status
    "agent_status"        = "Agent 状态"
    "service_status"      = "服务状态"
    "running"             = "运行中"
    "stopped"             = "已停止"
    "configuration"       = "配置文件"
    
    # Uninstall
    "uninstall_title"     = "卸载 NanoLink Agent"
    "uninstall_warn"      = "这将从系统中移除 NanoLink Agent。"
    "confirm_uninstall"   = "确定要卸载吗？"
    "uninstall_cancelled" = "卸载已取消"
    "binary_removed"      = "二进制文件已删除"
    "remove_data"         = "删除配置和数据？"
    "data_removed"        = "配置和数据已删除"
    "uninstall_complete"  = "NanoLink Agent 已卸载"
    
    # Logs
    "log_file_not_found"  = "日志文件未找到"
    "last_lines"          = "最近 30 行日志"
    "follow_logs"         = "实时跟踪日志？"
    "press_ctrl_c"        = "按 Ctrl+C 停止..."
    
    # Config
    "config_not_found"    = "配置文件未找到"
    "configured_servers"  = "已配置的服务器"
    "metrics_config"      = "指标配置"
    "current_settings"    = "当前采集器设置"
    "reload_now"          = "立即重载配置？"
    "reload_success"      = "配置重载成功！"
    "service_restarted"   = "服务已重启"

    # 运行时校验、维护和帮助
    "required_field"      = "此字段为必填项"
    "testing_connection"  = "测试连接"
    "testing_server"      = "正在测试连接到"
    "server_reachable"    = "服务器可访问！"
    "cannot_reach"        = "无法连接到服务器"
    "continue_anyway"     = "是否继续？"
    "connection_failed"   = "连接测试失败"
    "enable_tls_transport" = "启用 TLS？"
    "tls_verification_required" = "必须验证 TLS 证书；私有 CA 请配置 tls_ca_cert。"
    "config_backed_up"    = "已备份现有配置到"
    "service_installed_recovery" = "Windows 服务已安装并配置自动恢复"
    "check_logs"          = "查看日志"
    "event_viewer"        = "事件查看器"
    "binary_installed"    = "二进制文件已安装"
    "config_exists_check" = "配置文件存在"
    "service_installed_check" = "服务已安装"
    "service_running_check" = "服务正在运行"
    "checks_passed"       = "项检查通过"
    "service_management"  = "服务管理"
    "unknown"             = "未知"
    "stopping_existing_service" = "正在停止现有服务..."
    "removing_existing_service" = "正在删除现有服务..."
    "fresh_install_first" = "请先执行全新安装"
    "agent_binary_not_found" = "未找到 Agent 程序"
    "server_add_failed"   = "添加服务器失败"
    "server_added"        = "服务器已添加到配置"
    "restart_to_apply"    = "重启 Agent 以应用更改"
    "server_not_found"    = "配置中未找到此服务器"
    "server_removed"      = "服务器已从配置中删除"
    "server_removed_hot_reload" = "已通过管理 API 删除服务器（热重载）"
    "fetching_config"     = "正在获取配置"
    "invalid_config_response" = "服务器返回的配置无效"
    "config_fetched"      = "配置获取成功"
    "fetch_config_failed" = "获取配置失败"
    "no_servers"          = "未配置服务器"
    "modify_intervals"    = "修改采集频率？"
    "cpu_interval"        = "CPU 采集间隔（毫秒）"
    "disk_interval"       = "磁盘采集间隔（毫秒）"
    "network_interval"    = "网络采集间隔（毫秒）"
    "intervals_updated"   = "采集频率已更新"
    "reload_failed"       = "热重载失败，正在重启服务..."
    "reload_unavailable"  = "热重载不可用，正在重启服务..."
    "view_logs"           = "查看日志"
    "data_preserved"      = "配置和数据已保留在"
    "service_removed"     = "服务已删除"
    "add_mode_requires"   = "添加服务器模式需要 -Url 和 -Token 参数"
    "remove_mode_requires" = "删除服务器模式需要 -Url 参数"
    "silent_requires_credentials" = "静默模式需要 -Url 和 -Token 参数"
    "no_tls_verify_rejected" = "不再支持 -NoTlsVerify；请配置受信任的 CA 或 tls_ca_cert"
    "tls_options_conflict" = "TLS 证书选项不能与 -NoTls 同时使用"
    "tls_client_pair_required" = "-TlsClientCert 和 -TlsClientKey 必须同时提供"
    "tls_file_not_found"  = "未找到 TLS 文件"

    # 帮助
    "help_title"          = "NanoLink Agent Windows 安装程序"
    "usage"               = "用法"
    "install_options"     = "安装选项"
    "silent_mode"         = "静默模式（无提示）"
    "url_option"          = "服务器地址（host:port）"
    "token_option"        = "认证令牌"
    "permission_option"   = "权限级别（0-3）"
    "no_tls_option"       = "使用明文 gRPC（仅限受信任的私有传输）"
    "tls_ca_option"       = "内部或私有 PKI 的 PEM CA"
    "tls_server_name_option" = "通过隧道连接时要验证的证书 DNS 名称"
    "tls_client_cert_option" = "用于双向 TLS 的 Agent PEM 证书"
    "tls_client_key_option" = "用于双向 TLS 的 Agent PEM 私钥"
    "no_tls_verify_option" = "不再支持（请配置受信任的 CA）"
    "hostname_option"     = "覆盖主机名"
    "shell_enabled_option" = "启用 Shell 命令"
    "shell_token_option"  = "Shell 超级令牌"
    "server_mgmt"         = "服务器管理"
    "add_server_option"   = "添加服务器到现有安装"
    "remove_server_option" = "从现有安装中删除服务器"
    "fetch_config_option" = "从服务器 API 获取配置"
    "management"          = "管理"
    "manage_option"       = "交互式管理菜单"
    "lang_option"         = "设置语言（en/zh）"
    "help_option"         = "显示帮助"
    "examples"            = "示例"
    "interactive_install" = "交互式安装"
    "silent_install"      = "静默安装"
    "add_server_example"  = "添加额外服务器到现有 Agent"
    "open_manage"         = "打开管理菜单"
    "remove_server_example" = "删除服务器"
    "fetch_config_example" = "从服务器获取配置并安装"
}

function Initialize-Language {
    if (-not [string]::IsNullOrEmpty($Script:ScriptLang)) {
        return
    }
    
    # Check -Lang parameter
    if (-not [string]::IsNullOrEmpty($Lang)) {
        $Script:ScriptLang = $Lang
        return
    }
    
    # Auto-detect from system culture
    $culture = [System.Globalization.CultureInfo]::CurrentUICulture.Name
    if ($culture -match "^zh") {
        $Script:ScriptLang = "zh"
    }
    else {
        $Script:ScriptLang = "en"
    }
}

function Get-Msg {
    param([string]$Key)
    
    if ($Script:ScriptLang -eq "zh") {
        $msg = $Script:ZhMsgs[$Key]
    }
    else {
        $msg = $Script:EnMsgs[$Key]
    }
    
    if ([string]::IsNullOrEmpty($msg)) {
        return $Key
    }
    return $msg
}

function Test-TlsParameters {
    if ($NoTlsVerify) {
        throw (Get-Msg "no_tls_verify_rejected")
    }
    if ($NoTls -and ($TlsCaCert -or $TlsServerName -or $TlsClientCert -or $TlsClientKey)) {
        throw (Get-Msg "tls_options_conflict")
    }
    if ([bool]$TlsClientCert -ne [bool]$TlsClientKey) {
        throw (Get-Msg "tls_client_pair_required")
    }
    foreach ($tlsFile in @($TlsCaCert, $TlsClientCert, $TlsClientKey)) {
        if ($tlsFile -and -not (Test-Path -LiteralPath $tlsFile -PathType Leaf)) {
            throw "$(Get-Msg 'tls_file_not_found'): $tlsFile"
        }
    }
}

# =============================================================================
# Helper Functions
# =============================================================================
function Write-Banner {
    $banner = @"

    ╔═══════════════════════════════════════════════════════════════╗
    ║                                                               ║
    ║     ███╗   ██╗ █████╗ ███╗   ██╗ ██████╗ ██╗     ██╗███╗   ██╗██╗  ██╗     ║
    ║     ████╗  ██║██╔══██╗████╗  ██║██╔═══██╗██║     ██║████╗  ██║██║ ██╔╝     ║
    ║     ██╔██╗ ██║███████║██╔██╗ ██║██║   ██║██║     ██║██╔██╗ ██║█████╔╝      ║
    ║     ██║╚██╗██║██╔══██║██║╚██╗██║██║   ██║██║     ██║██║╚██╗██║██╔═██╗      ║
    ║     ██║ ╚████║██║  ██║██║ ╚████║╚██████╔╝███████╗██║██║ ╚████║██║  ██╗     ║
    ║     ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝     ║
    ║                                                               ║
    ║              $(Get-Msg 'banner_subtitle')
    ║                        $(Get-Msg 'version') $Script:VERSION
    ║                                                               ║
    ╚═══════════════════════════════════════════════════════════════╝

"@
    Write-Host $banner -ForegroundColor Cyan
}

function Write-Info { param([string]$Message) Write-Host "[$(Get-Msg 'info')] $Message" -ForegroundColor Blue }
function Write-Success { param([string]$Message) Write-Host "[$(Get-Msg 'success')] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[$(Get-Msg 'warn')] $Message" -ForegroundColor Yellow }
function Write-Err { param([string]$Message) Write-Host "[$(Get-Msg 'error')] $Message" -ForegroundColor Red }
function Write-Step { param([string]$Message) Write-Host "`n▶ $Message" -ForegroundColor Cyan }

function Get-AgentArchitecture {
    $machineArchitecture = ""
    try {
        $machineArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    }
    catch {
        $machineArchitecture = $env:PROCESSOR_ARCHITEW6432
    }
    if ([string]::IsNullOrWhiteSpace($machineArchitecture)) {
        $machineArchitecture = $env:PROCESSOR_ARCHITECTURE
    }
    if ([string]::IsNullOrWhiteSpace($machineArchitecture)) {
        $machineArchitecture = "unknown"
    }

    switch ($machineArchitecture.ToUpperInvariant()) {
        "AMD64" { return "x86_64" }
        "X64" { return "x86_64" }
        "X86_64" { return "x86_64" }
        "ARM64" { return "aarch64" }
        "AARCH64" { return "aarch64" }
        default {
            Write-Err "$(Get-Msg 'unsupported_arch'): $machineArchitecture"
            exit 1
        }
    }
}

function Read-PromptValue {
    param(
        [string]$Prompt,
        [string]$Default = "",
        [switch]$Required,
        [switch]$Password
    )

    $displayPrompt = if ($Default) { "$Prompt [$Default]" } else { $Prompt }

    while ($true) {
        if ($Password) {
            $secureValue = Read-Host -Prompt $displayPrompt -AsSecureString
            $value = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
            )
        }
        else {
            $value = Read-Host -Prompt $displayPrompt
        }

        if ([string]::IsNullOrEmpty($value)) {
            if ($Default) {
                return $Default
            }
            if ($Required) {
                Write-Warn (Get-Msg "required_field")
                continue
            }
        }
        return $value
    }
}

function Read-YesNo {
    param(
        [string]$Prompt,
        [bool]$Default = $true
    )

    $defaultStr = if ($Default) { "Y/n" } else { "y/N" }
    $response = Read-Host -Prompt "$Prompt [$defaultStr]"

    if ([string]::IsNullOrEmpty($response)) {
        return $Default
    }
    return $response -match "^[Yy是]"
}

function Read-Choice {
    param(
        [string]$Prompt,
        [string[]]$Options
    )

    Write-Host $Prompt
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "  $($i + 1)) $($Options[$i])" -ForegroundColor Cyan
    }

    while ($true) {
        $choice = Read-Host -Prompt "$(Get-Msg 'select_option') [1-$($Options.Count)]"
        if ($choice -match '^\d+$') {
            $num = [int]$choice
            if ($num -ge 1 -and $num -le $Options.Count) {
                return $num - 1
            }
        }
        Write-Warn (Get-Msg "invalid_option")
    }
}

# =============================================================================
# Interactive Configuration
# =============================================================================
function Get-InteractiveConfig {
    Write-Step (Get-Msg "server_config")
    Write-Host ""

    # Server URL (now host:port format)
    while ($true) {
        $Script:ServerUrl = Read-PromptValue -Prompt (Get-Msg "server_url_prompt") -Required
        # Validate host:port format
        if ($Script:ServerUrl -notmatch "^[a-zA-Z0-9]([a-zA-Z0-9.\-]*[a-zA-Z0-9])?(:[0-9]+)?$") {
            Write-Warn (Get-Msg "url_invalid")
            continue
        }
        break
    }

    # Token
    $Script:AuthToken = Read-PromptValue -Prompt (Get-Msg "token_prompt") -Required

    # Permission level
    Write-Host ""
    $permOptions = @(
        (Get-Msg "perm_readonly"),
        (Get-Msg "perm_basic"),
        (Get-Msg "perm_shell"),
        (Get-Msg "perm_full")
    )
    $Script:PermissionLevel = Read-Choice -Prompt (Get-Msg "permission_level") -Options $permOptions

    # TLS settings
    Write-Host ""
    $Script:TlsEnabled = $false
    $Script:TlsVerify = $true
    if (Read-YesNo -Prompt (Get-Msg "enable_tls_transport") -Default $false) {
        $Script:TlsEnabled = $true
        Write-Info (Get-Msg "tls_verification_required")
    }

    # Test connection
    Write-Host ""
    if (Read-YesNo -Prompt (Get-Msg "test_connection") -Default $true) {
        Test-ServerConnection
    }

    # Hostname override
    Write-Host ""
    $Script:HostnameOverride = ""
    $systemHostname = [System.Net.Dns]::GetHostName()
    if (-not (Read-YesNo -Prompt "$(Get-Msg 'use_hostname') ($systemHostname)?" -Default $true)) {
        $Script:HostnameOverride = Read-PromptValue -Prompt (Get-Msg "custom_hostname")
    }

    # Shell commands
    Write-Host ""
    $Script:ShellEnabled = $false
    $Script:ShellSuperToken = ""
    if ($Script:PermissionLevel -ge 2) {
        if (Read-YesNo -Prompt (Get-Msg "enable_shell") -Default $false) {
            $Script:ShellEnabled = $true
            $Script:ShellSuperToken = Read-PromptValue -Prompt (Get-Msg "shell_token_prompt") -Required -Password
        }
    }
}

function Test-ServerConnection {
    Write-Step (Get-Msg "testing_connection")

    # Extract host and port from URL
    $uri = [System.Uri]$Script:ServerUrl
    $host_ = $uri.Host
    $port = if ($uri.Port -gt 0) { $uri.Port } else { 9100 }

    Write-Info "$(Get-Msg 'testing_server') ${host_}:$port..."

    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $tcpClient.BeginConnect($host_, $port, $null, $null)
        $wait = $asyncResult.AsyncWaitHandle.WaitOne(5000, $false)

        if ($wait -and $tcpClient.Connected) {
            $tcpClient.Close()
            Write-Success (Get-Msg "server_reachable")
        }
        else {
            $tcpClient.Close()
            Write-Warn "$(Get-Msg 'cannot_reach') ${host_}:$port"
            if (-not (Read-YesNo -Prompt (Get-Msg "continue_anyway") -Default $false)) {
                exit 1
            }
        }
    }
    catch {
        Write-Warn "$(Get-Msg 'connection_failed'): $_"
        if (-not (Read-YesNo -Prompt (Get-Msg "continue_anyway") -Default $false)) {
            exit 1
        }
    }
}

# =============================================================================
# Installation Functions
# =============================================================================

# Check if agent is already installed and offer upgrade
function Test-ExistingAgent {
    $binaryPath = Join-Path $Script:InstallDir $Script:BinaryName
    $configPath = Join-Path $Script:ConfigDir "nanolink.yaml"
    
    # Check if binary exists
    if (-not (Test-Path $binaryPath)) {
        return $false  # No existing installation
    }
    
    Write-Step (Get-Msg "existing_detected")
    Write-Host ""
    
    # Get current version if possible
    $currentVersion = Get-Msg "unknown"
    try {
        $versionOutput = & $binaryPath --version 2>$null
        if ($versionOutput) {
            $currentVersion = $versionOutput | Select-Object -First 1
        }
    }
    catch {}
    
    Write-Info "$(Get-Msg 'installed_version'): $currentVersion"
    Write-Info "$(Get-Msg 'script_version'): $Script:VERSION"
    
    # Check if service is running
    $service = Get-Service -Name $Script:ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -eq "Running") {
            Write-Success (Get-Msg "service_running")
        }
        else {
            Write-Warn "$(Get-Msg 'service_stopped') ($($service.Status))"
        }
    }
    
    # Check if config exists
    if (Test-Path $configPath) {
        Write-Info "$(Get-Msg 'config_exists'): $configPath"
    }
    
    Write-Host ""
    Write-Host (Get-Msg "what_to_do") -ForegroundColor White
    $options = @(
        (Get-Msg "opt_update"),
        (Get-Msg "opt_manage"),
        (Get-Msg "opt_fresh"),
        (Get-Msg "opt_cancel")
    )
    $action = Read-Choice -Prompt (Get-Msg "select_action") -Options $options
    
    switch ($action) {
        0 {
            # Update
            $Script:UpdateMode = $true
            $Script:SkipConfig = $true

            # Ask if user wants to update server config
            Write-Host ""
            $configOptions = @(
                (Get-Msg "skip_config"),
                (Get-Msg "update_config")
            )
            $configAction = Read-Choice -Prompt (Get-Msg "update_config_choice") -Options $configOptions

            if ($configAction -eq 1) {
                $Script:SkipConfig = $false
            }

            if ($service -and $service.Status -eq "Running") {
                Write-Info (Get-Msg "stopping_service")
                Stop-Service -Name $Script:ServiceName -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Write-Success (Get-Msg "service_stopped_ok")
            }
            return $true
        }
        1 {
            # Manage
            Show-ManageMenu
            exit 0
        }
        2 {
            # Fresh install
            Write-Warn (Get-Msg "warn_overwrite")
            if (-not (Read-YesNo -Prompt (Get-Msg "are_you_sure") -Default $false)) {
                Write-Info (Get-Msg "cancelled")
                exit 0
            }
            if ($service -and $service.Status -eq "Running") {
                Write-Info (Get-Msg "stopping_service")
                Stop-Service -Name $Script:ServiceName -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Write-Success (Get-Msg "service_stopped_ok")
            }
            return $true
        }
        3 {
            # Cancel
            Write-Info (Get-Msg "cancelled")
            exit 0
        }
    }
    return $true
}
function Stop-ExistingService {
    if (Get-Service -Name $Script:ServiceName -ErrorAction SilentlyContinue) {
        Write-Info (Get-Msg "stopping_existing_service")
        Stop-Service -Name $Script:ServiceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

function Remove-ExistingService {
    if (Get-Service -Name $Script:ServiceName -ErrorAction SilentlyContinue) {
        Write-Info (Get-Msg "removing_existing_service")
        sc.exe delete $Script:ServiceName | Out-Null
        Start-Sleep -Seconds 2
    }
}

function New-Directories {
    Write-Step (Get-Msg "creating_dirs")

    $dirs = @($Script:InstallDir, $Script:ConfigDir, $Script:LogDir)
    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    Write-Success (Get-Msg "dirs_created")
}

function Get-Binary {
    Write-Step (Get-Msg "downloading")

    $arch = Get-AgentArchitecture
    $downloadUrl = "https://github.com/$Script:GitHubRepo/releases/latest/download/nanolink-agent-windows-$arch.exe"
    $binaryPath = Join-Path $Script:InstallDir $Script:BinaryName

    Write-Info "URL: $downloadUrl"

    try {
        # Show progress
        $ProgressPreference = 'Continue'
        Invoke-WebRequest -Uri $downloadUrl -OutFile $binaryPath -UseBasicParsing
        Write-Success (Get-Msg "download_success")
    }
    catch {
        Write-Err "$(Get-Msg 'download_failed'): $_"
        exit 1
    }
}

function New-Configuration {
    Write-Step (Get-Msg "generating_config")

    $configPath = Join-Path $Script:ConfigDir "nanolink.yaml"

    # Backup existing config
    if (Test-Path $configPath) {
        $backup = "$configPath.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item $configPath $backup
        Write-Warn "$(Get-Msg 'config_backed_up'): $backup"
    }

    # Generate config
    $hostnameSection = if ($Script:HostnameOverride) {
        "  hostname: `"$($Script:HostnameOverride)`""
    }
    else {
        "  # hostname: `"custom-hostname`""
    }

    $shellTokenSection = if ($Script:ShellEnabled) {
        "  super_token: `"$($Script:ShellSuperToken)`""
    }
    else {
        "  # super_token: `"your_super_token`""
    }

    $tlsConfigLines = @()
    if ($Script:TlsCaCert) {
        $tlsConfigLines += "    tls_ca_cert: '$($Script:TlsCaCert.Replace("'", "''"))'"
    }
    if ($Script:TlsServerName) {
        $tlsConfigLines += "    tls_server_name: '$($Script:TlsServerName.Replace("'", "''"))'"
    }
    if ($Script:TlsClientCert) {
        $tlsConfigLines += "    tls_client_cert: '$($Script:TlsClientCert.Replace("'", "''"))'"
    }
    if ($Script:TlsClientKey) {
        $tlsConfigLines += "    tls_client_key: '$($Script:TlsClientKey.Replace("'", "''"))'"
    }
    $tlsConfigSection = $tlsConfigLines -join "`r`n"

    $config = @"
# NanoLink Agent Configuration
# Generated on $(Get-Date)

agent:
$hostnameSection
  heartbeat_interval: 30
  reconnect_delay: 5
  max_reconnect_delay: 300

servers:
  - host: "$(($Script:ServerUrl -split ':')[0])"
    port: $(if ($Script:ServerUrl -match ':(\d+)$') { $Matches[1] } else { 39100 })
    tls_enabled: $($Script:TlsEnabled.ToString().ToLower())
    token: "$Script:AuthToken"
    permission: $Script:PermissionLevel
    tls_verify: $($Script:TlsVerify.ToString().ToLower())
$tlsConfigSection

collector:
  cpu_interval_ms: 1000
  disk_interval_ms: 3000
  network_interval_ms: 1000
  process_interval_ms: 5000
  disk_space_interval_ms: 30000
  enable_disk_io: true
  enable_network: true
  enable_per_core_cpu: true

buffer:
  capacity: 600

shell:
  enabled: $($Script:ShellEnabled.ToString().ToLower())
$shellTokenSection
  timeout_seconds: 30
  whitelist:
    - pattern: "Get-Process"
      description: "List processes"
    - pattern: "Get-Service"
      description: "List services"
    - pattern: "Get-EventLog *"
      description: "View event logs"
  blacklist:
    - "Remove-Item -Recurse -Force"
    - "Format-Volume"
    - "Clear-Disk"
  require_confirmation:
    - pattern: "Restart-Computer"
    - pattern: "Stop-Computer"

management:
  enabled: true
  port: 9101

logging:
  level: info
  audit_enabled: true
  audit_file: "$($Script:LogDir -replace '\\', '\\')\audit.log"
"@

    Set-Content -Path $configPath -Value $config -Encoding UTF8
    Write-Success "$(Get-Msg 'config_saved') $configPath"
}

function Install-Service {
    Write-Step (Get-Msg "installing_service")

    $binaryPath = Join-Path $Script:InstallDir $Script:BinaryName
    $configPath = Join-Path $Script:ConfigDir "nanolink.yaml"

    # Create the service
    $params = @{
        Name           = $Script:ServiceName
        BinaryPathName = "`"$binaryPath`" -c `"$configPath`""
        DisplayName    = $Script:ServiceDisplayName
        Description    = "NanoLink lightweight server monitoring agent"
        StartupType    = "Automatic"
    }

    New-Service @params | Out-Null

    # Configure service recovery (restart on failure)
    # First failure: restart after 5 seconds
    # Second failure: restart after 10 seconds
    # Subsequent failures: restart after 30 seconds
    # Reset failure count after 1 day (86400 seconds)
    sc.exe failure $Script:ServiceName reset=86400 actions=restart/5000/restart/10000/restart/30000 | Out-Null

    # Configure service to restart on crash
    sc.exe failureflag $Script:ServiceName 1 | Out-Null

    Write-Success (Get-Msg "service_installed_recovery")
}

function Start-InstalledService {
    Write-Step (Get-Msg "starting_service")

    Start-Service -Name $Script:ServiceName
    Start-Sleep -Seconds 3

    $service = Get-Service -Name $Script:ServiceName
    if ($service.Status -eq "Running") {
        Write-Success (Get-Msg "service_started")
    }
    else {
        Write-Err (Get-Msg "start_failed")
        Write-Host ""
        Write-Host "$(Get-Msg 'check_logs'): $Script:LogDir" -ForegroundColor Yellow
        Write-Host "$(Get-Msg 'event_viewer'): eventvwr.msc -> Windows Logs -> Application" -ForegroundColor Yellow
        exit 1
    }
}

function Test-Installation {
    Write-Step (Get-Msg "verifying")

    $checks = @{
        (Get-Msg "binary_installed")     = Test-Path (Join-Path $Script:InstallDir $Script:BinaryName)
        (Get-Msg "config_exists_check") = Test-Path (Join-Path $Script:ConfigDir "nanolink.yaml")
        (Get-Msg "service_installed_check") = $null -ne (Get-Service -Name $Script:ServiceName -ErrorAction SilentlyContinue)
        (Get-Msg "service_running_check") = (Get-Service -Name $Script:ServiceName -ErrorAction SilentlyContinue).Status -eq "Running"
    }

    $passed = 0
    foreach ($check in $checks.GetEnumerator()) {
        if ($check.Value) {
            Write-Host "  ✓ $($check.Key)" -ForegroundColor Green
            $passed++
        }
        else {
            Write-Host "  ✗ $($check.Key)" -ForegroundColor Red
        }
    }

    Write-Host ""
    if ($passed -eq $checks.Count) {
        Write-Success (Get-Msg "all_passed")
    }
    else {
        Write-Warn "$passed/$($checks.Count) $(Get-Msg 'checks_passed')"
    }
}

function Write-Summary {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              $(Get-Msg 'install_complete')" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "$(Get-Msg 'install_details'):" -ForegroundColor White
    Write-Host "  $(Get-Msg 'binary'):     $Script:InstallDir\$Script:BinaryName" -ForegroundColor Yellow
    Write-Host "  $(Get-Msg 'config'):     $Script:ConfigDir\nanolink.yaml" -ForegroundColor Yellow
    Write-Host "  $(Get-Msg 'logs'):       $Script:LogDir\" -ForegroundColor Yellow
    Write-Host "  $(Get-Msg 'server'):     $Script:ServerUrl" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "$(Get-Msg 'service_management'):" -ForegroundColor White
    Write-Host "  $(Get-Msg 'status'):     Get-Service $Script:ServiceName" -ForegroundColor Yellow
    Write-Host "  $(Get-Msg 'logs'):       Get-Content $Script:LogDir\*.log -Tail 50" -ForegroundColor Yellow
    Write-Host "  $(Get-Msg 'restart'):    Restart-Service $Script:ServiceName" -ForegroundColor Yellow
    Write-Host "  $(Get-Msg 'stop'):       Stop-Service $Script:ServiceName" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "$(Get-Msg 'uninstall'):" -ForegroundColor White
    Write-Host "  irm https://raw.githubusercontent.com/$Script:GitHubRepo/main/agent/scripts/uninstall.ps1 | iex" -ForegroundColor Yellow
    Write-Host ""
}

# =============================================================================
# Server Management Functions
# =============================================================================
function Add-ServerToConfig {
    $configPath = Join-Path $Script:ConfigDir "nanolink.yaml"
    $agentPath = Join-Path $Script:InstallDir $Script:BinaryName
    $serverUrl = if ($Script:Url) { $Script:Url } else { $Url }
    $serverToken = if ($Script:Token) { $Script:Token } else { $Token }

    if (-not (Test-Path $configPath)) {
        Write-Err "$(Get-Msg 'config_not_found'): $configPath"
        Write-Err (Get-Msg "fresh_install_first")
        exit 1
    }

    if (-not (Test-Path -LiteralPath $agentPath -PathType Leaf)) {
        Write-Err "$(Get-Msg 'agent_binary_not_found'): $agentPath"
        exit 1
    }

    $addArguments = @(
        "--config", $configPath, "server", "add",
        "--host", $serverUrl,
        "--token", $serverToken,
        "--permission", $Permission.ToString(),
        "--tls-enabled", $Script:TlsEnabled.ToString().ToLowerInvariant(),
        "--tls-verify", "true"
    )
    if ($Script:TlsCaCert) { $addArguments += @("--tls-ca-cert", $Script:TlsCaCert) }
    if ($Script:TlsServerName) { $addArguments += @("--tls-server-name", $Script:TlsServerName) }
    if ($Script:TlsClientCert) { $addArguments += @("--tls-client-cert", $Script:TlsClientCert) }
    if ($Script:TlsClientKey) { $addArguments += @("--tls-client-key", $Script:TlsClientKey) }

    & $agentPath @addArguments
    if ($LASTEXITCODE -ne 0) {
        Write-Err "$(Get-Msg 'server_add_failed'): $serverUrl"
        exit $LASTEXITCODE
    }

    Write-Success "$(Get-Msg 'server_added'): $serverUrl"
    Write-Info "$(Get-Msg 'restart_to_apply'): Restart-Service $Script:ServiceName"
}

function Remove-ServerFromConfig {
    $configPath = Join-Path $Script:ConfigDir "nanolink.yaml"

    if (-not (Test-Path $configPath)) {
        Write-Err "$(Get-Msg 'config_not_found'): $configPath"
        exit 1
    }

    # Read existing config
    $content = Get-Content $configPath -Raw

    # Check if server exists
    if (-not ($content -match [regex]::Escape("url: `"$Url`""))) {
        Write-Err "$(Get-Msg 'server_not_found'): $Url"
        exit 1
    }

    # Backup config
    $backup = "$configPath.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item $configPath $backup

    # Remove server entry (simplified - removes block starting with the URL)
    $content = $content -replace "(?m)^\s+-\s+url:\s+`"$([regex]::Escape($Url))`".*?(?=^\s+-\s+url:|^\w+:|$)", ""
    Set-Content -Path $configPath -Value $content -Encoding UTF8

    Write-Success "$(Get-Msg 'server_removed'): $Url"

    # Try to notify via management API
    try {
        $encodedUrl = [System.Web.HttpUtility]::UrlEncode($Url)
        $response = Invoke-RestMethod -Uri "http://localhost:9101/api/servers?url=$encodedUrl" -Method Delete -ErrorAction SilentlyContinue
        if ($response.success) {
            Write-Success (Get-Msg "server_removed_hot_reload")
        }
    }
    catch {
        Write-Info "$(Get-Msg 'restart_to_apply'): Restart-Service $Script:ServiceName"
    }
}

function Get-ConfigFromServer {
    param([string]$ApiUrl)

    Write-Info "$(Get-Msg 'fetching_config'): $ApiUrl"

    try {
        $response = Invoke-RestMethod -Uri $ApiUrl -Method Get
        $Script:ServerUrl = $response.serverUrl
        $Script:AuthToken = $response.token
        $Script:PermissionLevel = if ($response.permission) { $response.permission } else { 0 }
        $Script:TlsEnabled = if ($null -ne $response.tlsVerify) { $response.tlsVerify } else { $true }
        $Script:TlsVerify = $true

        if ([string]::IsNullOrEmpty($Script:ServerUrl) -or [string]::IsNullOrEmpty($Script:AuthToken)) {
            Write-Err (Get-Msg "invalid_config_response")
            exit 1
        }

        Write-Success (Get-Msg "config_fetched")
        Write-Info "  URL: $Script:ServerUrl"
        Write-Info "  $(Get-Msg 'permission'): $Script:PermissionLevel"
    }
    catch {
        Write-Err "$(Get-Msg 'fetch_config_failed'): $_"
        exit 1
    }
}

function Show-Help {
    Write-Host (Get-Msg "help_title")
    Write-Host ""
    Write-Host "$(Get-Msg 'usage'): .\install.ps1 [options]"
    Write-Host ""
    Write-Host "$(Get-Msg 'install_options'):"
    Write-Host "  -Silent           $(Get-Msg 'silent_mode')"
    Write-Host "  -Url URL          $(Get-Msg 'url_option')"
    Write-Host "  -Token TOKEN      $(Get-Msg 'token_option')"
    Write-Host "  -Permission N     $(Get-Msg 'permission_option')"
    Write-Host "  -NoTls            $(Get-Msg 'no_tls_option')"
    Write-Host "  -TlsCaCert PATH   $(Get-Msg 'tls_ca_option')"
    Write-Host "  -TlsServerName N  $(Get-Msg 'tls_server_name_option')"
    Write-Host "  -TlsClientCert P  $(Get-Msg 'tls_client_cert_option')"
    Write-Host "  -TlsClientKey P   $(Get-Msg 'tls_client_key_option')"
    Write-Host "  -NoTlsVerify      $(Get-Msg 'no_tls_verify_option')"
    Write-Host "  -Hostname NAME    $(Get-Msg 'hostname_option')"
    Write-Host "  -ShellEnabled     $(Get-Msg 'shell_enabled_option')"
    Write-Host "  -ShellToken TOKEN $(Get-Msg 'shell_token_option')"
    Write-Host ""
    Write-Host "$(Get-Msg 'server_mgmt'):"
    Write-Host "  -AddServer        $(Get-Msg 'add_server_option')"
    Write-Host "  -RemoveServer     $(Get-Msg 'remove_server_option')"
    Write-Host "  -FetchConfig URL  $(Get-Msg 'fetch_config_option')"
    Write-Host ""
    Write-Host "$(Get-Msg 'management'):"
    Write-Host "  -Manage           $(Get-Msg 'manage_option')"
    Write-Host "  -Lang LANG        $(Get-Msg 'lang_option')"
    Write-Host "  -Help             $(Get-Msg 'help_option')"
    Write-Host ""
    Write-Host "$(Get-Msg 'examples'):"
    Write-Host "  # $(Get-Msg 'interactive_install')"
    Write-Host "  .\install.ps1"
    Write-Host ""
    Write-Host "  # $(Get-Msg 'silent_install')"
    Write-Host '  .\install.ps1 -Silent -Url "server.example.com:39100" -Token "your_token"'
    Write-Host ""
    Write-Host "  # $(Get-Msg 'add_server_example')"
    Write-Host '  .\install.ps1 -AddServer -Url "second.example.com:39100" -Token "yyy"'
    Write-Host ""
    Write-Host "  # $(Get-Msg 'open_manage')"
    Write-Host "  .\install.ps1 -Manage"
    Write-Host ""
    Write-Host "  # $(Get-Msg 'remove_server_example')"
    Write-Host '  .\install.ps1 -RemoveServer -Url "old.example.com:39100"'
    Write-Host ""
    Write-Host "  # $(Get-Msg 'fetch_config_example')"
    Write-Host '  .\install.ps1 -FetchConfig "http://monitor.example.com:8080/api/config/generate"'
}

# =============================================================================
# Management Mode Functions
# =============================================================================
function Show-AgentStatus {
    Write-Step (Get-Msg "agent_status")
    
    $service = Get-Service -Name $Script:ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -eq "Running") {
            Write-Success "$(Get-Msg 'service_status'): $(Get-Msg 'running')"
        }
        else {
            Write-Warn "$(Get-Msg 'service_status'): $($service.Status)"
        }
        Write-Host ""
        Write-Host "$(Get-Msg 'configuration'):" -ForegroundColor White
        $service | Format-List Name, DisplayName, Status, StartType
    }
    else {
        Write-Warn "$(Get-Msg 'service_stopped')"
    }
    
    Write-Host "$(Get-Msg 'configuration'): $Script:ConfigDir\nanolink.yaml" -ForegroundColor Cyan
    Write-Host "$(Get-Msg 'logs'): $Script:LogDir\" -ForegroundColor Cyan
}

function Show-Servers {
    Write-Step (Get-Msg "configured_servers")
    
    $configPath = Join-Path $Script:ConfigDir "nanolink.yaml"
    if (-not (Test-Path $configPath)) {
        Write-Err (Get-Msg "config_not_found")
        return
    }
    
    Write-Host ""
    $content = Get-Content $configPath -Raw
    # Simple pattern match for servers section
    if ($content -match "servers:[\s\S]*?(?=\n\w+:|$)") {
        Write-Host $Matches[0] -ForegroundColor Yellow
    }
    else {
        Write-Host (Get-Msg "no_servers") -ForegroundColor Yellow
    }
}

function Edit-MetricsConfig {
    Write-Step (Get-Msg "metrics_config")
    
    $configPath = Join-Path $Script:ConfigDir "nanolink.yaml"
    if (-not (Test-Path $configPath)) {
        Write-Err (Get-Msg "config_not_found")
        return
    }
    
    Write-Host ""
    Write-Host "$(Get-Msg 'current_settings'):" -ForegroundColor White
    $content = Get-Content $configPath -Raw
    if ($content -match "collector:[\s\S]*?(?=\n\w+:|$)") {
        Write-Host $Matches[0] -ForegroundColor Yellow
    }
    
    Write-Host ""
    if (Read-YesNo -Prompt (Get-Msg "modify_intervals") -Default $false) {
        $cpuInterval = Read-PromptValue -Prompt (Get-Msg "cpu_interval") -Default "1000"
        $diskInterval = Read-PromptValue -Prompt (Get-Msg "disk_interval") -Default "3000"
        $networkInterval = Read-PromptValue -Prompt (Get-Msg "network_interval") -Default "1000"
        
        # Backup config
        $backup = "$configPath.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item $configPath $backup
        
        # Update config
        $content = $content -replace "cpu_interval_ms:\s*\d+", "cpu_interval_ms: $cpuInterval"
        $content = $content -replace "disk_interval_ms:\s*\d+", "disk_interval_ms: $diskInterval"
        $content = $content -replace "network_interval_ms:\s*\d+", "network_interval_ms: $networkInterval"
        Set-Content -Path $configPath -Value $content -Encoding UTF8
        
        Write-Success (Get-Msg "intervals_updated")
        
        if (Read-YesNo -Prompt (Get-Msg "reload_now") -Default $true) {
            Invoke-ConfigReload
        }
    }
}

function Invoke-ConfigReload {
    Write-Step (Get-Msg "reload_config")
    
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:9101/api/reload" -Method Post -ErrorAction SilentlyContinue
        if ($response.success) {
            Write-Success (Get-Msg "reload_success")
        }
        else {
            Write-Warn (Get-Msg "reload_failed")
            Restart-Service -Name $Script:ServiceName
            Write-Success (Get-Msg "service_restarted")
        }
    }
    catch {
        Write-Warn (Get-Msg "reload_unavailable")
        Restart-Service -Name $Script:ServiceName
        Write-Success (Get-Msg "service_restarted")
    }
}

function Show-Logs {
    Write-Step (Get-Msg "view_logs")
    
    $logFile = Join-Path $Script:LogDir "agent.log"
    if (-not (Test-Path $logFile)) {
        Write-Warn "$(Get-Msg 'log_file_not_found'): $logFile"
        return
    }
    
    Write-Host ""
    Write-Host "$(Get-Msg 'last_lines'):" -ForegroundColor White
    Write-Host "────────────────────────────────────────" -ForegroundColor Gray
    Get-Content $logFile -Tail 30
    Write-Host "────────────────────────────────────────" -ForegroundColor Gray
    
    Write-Host ""
    if (Read-YesNo -Prompt (Get-Msg "follow_logs") -Default $false) {
        Write-Host (Get-Msg "press_ctrl_c") -ForegroundColor Yellow
        Get-Content $logFile -Wait -Tail 10
    }
}

function Invoke-Uninstall {
    Write-Step (Get-Msg "uninstall_title")
    
    Write-Host ""
    Write-Warn (Get-Msg "uninstall_warn")
    Write-Host ""
    
    if (-not (Read-YesNo -Prompt (Get-Msg "confirm_uninstall") -Default $false)) {
        Write-Info (Get-Msg "uninstall_cancelled")
        return
    }
    
    # Stop and remove service
    $service = Get-Service -Name $Script:ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        Stop-Service -Name $Script:ServiceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        sc.exe delete $Script:ServiceName | Out-Null
        Write-Success (Get-Msg "service_removed")
    }
    
    # Remove binary
    if (Test-Path $Script:InstallDir) {
        Remove-Item -Path $Script:InstallDir -Recurse -Force
        Write-Success (Get-Msg "binary_removed")
    }
    
    # Ask about data
    Write-Host ""
    if (Read-YesNo -Prompt (Get-Msg "remove_data") -Default $false) {
        if (Test-Path $Script:ConfigDir) {
            Remove-Item -Path $Script:ConfigDir -Recurse -Force
            Write-Success (Get-Msg "data_removed")
        }
    }
    else {
        Write-Info "$(Get-Msg 'data_preserved'): $Script:ConfigDir"
    }
    
    Write-Host ""
    Write-Success (Get-Msg "uninstall_complete")
}

function Show-ManageMenu {
    Initialize-Language
    
    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host ("║              {0,-47} ║" -f (Get-Msg "mgmt_menu_title")) -ForegroundColor Cyan
        Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        
        Write-Host "$(Get-Msg 'server_management'):" -ForegroundColor White
        Write-Host "  1) $(Get-Msg 'add_server')" -ForegroundColor Cyan
        Write-Host "  2) $(Get-Msg 'list_servers')" -ForegroundColor Cyan
        Write-Host "  3) $(Get-Msg 'remove_server')" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "$(Get-Msg 'metrics_collection'):" -ForegroundColor White
        Write-Host "  4) $(Get-Msg 'config_metrics')" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "$(Get-Msg 'service_control'):" -ForegroundColor White
        Write-Host "  5) $(Get-Msg 'show_status')" -ForegroundColor Cyan
        Write-Host "  6) $(Get-Msg 'start_agent')" -ForegroundColor Cyan
        Write-Host "  7) $(Get-Msg 'stop_agent')" -ForegroundColor Cyan
        Write-Host "  8) $(Get-Msg 'restart_agent')" -ForegroundColor Cyan
        Write-Host "  r) $(Get-Msg 'reload_config')" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "$(Get-Msg 'maintenance'):" -ForegroundColor White
        Write-Host "  l) $(Get-Msg 'view_logs_menu')" -ForegroundColor Cyan
        Write-Host "  u) $(Get-Msg 'uninstall_agent')" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  0) $(Get-Msg 'exit')" -ForegroundColor Cyan
        Write-Host ""
        
        $choice = Read-Host (Get-Msg "select_option")
        Write-Host ""
        
        switch ($choice) {
            "1" {
                # Interactive add server
                Write-Step (Get-Msg "add_server")
                $serverUrl = Read-PromptValue -Prompt (Get-Msg "server_url_prompt") -Required
                $serverToken = Read-PromptValue -Prompt (Get-Msg "token_prompt") -Required
                $Script:Url = $serverUrl
                $Script:Token = $serverToken
                Add-ServerToConfig
            }
            "2" { Show-Servers }
            "3" {
                Show-Servers
                $serverUrl = Read-PromptValue -Prompt (Get-Msg "server_url_prompt")
                if (-not [string]::IsNullOrEmpty($serverUrl)) {
                    $Script:Url = $serverUrl
                    Remove-ServerFromConfig
                }
            }
            "4" { Edit-MetricsConfig }
            "5" { Show-AgentStatus }
            "6" {
                Write-Step (Get-Msg "starting_service")
                Start-Service -Name $Script:ServiceName
                Write-Success (Get-Msg "service_started")
            }
            "7" {
                Write-Step (Get-Msg "stop_agent")
                Stop-Service -Name $Script:ServiceName -Force
                Write-Success (Get-Msg "service_stopped_ok")
            }
            "8" {
                Write-Step (Get-Msg "restart_agent")
                Restart-Service -Name $Script:ServiceName
                Write-Success (Get-Msg "service_restarted")
            }
            { $_ -in "r", "R" } { Invoke-ConfigReload }
            { $_ -in "l", "L" } { Show-Logs }
            { $_ -in "u", "U" } { Invoke-Uninstall; exit 0 }
            { $_ -in "0", "q", "Q" } { Write-Host (Get-Msg "goodbye"); return }
            default { Write-Warn "$(Get-Msg 'invalid_option'): $choice" }
        }
        
        Write-Host ""
        Read-Host (Get-Msg "press_enter")
    }
}

# =============================================================================
# Main
# =============================================================================
function Main {
    # Initialize language detection
    Initialize-Language
    Test-TlsParameters
    
    if ($Help) {
        Show-Help
        return
    }

    # Handle fetch-config mode first
    if (-not [string]::IsNullOrEmpty($FetchConfig)) {
        Get-ConfigFromServer -ApiUrl $FetchConfig
        $Silent = $true
    }

    # Handle add-server mode
    if ($AddServer) {
        if ([string]::IsNullOrEmpty($Url) -or [string]::IsNullOrEmpty($Token)) {
            Write-Err (Get-Msg "add_mode_requires")
            exit 1
        }
        Add-ServerToConfig
        return
    }

    # Handle remove-server mode
    if ($RemoveServer) {
        if ([string]::IsNullOrEmpty($Url)) {
            Write-Err (Get-Msg "remove_mode_requires")
            exit 1
        }
        Remove-ServerFromConfig
        return
    }

    # Handle manage mode
    if ($Manage) {
        Show-ManageMenu
        return
    }

    # Validate silent mode
    if ($Silent) {
        if ([string]::IsNullOrEmpty($Url) -or [string]::IsNullOrEmpty($Token)) {
            if ([string]::IsNullOrEmpty($Script:ServerUrl)) {
                Write-Err (Get-Msg "silent_requires_credentials")
                exit 1
            }
        }
        else {
            $Script:ServerUrl = $Url
            $Script:AuthToken = $Token
            $Script:PermissionLevel = $Permission
            $Script:TlsEnabled = -not $NoTls
            $Script:TlsVerify = $true
            $Script:TlsCaCert = $TlsCaCert
            $Script:TlsServerName = $TlsServerName
            $Script:TlsClientCert = $TlsClientCert
            $Script:TlsClientKey = $TlsClientKey
            $Script:HostnameOverride = $Hostname
            $Script:ShellEnabled = $ShellEnabled.IsPresent
            $Script:ShellSuperToken = $ShellToken
        }
    }
    else {
        Write-Banner
    }

    $arch = Get-AgentArchitecture
    $displayArch = if ($arch -eq 'aarch64') { 'ARM64' } else { 'x64' }
    Write-Info "$(Get-Msg 'detected'): Windows $([Environment]::OSVersion.Version) ($displayArch)"

    # Check for existing installation (only in interactive mode)
    $Script:UpdateMode = $false
    $Script:SkipConfig = $true  # Default to skip config on update
    if (-not $Silent) {
        Test-ExistingAgent | Out-Null
    }

    # Interactive configuration (skip if updating with SkipConfig=true)
    if (-not $Silent) {
        if (-not $Script:UpdateMode) {
            # Fresh install - always configure
            Get-InteractiveConfig
        }
        elseif (-not $Script:SkipConfig) {
            # Update mode but user chose to update config
            Get-InteractiveConfig
        }
    }

    # Installation steps
    Stop-ExistingService
    Remove-ExistingService
    New-Directories
    Get-Binary
    
    # Generate config based on mode
    if (-not $Script:UpdateMode) {
        # Fresh install - always generate config
        New-Configuration
    }
    elseif (-not $Script:SkipConfig) {
        # Update mode but user chose to update config
        New-Configuration
    }
    else {
        # Update mode with skip config - keep existing
        Write-Info (Get-Msg "keeping_config")
    }
    
    Install-Service
    Start-InstalledService
    Test-Installation
    
    if ($Script:UpdateMode) {
        Write-Success (Get-Msg "update_success")
    }
    Write-Summary
}

Main
