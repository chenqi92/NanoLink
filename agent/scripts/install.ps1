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
    Disable TLS certificate verification

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
$Script:VERSION = "0.2.7"
$Script:ServiceName = "NanoLinkAgent"
$Script:ServiceDisplayName = "NanoLink Monitoring Agent"
$Script:InstallDir = "C:\Program Files\NanoLink"
$Script:ConfigDir = "C:\ProgramData\NanoLink"
$Script:LogDir = "C:\ProgramData\NanoLink\logs"
$Script:BinaryName = "nanolink-agent.exe"
$Script:GitHubRepo = "chenqi92/NanoLink"

# =============================================================================
# Internationalization (i18n)
# =============================================================================
$Script:ScriptLang = ""

# Message dictionaries
$Script:EnMsgs = @{
    # General
    "banner_subtitle"     = "Lightweight Server Monitoring Agent"
    "detected"            = "Detected"
    
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
    "view_logs"           = "View Logs"
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
}

$Script:ZhMsgs = @{
    # General
    "banner_subtitle"     = "轻量级服务器监控代理"
    "detected"            = "检测到"
    
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
    "view_logs"           = "查看日志"
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
    ║              Lightweight Server Monitoring Agent              ║
    ║                        Version $Script:VERSION                           ║
    ║                                                               ║
    ╚═══════════════════════════════════════════════════════════════╝

"@
    Write-Host $banner -ForegroundColor Cyan
}

function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Blue }
function Write-Success { param([string]$Message) Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Err { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }
function Write-Step { param([string]$Message) Write-Host "`n▶ $Message" -ForegroundColor Cyan }

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
                Write-Warn "This field is required"
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
    return $response -match "^[Yy]"
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
        $choice = Read-Host -Prompt "Select [1-$($Options.Count)]"
        if ($choice -match '^\d+$') {
            $num = [int]$choice
            if ($num -ge 1 -and $num -le $Options.Count) {
                return $num - 1
            }
        }
        Write-Warn "Invalid choice, please try again"
    }
}

# =============================================================================
# Interactive Configuration
# =============================================================================
function Get-InteractiveConfig {
    Write-Step "Server Configuration"
    Write-Host ""

    # Server URL (now host:port format)
    while ($true) {
        $Script:ServerUrl = Read-PromptValue -Prompt "Server address (e.g., monitor.example.com:39100)" -Required
        # Validate host:port format
        if ($Script:ServerUrl -notmatch "^[a-zA-Z0-9]([a-zA-Z0-9.\-]*[a-zA-Z0-9])?(:[0-9]+)?$") {
            Write-Warn "Invalid format. Use host:port (e.g., server.example.com:39100)"
            continue
        }
        break
    }

    # Token
    $Script:AuthToken = Read-PromptValue -Prompt "Authentication Token" -Required

    # Permission level
    Write-Host ""
    $permOptions = @(
        "Read Only (monitoring only)",
        "Basic Write (logs, temp files)",
        "Service Control (restart services)",
        "System Admin (full control)"
    )
    $Script:PermissionLevel = Read-Choice -Prompt "Permission Level" -Options $permOptions

    # TLS settings
    Write-Host ""
    $Script:TlsEnabled = $false
    $Script:TlsVerify = $true
    if (Read-YesNo -Prompt "Enable TLS?" -Default $false) {
        $Script:TlsEnabled = $true
        if (-not (Read-YesNo -Prompt "Verify TLS certificate?" -Default $true)) {
            $Script:TlsVerify = $false
            Write-Warn "TLS verification disabled - only use for testing!"
        }
    }

    # Test connection
    Write-Host ""
    if (Read-YesNo -Prompt "Test server connection before installing?" -Default $true) {
        Test-ServerConnection
    }

    # Hostname override
    Write-Host ""
    $Script:HostnameOverride = ""
    $systemHostname = [System.Net.Dns]::GetHostName()
    if (-not (Read-YesNo -Prompt "Use system hostname ($systemHostname)?" -Default $true)) {
        $Script:HostnameOverride = Read-PromptValue -Prompt "Custom hostname"
    }

    # Shell commands
    Write-Host ""
    $Script:ShellEnabled = $false
    $Script:ShellSuperToken = ""
    if ($Script:PermissionLevel -ge 2) {
        if (Read-YesNo -Prompt "Enable shell command execution? (requires super token)" -Default $false) {
            $Script:ShellEnabled = $true
            $Script:ShellSuperToken = Read-PromptValue -Prompt "Shell Super Token (different from auth token)" -Required -Password
        }
    }
}

function Test-ServerConnection {
    Write-Step "Testing Connection"

    # Extract host and port from URL
    $uri = [System.Uri]$Script:ServerUrl
    $host_ = $uri.Host
    $port = if ($uri.Port -gt 0) { $uri.Port } else { 9100 }

    Write-Info "Testing connection to ${host_}:$port..."

    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $tcpClient.BeginConnect($host_, $port, $null, $null)
        $wait = $asyncResult.AsyncWaitHandle.WaitOne(5000, $false)

        if ($wait -and $tcpClient.Connected) {
            $tcpClient.Close()
            Write-Success "Server is reachable!"
        }
        else {
            $tcpClient.Close()
            Write-Warn "Cannot reach server at ${host_}:$port"
            if (-not (Read-YesNo -Prompt "Continue anyway?" -Default $false)) {
                exit 1
            }
        }
    }
    catch {
        Write-Warn "Connection test failed: $_"
        if (-not (Read-YesNo -Prompt "Continue anyway?" -Default $false)) {
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
    
    Write-Step "Existing Installation Detected"
    Write-Host ""
    
    # Get current version if possible
    $currentVersion = "unknown"
    try {
        $versionOutput = & $binaryPath --version 2>$null
        if ($versionOutput) {
            $currentVersion = $versionOutput | Select-Object -First 1
        }
    }
    catch {}
    
    Write-Info "Installed version: $currentVersion"
    Write-Info "Script version: $Script:VERSION"
    
    # Check if service is running
    $service = Get-Service -Name $Script:ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -eq "Running") {
            Write-Success "Agent service is currently running"
        }
        else {
            Write-Warn "Agent service is stopped ($($service.Status))"
        }
    }
    
    # Check if config exists
    if (Test-Path $configPath) {
        Write-Info "Configuration exists at: $configPath"
    }
    
    Write-Host ""
    Write-Host "What would you like to do?" -ForegroundColor White
    $options = @(
        "Update agent (download latest binary, keep config)",
        "Manage existing agent (open management menu)",
        "Fresh install (overwrite config and binary)",
        "Cancel"
    )
    $action = Read-Choice -Prompt "Select action" -Options $options
    
    switch ($action) {
        0 {
            # Update
            $Script:UpdateMode = $true
            if ($service -and $service.Status -eq "Running") {
                Write-Info "Stopping agent service before update..."
                Stop-Service -Name $Script:ServiceName -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Write-Success "Service stopped"
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
            Write-Warn "This will overwrite existing configuration!"
            if (-not (Read-YesNo -Prompt "Are you sure?" -Default $false)) {
                Write-Info "Installation cancelled"
                exit 0
            }
            if ($service -and $service.Status -eq "Running") {
                Write-Info "Stopping agent service..."
                Stop-Service -Name $Script:ServiceName -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Write-Success "Service stopped"
            }
            return $true
        }
        3 {
            # Cancel
            Write-Info "Installation cancelled"
            exit 0
        }
    }
    return $true
}
function Stop-ExistingService {
    if (Get-Service -Name $Script:ServiceName -ErrorAction SilentlyContinue) {
        Write-Info "Stopping existing service..."
        Stop-Service -Name $Script:ServiceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

function Remove-ExistingService {
    if (Get-Service -Name $Script:ServiceName -ErrorAction SilentlyContinue) {
        Write-Info "Removing existing service..."
        sc.exe delete $Script:ServiceName | Out-Null
        Start-Sleep -Seconds 2
    }
}

function New-Directories {
    Write-Step "Creating Directories"

    $dirs = @($Script:InstallDir, $Script:ConfigDir, $Script:LogDir)
    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    Write-Success "Directories created"
}

function Get-Binary {
    Write-Step "Downloading NanoLink Agent"

    $arch = if ([Environment]::Is64BitOperatingSystem) { "x86_64" } else { "x86" }
    $downloadUrl = "https://github.com/$Script:GitHubRepo/releases/latest/download/nanolink-agent-windows-$arch.exe"
    $binaryPath = Join-Path $Script:InstallDir $Script:BinaryName

    Write-Info "URL: $downloadUrl"

    try {
        # Show progress
        $ProgressPreference = 'Continue'
        Invoke-WebRequest -Uri $downloadUrl -OutFile $binaryPath -UseBasicParsing
        Write-Success "Downloaded successfully"
    }
    catch {
        Write-Err "Download failed: $_"
        exit 1
    }
}

function New-Configuration {
    Write-Step "Generating Configuration"

    $configPath = Join-Path $Script:ConfigDir "nanolink.yaml"

    # Backup existing config
    if (Test-Path $configPath) {
        $backup = "$configPath.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item $configPath $backup
        Write-Warn "Existing config backed up to: $backup"
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
    Write-Success "Configuration saved to $configPath"
}

function Install-Service {
    Write-Step "Installing Windows Service"

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

    Write-Success "Windows Service installed with auto-recovery"
}

function Start-InstalledService {
    Write-Step "Starting Service"

    Start-Service -Name $Script:ServiceName
    Start-Sleep -Seconds 3

    $service = Get-Service -Name $Script:ServiceName
    if ($service.Status -eq "Running") {
        Write-Success "Service started successfully!"
    }
    else {
        Write-Err "Service failed to start"
        Write-Host ""
        Write-Host "Check logs at: $Script:LogDir" -ForegroundColor Yellow
        Write-Host "Event Viewer: eventvwr.msc -> Windows Logs -> Application" -ForegroundColor Yellow
        exit 1
    }
}

function Test-Installation {
    Write-Step "Verifying Installation"

    $checks = @{
        "Binary installed"     = Test-Path (Join-Path $Script:InstallDir $Script:BinaryName)
        "Configuration exists" = Test-Path (Join-Path $Script:ConfigDir "nanolink.yaml")
        "Service installed"    = $null -ne (Get-Service -Name $Script:ServiceName -ErrorAction SilentlyContinue)
        "Service running"      = (Get-Service -Name $Script:ServiceName -ErrorAction SilentlyContinue).Status -eq "Running"
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
        Write-Success "All checks passed!"
    }
    else {
        Write-Warn "$passed/$($checks.Count) checks passed"
    }
}

function Write-Summary {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              Installation Complete!                           ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Installation Details:" -ForegroundColor White
    Write-Host "  Binary:     $Script:InstallDir\$Script:BinaryName" -ForegroundColor Yellow
    Write-Host "  Config:     $Script:ConfigDir\nanolink.yaml" -ForegroundColor Yellow
    Write-Host "  Logs:       $Script:LogDir\" -ForegroundColor Yellow
    Write-Host "  Server:     $Script:ServerUrl" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Service Management:" -ForegroundColor White
    Write-Host "  Status:     Get-Service $Script:ServiceName" -ForegroundColor Yellow
    Write-Host "  Logs:       Get-Content $Script:LogDir\*.log -Tail 50" -ForegroundColor Yellow
    Write-Host "  Restart:    Restart-Service $Script:ServiceName" -ForegroundColor Yellow
    Write-Host "  Stop:       Stop-Service $Script:ServiceName" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Uninstall:" -ForegroundColor White
    Write-Host "  irm https://raw.githubusercontent.com/$Script:GitHubRepo/main/agent/scripts/uninstall.ps1 | iex" -ForegroundColor Yellow
    Write-Host ""
}

# =============================================================================
# Server Management Functions
# =============================================================================
function Add-ServerToConfig {
    $configPath = Join-Path $Script:ConfigDir "nanolink.yaml"

    if (-not (Test-Path $configPath)) {
        Write-Err "Configuration file not found: $configPath"
        Write-Err "Please run a fresh installation first"
        exit 1
    }

    # Read existing config
    $content = Get-Content $configPath -Raw

    # Check if server already exists
    if ($content -match [regex]::Escape("url: `"$Url`"")) {
        Write-Err "Server $Url already exists in configuration"
        Write-Host "Use -RemoveServer first to remove it, or update manually"
        exit 1
    }

    # Backup config
    $backup = "$configPath.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item $configPath $backup

    # Add new server entry after "servers:" line
    $tlsVerify = if ($NoTlsVerify) { "false" } else { "true" }
    $newServer = @"

  - url: "$Url"
    token: "$Token"
    permission: $Permission
    tls_verify: $tlsVerify
"@

    $content = $content -replace "(servers:)", "`$1$newServer"
    Set-Content -Path $configPath -Value $content -Encoding UTF8

    Write-Success "Server $Url added to configuration"

    # Try to notify via management API
    try {
        $body = @{
            url        = $Url
            token      = $Token
            permission = $Permission
            tls_verify = -not $NoTlsVerify
        } | ConvertTo-Json

        $response = Invoke-RestMethod -Uri "http://localhost:9101/api/servers" -Method Post -Body $body -ContentType "application/json" -ErrorAction SilentlyContinue
        if ($response.success) {
            Write-Success "Server added via management API (hot-reload)"
        }
    }
    catch {
        Write-Info "Restart the agent to apply changes: Restart-Service $Script:ServiceName"
    }
}

function Remove-ServerFromConfig {
    $configPath = Join-Path $Script:ConfigDir "nanolink.yaml"

    if (-not (Test-Path $configPath)) {
        Write-Err "Configuration file not found: $configPath"
        exit 1
    }

    # Read existing config
    $content = Get-Content $configPath -Raw

    # Check if server exists
    if (-not ($content -match [regex]::Escape("url: `"$Url`""))) {
        Write-Err "Server $Url not found in configuration"
        exit 1
    }

    # Backup config
    $backup = "$configPath.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item $configPath $backup

    # Remove server entry (simplified - removes block starting with the URL)
    $content = $content -replace "(?m)^\s+-\s+url:\s+`"$([regex]::Escape($Url))`".*?(?=^\s+-\s+url:|^\w+:|$)", ""
    Set-Content -Path $configPath -Value $content -Encoding UTF8

    Write-Success "Server $Url removed from configuration"

    # Try to notify via management API
    try {
        $encodedUrl = [System.Web.HttpUtility]::UrlEncode($Url)
        $response = Invoke-RestMethod -Uri "http://localhost:9101/api/servers?url=$encodedUrl" -Method Delete -ErrorAction SilentlyContinue
        if ($response.success) {
            Write-Success "Server removed via management API (hot-reload)"
        }
    }
    catch {
        Write-Info "Restart the agent to apply changes: Restart-Service $Script:ServiceName"
    }
}

function Get-ConfigFromServer {
    param([string]$ApiUrl)

    Write-Info "Fetching configuration from: $ApiUrl"

    try {
        $response = Invoke-RestMethod -Uri $ApiUrl -Method Get
        $Script:ServerUrl = $response.serverUrl
        $Script:AuthToken = $response.token
        $Script:PermissionLevel = if ($response.permission) { $response.permission } else { 0 }
        $Script:TlsVerify = if ($null -ne $response.tlsVerify) { $response.tlsVerify } else { $true }

        if ([string]::IsNullOrEmpty($Script:ServerUrl) -or [string]::IsNullOrEmpty($Script:AuthToken)) {
            Write-Err "Invalid configuration response from server"
            exit 1
        }

        Write-Success "Configuration fetched successfully"
        Write-Info "  URL: $Script:ServerUrl"
        Write-Info "  Permission: $Script:PermissionLevel"
    }
    catch {
        Write-Err "Failed to fetch configuration: $_"
        exit 1
    }
}

function Show-Help {
    Write-Host @"
NanoLink Agent Installer for Windows

Usage: .\install.ps1 [options]

Installation Options:
  -Silent           Silent mode (no prompts)
  -Url URL          Server address (host:port)
  -Token TOKEN      Authentication token
  -Permission N     Permission level (0-3)
  -NoTlsVerify      Disable TLS verification
  -Hostname NAME    Override hostname
  -ShellEnabled     Enable shell commands
  -ShellToken TOKEN Shell super token

Server Management:
  -AddServer        Add server to existing installation
  -RemoveServer     Remove server from existing installation
  -FetchConfig URL  Fetch configuration from server API

Management:
  -Manage           Interactive management menu

  -Help             Show this help

Examples:
  # Interactive installation
  .\install.ps1

  # Silent installation
  .\install.ps1 -Silent -Url "server.example.com:39100" -Token "your_token"

  # Add additional server to existing agent
  .\install.ps1 -AddServer -Url "second.example.com:39100" -Token "yyy"

  # Open management menu
  .\install.ps1 -Manage

  # Remove a server
  .\install.ps1 -RemoveServer -Url "old.example.com:39100"

  # Fetch config from server and install
  .\install.ps1 -FetchConfig "http://monitor.example.com:8080/api/config/generate"
"@
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
    Write-Step "Configured Servers"
    
    $configPath = Join-Path $Script:ConfigDir "nanolink.yaml"
    if (-not (Test-Path $configPath)) {
        Write-Err "Configuration file not found"
        return
    }
    
    Write-Host ""
    $content = Get-Content $configPath -Raw
    # Simple pattern match for servers section
    if ($content -match "servers:[\s\S]*?(?=\n\w+:|$)") {
        Write-Host $Matches[0] -ForegroundColor Yellow
    }
    else {
        Write-Host "No servers configured" -ForegroundColor Yellow
    }
}

function Edit-MetricsConfig {
    Write-Step "Metrics Configuration"
    
    $configPath = Join-Path $Script:ConfigDir "nanolink.yaml"
    if (-not (Test-Path $configPath)) {
        Write-Err "Configuration file not found"
        return
    }
    
    Write-Host ""
    Write-Host "Current collector settings:" -ForegroundColor White
    $content = Get-Content $configPath -Raw
    if ($content -match "collector:[\s\S]*?(?=\n\w+:|$)") {
        Write-Host $Matches[0] -ForegroundColor Yellow
    }
    
    Write-Host ""
    if (Read-YesNo -Prompt "Modify collector intervals?" -Default $false) {
        $cpuInterval = Read-PromptValue -Prompt "CPU interval (ms)" -Default "1000"
        $diskInterval = Read-PromptValue -Prompt "Disk interval (ms)" -Default "3000"
        $networkInterval = Read-PromptValue -Prompt "Network interval (ms)" -Default "1000"
        
        # Backup config
        $backup = "$configPath.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item $configPath $backup
        
        # Update config
        $content = $content -replace "cpu_interval_ms:\s*\d+", "cpu_interval_ms: $cpuInterval"
        $content = $content -replace "disk_interval_ms:\s*\d+", "disk_interval_ms: $diskInterval"
        $content = $content -replace "network_interval_ms:\s*\d+", "network_interval_ms: $networkInterval"
        Set-Content -Path $configPath -Value $content -Encoding UTF8
        
        Write-Success "Collector intervals updated"
        
        if (Read-YesNo -Prompt "Reload configuration now?" -Default $true) {
            Invoke-ConfigReload
        }
    }
}

function Invoke-ConfigReload {
    Write-Step "Reloading Configuration"
    
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:9101/api/reload" -Method Post -ErrorAction SilentlyContinue
        if ($response.success) {
            Write-Success "Configuration reloaded successfully!"
        }
        else {
            Write-Warn "Hot reload failed. Restarting service..."
            Restart-Service -Name $Script:ServiceName
            Write-Success "Service restarted"
        }
    }
    catch {
        Write-Warn "Hot reload not available. Restarting service..."
        Restart-Service -Name $Script:ServiceName
        Write-Success "Service restarted"
    }
}

function Show-Logs {
    Write-Step "View Logs"
    
    $logFile = Join-Path $Script:LogDir "agent.log"
    if (-not (Test-Path $logFile)) {
        Write-Warn "Log file not found: $logFile"
        return
    }
    
    Write-Host ""
    Write-Host "Last 30 lines of agent log:" -ForegroundColor White
    Write-Host "────────────────────────────────────────" -ForegroundColor Gray
    Get-Content $logFile -Tail 30
    Write-Host "────────────────────────────────────────" -ForegroundColor Gray
    
    Write-Host ""
    if (Read-YesNo -Prompt "Follow logs in real-time?" -Default $false) {
        Write-Host "Press Ctrl+C to stop..." -ForegroundColor Yellow
        Get-Content $logFile -Wait -Tail 10
    }
}

function Invoke-Uninstall {
    Write-Step "Uninstall NanoLink Agent"
    
    Write-Host ""
    Write-Warn "This will remove the NanoLink Agent from your system."
    Write-Host ""
    
    if (-not (Read-YesNo -Prompt "Are you sure you want to uninstall?" -Default $false)) {
        Write-Info "Uninstall cancelled"
        return
    }
    
    # Stop and remove service
    $service = Get-Service -Name $Script:ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        Stop-Service -Name $Script:ServiceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        sc.exe delete $Script:ServiceName | Out-Null
        Write-Success "Service removed"
    }
    
    # Remove binary
    if (Test-Path $Script:InstallDir) {
        Remove-Item -Path $Script:InstallDir -Recurse -Force
        Write-Success "Binary removed"
    }
    
    # Ask about data
    Write-Host ""
    if (Read-YesNo -Prompt "Remove configuration and data?" -Default $false) {
        if (Test-Path $Script:ConfigDir) {
            Remove-Item -Path $Script:ConfigDir -Recurse -Force
            Write-Success "Configuration and data removed"
        }
    }
    else {
        Write-Info "Configuration and data preserved at: $Script:ConfigDir"
    }
    
    Write-Host ""
    Write-Success "NanoLink Agent has been uninstalled"
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
            Write-Err "Add server mode requires -Url and -Token parameters"
            exit 1
        }
        Add-ServerToConfig
        return
    }

    # Handle remove-server mode
    if ($RemoveServer) {
        if ([string]::IsNullOrEmpty($Url)) {
            Write-Err "Remove server mode requires -Url parameter"
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
                Write-Err "Silent mode requires -Url and -Token parameters"
                exit 1
            }
        }
        else {
            $Script:ServerUrl = $Url
            $Script:AuthToken = $Token
            $Script:PermissionLevel = $Permission
            $Script:TlsVerify = -not $NoTlsVerify
            $Script:HostnameOverride = $Hostname
            $Script:ShellEnabled = $ShellEnabled.IsPresent
            $Script:ShellSuperToken = $ShellToken
        }
    }
    else {
        Write-Banner
    }

    Write-Info "Detected: Windows $([Environment]::OSVersion.Version) ($([Environment]::Is64BitOperatingSystem ? 'x64' : 'x86'))"

    # Check for existing installation (only in interactive mode)
    $Script:UpdateMode = $false
    if (-not $Silent) {
        Test-ExistingAgent | Out-Null
    }

    # Interactive configuration (skip if updating)
    if (-not $Silent -and -not $Script:UpdateMode) {
        Get-InteractiveConfig
    }

    # Installation steps
    Stop-ExistingService
    Remove-ExistingService
    New-Directories
    Get-Binary
    
    # Only generate config if not updating (preserve existing config)
    if (-not $Script:UpdateMode) {
        New-Configuration
    }
    else {
        Write-Info "Keeping existing configuration"
    }
    
    Install-Service
    Start-InstalledService
    Test-Installation
    
    if ($Script:UpdateMode) {
        Write-Success "Agent updated successfully!"
    }
    Write-Summary
}

Main
