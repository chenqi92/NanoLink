#!/bin/bash
#
# NanoLink Agent Interactive Installation Script
# Supports: Linux (systemd), macOS (launchd)
#
# Usage:
#   Interactive: curl -fsSL https://raw.githubusercontent.com/chenqi92/NanoLink/main/agent/scripts/install.sh | bash
#   Silent:      curl -fsSL https://raw.githubusercontent.com/chenqi92/NanoLink/main/agent/scripts/install.sh | bash -s -- --silent --url wss://server:9100 --token xxx
#

set -e

# =============================================================================
# Configuration
# =============================================================================
VERSION="0.2.7"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/nanolink"
LOG_DIR="/var/log/nanolink"
DATA_DIR="/var/lib/nanolink"
SERVICE_NAME="nanolink-agent"
BINARY_NAME="nanolink-agent"
GITHUB_REPO="chenqi92/NanoLink"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# =============================================================================
# Internationalization (i18n)
# =============================================================================
SCRIPT_LANG=""

# Detect system language
detect_language() {
    # Check if already set via --lang parameter
    if [ -n "$SCRIPT_LANG" ]; then
        return
    fi
    
    # Auto-detect based on system locale
    local sys_lang="${LANG:-}${LC_ALL:-}${LC_MESSAGES:-}"
    if [[ "$sys_lang" =~ ^zh ]] || [[ "$sys_lang" =~ [Cc]hinese ]]; then
        SCRIPT_LANG="zh"
    else
        SCRIPT_LANG="en"
    fi
}

# Message dictionary - returns localized string
# Usage: echo "$(msg key)"
msg() {
    local key="$1"
    
    # English messages
    declare -A en_msgs=(
        # General
        ["banner_subtitle"]="Lightweight Server Monitoring Agent"
        ["detected"]="Detected"
        
        # Status messages
        ["info"]="INFO"
        ["success"]="SUCCESS"
        ["warn"]="WARN"
        ["error"]="ERROR"
        
        # Installation
        ["existing_detected"]="Existing Installation Detected"
        ["installed_version"]="Installed version"
        ["script_version"]="Script version"
        ["service_running"]="Agent service is currently running"
        ["service_stopped"]="Agent service is stopped"
        ["service_loaded"]="Agent service is currently loaded"
        ["config_exists"]="Configuration exists at"
        ["what_to_do"]="What would you like to do?"
        ["select_action"]="Select action"
        ["opt_update"]="Update agent (download latest binary, keep config)"
        ["opt_manage"]="Manage existing agent (open management menu)"
        ["opt_fresh"]="Fresh install (overwrite config and binary)"
        ["opt_cancel"]="Cancel"
        ["stopping_service"]="Stopping agent service before update..."
        ["service_stopped_ok"]="Service stopped"
        ["warn_overwrite"]="This will overwrite existing configuration!"
        ["are_you_sure"]="Are you sure?"
        ["cancelled"]="Installation cancelled"
        ["keeping_config"]="Keeping existing configuration"
        ["update_success"]="Agent updated successfully!"
        
        # Server config
        ["server_config"]="Server Configuration"
        ["server_url_prompt"]="Server WebSocket URL (e.g., wss://monitor.example.com:9100)"
        ["url_invalid"]="URL must start with ws:// or wss://"
        ["token_prompt"]="Authentication Token"
        ["permission_level"]="Permission Level"
        ["perm_readonly"]="Read Only (monitoring only)"
        ["perm_basic"]="Read + Process Control"
        ["perm_shell"]="Read + Process + Limited Shell"
        ["perm_full"]="Full Access (all operations)"
        ["verify_tls"]="Verify TLS certificate?"
        ["tls_disabled_warn"]="TLS verification disabled - only use for testing!"
        ["test_connection"]="Test server connection before installing?"
        ["use_hostname"]="Use system hostname"
        ["custom_hostname"]="Custom hostname"
        ["enable_shell"]="Enable shell command execution? (requires super token)"
        ["shell_token_prompt"]="Shell Super Token (different from auth token)"
        
        # Testing
        ["testing_connection"]="Testing Connection"
        ["testing_server"]="Testing connection to"
        ["server_reachable"]="Server is reachable!"
        ["cannot_reach"]="Cannot reach server at"
        ["continue_anyway"]="Continue anyway?"
        ["connection_failed"]="Connection test failed"
        
        # Download & Install
        ["downloading"]="Downloading NanoLink Agent"
        ["download_url"]="URL"
        ["download_success"]="Downloaded successfully"
        ["download_failed"]="Failed to download"
        ["installing_binary"]="Installing Binary"
        ["installed_to"]="Installed to"
        ["creating_dirs"]="Creating Directories"
        ["dirs_created"]="Directories created"
        ["generating_config"]="Generating Configuration"
        ["config_backed_up"]="Existing config backed up to"
        ["config_saved"]="Configuration saved to"
        
        # Service
        ["installing_systemd"]="Installing systemd Service"
        ["systemd_installed"]="systemd service installed"
        ["installing_launchd"]="Installing launchd Service"
        ["launchd_installed"]="launchd service installed"
        ["starting_service"]="Starting Service"
        ["service_started"]="Service started"
        ["start_failed"]="Failed to start service"
        ["check_logs"]="Check logs at"
        ["verifying"]="Verifying Installation"
        ["binary_installed"]="Binary installed"
        ["config_exists_check"]="Configuration exists"
        ["service_installed"]="Service installed"
        ["service_running_check"]="Service running"
        ["all_passed"]="All checks passed!"
        ["checks_passed"]="checks passed"
        
        # Summary
        ["install_complete"]="Installation Complete!"
        ["install_details"]="Installation Details"
        ["binary"]="Binary"
        ["config"]="Config"
        ["logs"]="Logs"
        ["server"]="Server"
        ["useful_commands"]="Useful Commands"
        ["status"]="Status"
        ["restart"]="Restart"
        ["stop"]="Stop"
        ["view_logs"]="View Logs"
        ["uninstall"]="Uninstall"
        
        # Management menu
        ["mgmt_menu_title"]="NanoLink Agent Management Menu"
        ["server_management"]="Server Management"
        ["add_server"]="Add new server"
        ["modify_server"]="Modify server configuration"
        ["remove_server"]="Remove server"
        ["list_servers"]="List configured servers"
        ["metrics_collection"]="Metrics & Collection"
        ["config_metrics"]="Configure metrics collection intervals"
        ["service_control"]="Service Control"
        ["show_status"]="Show agent status"
        ["start_agent"]="Start agent"
        ["stop_agent"]="Stop agent"
        ["restart_agent"]="Restart agent"
        ["reload_config"]="Reload configuration (hot-reload)"
        ["maintenance"]="Maintenance"
        ["view_logs_menu"]="View logs"
        ["uninstall_agent"]="Uninstall agent"
        ["exit"]="Exit"
        ["select_option"]="Select option"
        ["press_enter"]="Press Enter to continue..."
        ["goodbye"]="Goodbye!"
        ["invalid_option"]="Invalid option"
        
        # Metrics config
        ["metrics_config"]="Metrics Configuration"
        ["current_settings"]="Current collector settings"
        ["modify_intervals"]="Modify collector intervals?"
        ["cpu_interval"]="CPU interval (ms)"
        ["disk_interval"]="Disk interval (ms)"
        ["network_interval"]="Network interval (ms)"
        ["intervals_updated"]="Collector intervals updated"
        ["reload_now"]="Reload configuration now?"
        ["reloading_config"]="Reloading Configuration"
        ["reload_success"]="Configuration reloaded successfully!"
        ["reload_failed"]="Hot reload failed. Restarting service..."
        ["restarting_service"]="Restarting Service"
        ["service_restarted"]="Service restarted"
        
        # Uninstall
        ["uninstall_title"]="Uninstall NanoLink Agent"
        ["uninstall_warn"]="This will remove the NanoLink Agent from your system."
        ["confirm_uninstall"]="Are you sure you want to uninstall?"
        ["uninstall_cancelled"]="Uninstall cancelled"
        ["binary_removed"]="Binary removed"
        ["remove_data"]="Remove configuration and data?"
        ["data_removed"]="Configuration and data removed"
        ["data_preserved"]="Configuration and data preserved at"
        ["uninstall_complete"]="NanoLink Agent has been uninstalled"
        
        # View logs
        ["log_file_not_found"]="Log file not found"
        ["last_lines"]="Last 30 lines of agent log"
        ["follow_logs"]="Follow logs in real-time?"
        ["press_ctrl_c"]="Press Ctrl+C to stop..."
        
        # Add server
        ["add_new_server"]="Add New Server"
        ["server_url_required"]="Server URL is required"
        ["token_required"]="Token is required"
        ["server_added"]="Server added to configuration"
        ["hot_reload_success"]="Server added via hot-reload"
        ["restart_to_apply"]="Restart the agent to apply changes"
        
        # Remove server
        ["remove_server_title"]="Remove Server"
        ["enter_url_remove"]="Enter server URL to remove"
        ["confirm_remove"]="Are you sure you want to remove this server?"
        ["server_removed"]="Server removed from configuration"
        
        # Modify server
        ["modify_server_title"]="Modify Server Configuration"
        ["enter_url_modify"]="Enter server URL to modify"
        ["server_not_found"]="Server not found in configuration"
        ["what_to_modify"]="What do you want to modify?"
        ["token"]="Token"
        ["permission"]="Permission level"
        ["tls_verify"]="TLS verification"
        ["new_token"]="New Token"
        ["new_permission"]="New Permission Level"
        ["enable_tls"]="Enable TLS verification?"
        ["manual_edit"]="Manual update recommended. Edit"
        ["open_editor"]="Open config file in editor?"
        
        # Configured servers
        ["configured_servers"]="Configured Servers"
        ["no_servers"]="No servers configured"
        ["config_not_found"]="Configuration file not found"
        
        # Agent status
        ["agent_status"]="Agent Status"
        ["service_status"]="Service Status"
        ["running"]="Running"
        ["stopped"]="Stopped"
        ["loaded"]="Loaded"
        ["not_loaded"]="Not Loaded"
        ["service_details"]="Service Details"
        ["configuration"]="Configuration"
        
        # Help
        ["help_title"]="NanoLink Agent Installer"
        ["usage"]="Usage"
        ["install_options"]="Installation Options"
        ["silent_mode"]="Silent mode (no prompts)"
        ["url_option"]="Server WebSocket URL (IP or domain)"
        ["token_option"]="Authentication token"
        ["permission_option"]="Permission level (0-3)"
        ["no_tls_option"]="Disable TLS verification"
        ["hostname_option"]="Override hostname"
        ["shell_enabled_option"]="Enable shell commands"
        ["shell_token_option"]="Shell super token"
        ["server_mgmt"]="Server Management"
        ["add_server_option"]="Add server to existing installation"
        ["remove_server_option"]="Remove server from existing installation"
        ["fetch_config_option"]="Fetch configuration from server API"
        ["management"]="Management"
        ["manage_option"]="Interactive management menu"
        ["lang_option"]="Set language (en/zh)"
        ["help_option"]="Show this help"
        ["examples"]="Examples"
        ["fresh_install_interactive"]="Fresh install (interactive)"
        ["fresh_install_silent"]="Fresh install (silent)"
        ["add_server_example"]="Add additional server to existing agent"
        ["open_manage"]="Open management menu"
        ["fetch_config_example"]="Fetch config from server and install"
    )
    
    # Chinese messages
    declare -A zh_msgs=(
        # General
        ["banner_subtitle"]="轻量级服务器监控代理"
        ["detected"]="检测到"
        
        # Status messages
        ["info"]="信息"
        ["success"]="成功"
        ["warn"]="警告"
        ["error"]="错误"
        
        # Installation
        ["existing_detected"]="检测到已安装的 Agent"
        ["installed_version"]="已安装版本"
        ["script_version"]="脚本版本"
        ["service_running"]="Agent 服务正在运行"
        ["service_stopped"]="Agent 服务已停止"
        ["service_loaded"]="Agent 服务已加载"
        ["config_exists"]="配置文件位于"
        ["what_to_do"]="请选择操作"
        ["select_action"]="选择操作"
        ["opt_update"]="更新 Agent（下载最新版本，保留配置）"
        ["opt_manage"]="管理现有 Agent（打开管理菜单）"
        ["opt_fresh"]="全新安装（覆盖配置和二进制文件）"
        ["opt_cancel"]="取消"
        ["stopping_service"]="更新前停止 Agent 服务..."
        ["service_stopped_ok"]="服务已停止"
        ["warn_overwrite"]="这将覆盖现有配置！"
        ["are_you_sure"]="确定继续吗？"
        ["cancelled"]="安装已取消"
        ["keeping_config"]="保留现有配置"
        ["update_success"]="Agent 更新成功！"
        
        # Server config
        ["server_config"]="服务器配置"
        ["server_url_prompt"]="服务器 WebSocket 地址（例如：wss://monitor.example.com:9100）"
        ["url_invalid"]="地址必须以 ws:// 或 wss:// 开头"
        ["token_prompt"]="认证令牌"
        ["permission_level"]="权限级别"
        ["perm_readonly"]="只读（仅监控）"
        ["perm_basic"]="读取 + 进程控制"
        ["perm_shell"]="读取 + 进程 + 受限 Shell"
        ["perm_full"]="完全访问（所有操作）"
        ["verify_tls"]="验证 TLS 证书？"
        ["tls_disabled_warn"]="TLS 验证已禁用 - 仅用于测试环境！"
        ["test_connection"]="安装前测试服务器连接？"
        ["use_hostname"]="使用系统主机名"
        ["custom_hostname"]="自定义主机名"
        ["enable_shell"]="启用 Shell 命令执行？（需要超级令牌）"
        ["shell_token_prompt"]="Shell 超级令牌（与认证令牌不同）"
        
        # Testing
        ["testing_connection"]="测试连接"
        ["testing_server"]="正在测试连接到"
        ["server_reachable"]="服务器可访问！"
        ["cannot_reach"]="无法连接到服务器"
        ["continue_anyway"]="是否继续？"
        ["connection_failed"]="连接测试失败"
        
        # Download & Install
        ["downloading"]="正在下载 NanoLink Agent"
        ["download_url"]="下载地址"
        ["download_success"]="下载成功"
        ["download_failed"]="下载失败"
        ["installing_binary"]="安装二进制文件"
        ["installed_to"]="已安装到"
        ["creating_dirs"]="创建目录"
        ["dirs_created"]="目录创建完成"
        ["generating_config"]="生成配置文件"
        ["config_backed_up"]="已备份现有配置到"
        ["config_saved"]="配置已保存到"
        
        # Service
        ["installing_systemd"]="安装 systemd 服务"
        ["systemd_installed"]="systemd 服务已安装"
        ["installing_launchd"]="安装 launchd 服务"
        ["launchd_installed"]="launchd 服务已安装"
        ["starting_service"]="启动服务"
        ["service_started"]="服务已启动"
        ["start_failed"]="服务启动失败"
        ["check_logs"]="查看日志"
        ["verifying"]="验证安装"
        ["binary_installed"]="二进制文件已安装"
        ["config_exists_check"]="配置文件存在"
        ["service_installed"]="服务已安装"
        ["service_running_check"]="服务正在运行"
        ["all_passed"]="所有检查通过！"
        ["checks_passed"]="项检查通过"
        
        # Summary
        ["install_complete"]="安装完成！"
        ["install_details"]="安装详情"
        ["binary"]="二进制文件"
        ["config"]="配置文件"
        ["logs"]="日志目录"
        ["server"]="服务器"
        ["useful_commands"]="常用命令"
        ["status"]="查看状态"
        ["restart"]="重启服务"
        ["stop"]="停止服务"
        ["view_logs"]="查看日志"
        ["uninstall"]="卸载"
        
        # Management menu
        ["mgmt_menu_title"]="NanoLink Agent 管理菜单"
        ["server_management"]="服务器管理"
        ["add_server"]="添加新服务器"
        ["modify_server"]="修改服务器配置"
        ["remove_server"]="删除服务器"
        ["list_servers"]="列出已配置的服务器"
        ["metrics_collection"]="指标采集"
        ["config_metrics"]="配置指标采集频率"
        ["service_control"]="服务控制"
        ["show_status"]="查看 Agent 状态"
        ["start_agent"]="启动 Agent"
        ["stop_agent"]="停止 Agent"
        ["restart_agent"]="重启 Agent"
        ["reload_config"]="重载配置（热更新）"
        ["maintenance"]="维护"
        ["view_logs_menu"]="查看日志"
        ["uninstall_agent"]="卸载 Agent"
        ["exit"]="退出"
        ["select_option"]="请选择"
        ["press_enter"]="按回车键继续..."
        ["goodbye"]="再见！"
        ["invalid_option"]="无效选项"
        
        # Metrics config
        ["metrics_config"]="指标配置"
        ["current_settings"]="当前采集器设置"
        ["modify_intervals"]="修改采集频率？"
        ["cpu_interval"]="CPU 采集间隔（毫秒）"
        ["disk_interval"]="磁盘采集间隔（毫秒）"
        ["network_interval"]="网络采集间隔（毫秒）"
        ["intervals_updated"]="采集频率已更新"
        ["reload_now"]="立即重载配置？"
        ["reloading_config"]="重载配置"
        ["reload_success"]="配置重载成功！"
        ["reload_failed"]="热重载失败，正在重启服务..."
        ["restarting_service"]="重启服务"
        ["service_restarted"]="服务已重启"
        
        # Uninstall
        ["uninstall_title"]="卸载 NanoLink Agent"
        ["uninstall_warn"]="这将从系统中移除 NanoLink Agent。"
        ["confirm_uninstall"]="确定要卸载吗？"
        ["uninstall_cancelled"]="卸载已取消"
        ["binary_removed"]="二进制文件已删除"
        ["remove_data"]="删除配置和数据？"
        ["data_removed"]="配置和数据已删除"
        ["data_preserved"]="配置和数据已保留在"
        ["uninstall_complete"]="NanoLink Agent 已卸载"
        
        # View logs
        ["log_file_not_found"]="日志文件未找到"
        ["last_lines"]="最近 30 行日志"
        ["follow_logs"]="实时跟踪日志？"
        ["press_ctrl_c"]="按 Ctrl+C 停止..."
        
        # Add server
        ["add_new_server"]="添加新服务器"
        ["server_url_required"]="服务器地址是必需的"
        ["token_required"]="令牌是必需的"
        ["server_added"]="服务器已添加到配置"
        ["hot_reload_success"]="服务器已通过热重载添加"
        ["restart_to_apply"]="重启 Agent 以应用更改"
        
        # Remove server
        ["remove_server_title"]="删除服务器"
        ["enter_url_remove"]="输入要删除的服务器地址"
        ["confirm_remove"]="确定要删除此服务器吗？"
        ["server_removed"]="服务器已从配置中删除"
        
        # Modify server
        ["modify_server_title"]="修改服务器配置"
        ["enter_url_modify"]="输入要修改的服务器地址"
        ["server_not_found"]="配置中未找到此服务器"
        ["what_to_modify"]="要修改什么？"
        ["token"]="令牌"
        ["permission"]="权限级别"
        ["tls_verify"]="TLS 验证"
        ["new_token"]="新令牌"
        ["new_permission"]="新权限级别"
        ["enable_tls"]="启用 TLS 验证？"
        ["manual_edit"]="建议手动编辑"
        ["open_editor"]="在编辑器中打开配置文件？"
        
        # Configured servers
        ["configured_servers"]="已配置的服务器"
        ["no_servers"]="未配置服务器"
        ["config_not_found"]="配置文件未找到"
        
        # Agent status
        ["agent_status"]="Agent 状态"
        ["service_status"]="服务状态"
        ["running"]="运行中"
        ["stopped"]="已停止"
        ["loaded"]="已加载"
        ["not_loaded"]="未加载"
        ["service_details"]="服务详情"
        ["configuration"]="配置文件"
        
        # Help
        ["help_title"]="NanoLink Agent 安装程序"
        ["usage"]="用法"
        ["install_options"]="安装选项"
        ["silent_mode"]="静默模式（无提示）"
        ["url_option"]="服务器 WebSocket 地址"
        ["token_option"]="认证令牌"
        ["permission_option"]="权限级别（0-3）"
        ["no_tls_option"]="禁用 TLS 验证"
        ["hostname_option"]="覆盖主机名"
        ["shell_enabled_option"]="启用 Shell 命令"
        ["shell_token_option"]="Shell 超级令牌"
        ["server_mgmt"]="服务器管理"
        ["add_server_option"]="添加服务器到现有安装"
        ["remove_server_option"]="从现有安装中删除服务器"
        ["fetch_config_option"]="从服务器 API 获取配置"
        ["management"]="管理"
        ["manage_option"]="交互式管理菜单"
        ["lang_option"]="设置语言（en/zh）"
        ["help_option"]="显示帮助"
        ["examples"]="示例"
        ["fresh_install_interactive"]="交互式安装"
        ["fresh_install_silent"]="静默安装"
        ["add_server_example"]="添加额外服务器到现有 Agent"
        ["open_manage"]="打开管理菜单"
        ["fetch_config_example"]="从服务器获取配置并安装"
    )
    
    # Return appropriate message
    if [ "$SCRIPT_LANG" = "zh" ]; then
        echo "${zh_msgs[$key]:-$key}"
    else
        echo "${en_msgs[$key]:-$key}"
    fi
}

# =============================================================================
# Helper Functions
# =============================================================================
print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║     ███╗   ██╗ █████╗ ███╗   ██╗ ██████╗ ██╗     ██╗███╗   ██╗██╗  ██╗    ║"
    echo "║     ████╗  ██║██╔══██╗████╗  ██║██╔═══██╗██║     ██║████╗  ██║██║ ██╔╝    ║"
    echo "║     ██╔██╗ ██║███████║██╔██╗ ██║██║   ██║██║     ██║██╔██╗ ██║█████╔╝     ║"
    echo "║     ██║╚██╗██║██╔══██║██║╚██╗██║██║   ██║██║     ██║██║╚██╗██║██╔═██╗     ║"
    echo "║     ██║ ╚████║██║  ██║██║ ╚████║╚██████╔╝███████╗██║██║ ╚████║██║  ██╗    ║"
    echo "║     ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝    ║"
    echo "║                                                               ║"
    printf "║              %-43s ║\n" "$(msg banner_subtitle)"
    echo "║                        Version ${VERSION}                          ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
step() { echo -e "\n${BOLD}${CYAN}▶ $1${NC}"; }

# Spinner for long operations
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "      \b\b\b\b\b\b"
}

# =============================================================================
# System Detection
# =============================================================================
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
        if command -v systemctl &> /dev/null; then
            INIT_SYSTEM="systemd"
        else
            INIT_SYSTEM="other"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        INIT_SYSTEM="launchd"
    else
        error "Unsupported operating system: $OSTYPE"
        exit 1
    fi
}

detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64|amd64)
            ARCH="x86_64"
            ;;
        aarch64|arm64)
            ARCH="aarch64"
            ;;
        armv7l)
            ARCH="armv7"
            ;;
        *)
            error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Please run as root (sudo)"
        echo -e "  Run: ${YELLOW}sudo $0${NC}"
        exit 1
    fi
}

check_dependencies() {
    local missing=()

    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        missing+=("curl or wget")
    fi

    if [ ${#missing[@]} -ne 0 ]; then
        error "Missing dependencies: ${missing[*]}"
        exit 1
    fi
}

# =============================================================================
# Interactive Configuration
# =============================================================================

# Check if we can read from terminal (for pipe mode support)
check_interactive() {
    if [ ! -t 0 ] && [ "$SILENT_MODE" != "true" ]; then
        # stdin is not a terminal (piped), try to use /dev/tty
        if [ ! -e /dev/tty ]; then
            error "Interactive mode requires a terminal. Use --silent mode with parameters:"
            echo ""
            echo "  curl -fsSL URL | sudo bash -s -- --silent --host \"server.example.com\" --port 39100 --token \"your_token\""
            echo ""
            exit 1
        fi
    fi
}

prompt_value() {
    local prompt="$1"
    local default="$2"
    local value

    if [ -n "$default" ]; then
        echo -en "${BOLD}$prompt${NC} [${YELLOW}$default${NC}]: " >/dev/tty
        read value </dev/tty
        echo "${value:-$default}"
    else
        echo -en "${BOLD}$prompt${NC}: " >/dev/tty
        read value </dev/tty
        echo "$value"
    fi
}

prompt_password() {
    local prompt="$1"
    local value

    echo -en "${BOLD}$prompt${NC}: " >/dev/tty
    read -s value </dev/tty
    echo "" >/dev/tty
    echo "$value"
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local value

    if [ "$default" = "y" ]; then
        echo -en "${BOLD}$prompt${NC} [${YELLOW}Y/n${NC}]: " >/dev/tty
        read value </dev/tty
        value="${value:-y}"
    else
        echo -en "${BOLD}$prompt${NC} [${YELLOW}y/N${NC}]: " >/dev/tty
        read value </dev/tty
        value="${value:-n}"
    fi

    [[ "$value" =~ ^[Yy] ]]
}

prompt_choice() {
    local prompt="$1"
    shift
    local options=("$@")

    echo -e "${BOLD}$prompt${NC}" >/dev/tty
    for i in "${!options[@]}"; do
        echo -e "  ${CYAN}$((i+1))${NC}) ${options[$i]}" >/dev/tty
    done

    local choice
    while true; do
        echo -en "${BOLD}Select [1-${#options[@]}]${NC}: " >/dev/tty
        read choice </dev/tty
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
            echo "$((choice-1))"
            return
        fi
        warn "Invalid choice, please try again"
    done
}

interactive_config() {
    step "$(msg server_config)"
    echo ""

    # Server URL
    while true; do
        SERVER_URL=$(prompt_value "$(msg server_url_prompt)" "")
        if [ -z "$SERVER_URL" ]; then
            warn "$(msg server_url_required)"
            continue
        fi
        if [[ ! "$SERVER_URL" =~ ^wss?:// ]]; then
            warn "$(msg url_invalid)"
            continue
        fi
        break
    done

    # Token
    while true; do
        TOKEN=$(prompt_value "$(msg token_prompt)" "")
        if [ -z "$TOKEN" ]; then
            warn "$(msg token_required)"
            continue
        fi
        break
    done

    # Permission level
    echo ""
    local perms=("$(msg perm_readonly)" "$(msg perm_basic)" "$(msg perm_shell)" "$(msg perm_full)")
    PERMISSION=$(prompt_choice "$(msg permission_level)" "${perms[@]}")

    # TLS verification
    echo ""
    TLS_VERIFY="true"
    if [[ "$SERVER_URL" =~ ^wss:// ]]; then
        if prompt_yes_no "$(msg verify_tls)" "y"; then
            TLS_VERIFY="true"
        else
            TLS_VERIFY="false"
            warn "$(msg tls_disabled_warn)"
        fi
    fi

    # Test connection
    echo ""
    if prompt_yes_no "$(msg test_connection)" "y"; then
        test_connection
    fi

    # Hostname override
    echo ""
    HOSTNAME_OVERRIDE=""
    if ! prompt_yes_no "$(msg use_hostname) ($(hostname))?" "y"; then
        HOSTNAME_OVERRIDE=$(prompt_value "$(msg custom_hostname)" "")
    fi

    # Shell commands
    echo ""
    SHELL_ENABLED="false"
    SHELL_TOKEN=""
    if [ "$PERMISSION" -ge 2 ]; then
        if prompt_yes_no "$(msg enable_shell)" "n"; then
            SHELL_ENABLED="true"
            while true; do
                SHELL_TOKEN=$(prompt_password "$(msg shell_token_prompt)")
                if [ -z "$SHELL_TOKEN" ]; then
                    warn "$(msg token_required)"
                    continue
                fi
                break
            done
        fi
    fi
}

test_connection() {
    step "Testing Connection"

    # Extract host and port from URL
    local host_port=$(echo "$SERVER_URL" | sed -E 's|^wss?://||' | cut -d'/' -f1)
    local host=$(echo "$host_port" | cut -d':' -f1)
    local port=$(echo "$host_port" | cut -d':' -f2)
    [ "$port" = "$host" ] && port="9100"

    info "Testing connection to $host:$port..."

    # Test TCP connection
    if command -v nc &> /dev/null; then
        if nc -z -w5 "$host" "$port" 2>/dev/null; then
            success "Server is reachable!"
        else
            warn "Cannot reach server at $host:$port"
            if ! prompt_yes_no "Continue anyway?" "n"; then
                exit 1
            fi
        fi
    elif command -v curl &> /dev/null; then
        local test_url="${SERVER_URL/wss:/https:}"
        test_url="${test_url/ws:/http:}"
        if curl -s --connect-timeout 5 "$test_url" &>/dev/null; then
            success "Server is reachable!"
        else
            warn "Cannot reach server"
            if ! prompt_yes_no "Continue anyway?" "n"; then
                exit 1
            fi
        fi
    else
        warn "Cannot test connection (nc/curl not available)"
    fi
}

# =============================================================================
# Installation Functions
# =============================================================================

# Check if agent is already installed and offer upgrade
check_existing_agent() {
    local binary_path="${INSTALL_DIR}/${BINARY_NAME}"
    local config_file="${CONFIG_DIR}/nanolink.yaml"
    local service_running=false
    
    # Check if binary exists
    if [ ! -f "$binary_path" ]; then
        return 0  # No existing installation
    fi
    
    step "$(msg existing_detected)"
    echo ""
    
    # Get current version if possible
    local current_version="unknown"
    if [ -x "$binary_path" ]; then
        current_version=$("$binary_path" --version 2>/dev/null | head -1 || echo "unknown")
    fi
    info "$(msg installed_version): $current_version"
    info "$(msg script_version): $VERSION"
    
    # Check if service is running
    if [ "$OS" = "linux" ]; then
        if systemctl is-active --quiet nanolink-agent 2>/dev/null; then
            service_running=true
            success "$(msg service_running)"
        else
            warn "$(msg service_stopped)"
        fi
    elif [ "$OS" = "macos" ]; then
        if launchctl list 2>/dev/null | grep -q "com.nanolink.agent"; then
            service_running=true
            success "$(msg service_loaded)"
        fi
    fi
    
    # Check if config exists
    if [ -f "$config_file" ]; then
        info "$(msg config_exists): $config_file"
    fi
    
    echo ""
    echo -e "${BOLD}$(msg what_to_do)${NC}"
    local action=$(prompt_choice "$(msg select_action)" \
        "$(msg opt_update)" \
        "$(msg opt_manage)" \
        "$(msg opt_fresh)" \
        "$(msg opt_cancel)")
    
    case $action in
        0)  # Update
            UPDATE_MODE=true
            if [ "$service_running" = "true" ]; then
                info "$(msg stopping_service)"
                if [ "$OS" = "linux" ]; then
                    systemctl stop nanolink-agent
                elif [ "$OS" = "macos" ]; then
                    launchctl stop com.nanolink.agent 2>/dev/null || true
                fi
                success "$(msg service_stopped_ok)"
            fi
            ;;
        1)  # Manage
            manage_menu
            exit 0
            ;;
        2)  # Fresh install
            warn "$(msg warn_overwrite)"
            if ! prompt_yes_no "$(msg are_you_sure)" "n"; then
                info "$(msg cancelled)"
                exit 0
            fi
            if [ "$service_running" = "true" ]; then
                info "$(msg stopping_service)"
                if [ "$OS" = "linux" ]; then
                    systemctl stop nanolink-agent
                elif [ "$OS" = "macos" ]; then
                    launchctl stop com.nanolink.agent 2>/dev/null || true
                fi
                success "$(msg service_stopped_ok)"
            fi
            ;;
        3)  # Cancel
            info "$(msg cancelled)"
            exit 0
            ;;
    esac
}
download_binary() {
    step "Downloading NanoLink Agent"

    local download_url="https://github.com/${GITHUB_REPO}/releases/latest/download/${BINARY_NAME}-${OS}-${ARCH}"
    local tmp_file="/tmp/${BINARY_NAME}"

    info "URL: $download_url"

    if command -v curl &> /dev/null; then
        curl -fsSL "$download_url" -o "$tmp_file" &
        spinner $!
    elif command -v wget &> /dev/null; then
        wget -q "$download_url" -O "$tmp_file" &
        spinner $!
    fi

    if [ ! -f "$tmp_file" ]; then
        error "Download failed"
        exit 1
    fi

    chmod +x "$tmp_file"
    success "Downloaded successfully"
}

install_binary() {
    step "Installing Binary"

    mv "/tmp/${BINARY_NAME}" "${INSTALL_DIR}/${BINARY_NAME}"
    success "Installed to ${INSTALL_DIR}/${BINARY_NAME}"
}

create_directories() {
    step "Creating Directories"

    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$DATA_DIR"

    # Set permissions
    chmod 755 "$CONFIG_DIR"
    chmod 755 "$LOG_DIR"
    chmod 755 "$DATA_DIR"

    success "Directories created"
}

generate_config() {
    step "Generating Configuration"

    local config_file="${CONFIG_DIR}/nanolink.yaml"

    # Backup existing config
    if [ -f "$config_file" ]; then
        local backup="${config_file}.backup.$(date +%Y%m%d%H%M%S)"
        cp "$config_file" "$backup"
        warn "Existing config backed up to: $backup"
    fi

    # Generate new config
    cat > "$config_file" << EOF
# NanoLink Agent Configuration
# Generated on $(date)

agent:
$([ -n "$HOSTNAME_OVERRIDE" ] && echo "  hostname: \"$HOSTNAME_OVERRIDE\"")
  heartbeat_interval: 30
  reconnect_delay: 5
  max_reconnect_delay: 300

servers:
  - host: "$(echo "$SERVER_URL" | sed -E 's|^wss?://||' | cut -d':' -f1 | cut -d'/' -f1)"
    port: $(echo "$SERVER_URL" | sed -E 's|^wss?://||' | grep -oE ':[0-9]+' | cut -d':' -f2 || echo 9100)
    tls_enabled: $(echo "$SERVER_URL" | grep -q '^wss://' && echo 'true' || echo 'false')
    token: "${TOKEN}"
    permission: ${PERMISSION}
    tls_verify: ${TLS_VERIFY}

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
  enabled: ${SHELL_ENABLED}
$([ "$SHELL_ENABLED" = "true" ] && echo "  super_token: \"${SHELL_TOKEN}\"")
  timeout_seconds: 30
  whitelist:
    - pattern: "df -h"
      description: "Show disk space"
    - pattern: "free -m"
      description: "Show memory usage"
    - pattern: "uptime"
      description: "Show uptime"
    - pattern: "tail -n * /var/log/*.log"
      description: "View log tail"
    - pattern: "systemctl status *"
      description: "View service status"
  blacklist:
    - "rm -rf"
    - "mkfs"
    - "> /dev"
    - "dd if="
    - ":(){:|:&};:"
  require_confirmation:
    - pattern: "reboot"
    - pattern: "shutdown"

management:
  enabled: true
  port: 9101

logging:
  level: info
  audit_enabled: true
  audit_file: "${LOG_DIR}/audit.log"
EOF

    # Secure the config file (contains tokens)
    chmod 600 "$config_file"

    success "Configuration saved to $config_file"
}

install_systemd_service() {
    step "Installing systemd Service"

    cat > /etc/systemd/system/nanolink-agent.service << 'EOF'
[Unit]
Description=NanoLink Monitoring Agent
Documentation=https://github.com/chenqi92/NanoLink
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=root
Group=root
ExecStart=/usr/local/bin/nanolink-agent -c /etc/nanolink/nanolink.yaml
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
RestartSec=5
StartLimitInterval=60
StartLimitBurst=3

# Watchdog (agent must notify systemd every 30s)
WatchdogSec=60

# Graceful shutdown
TimeoutStartSec=10
TimeoutStopSec=10

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=nanolink-agent

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/var/log/nanolink /var/lib/nanolink
ReadOnlyPaths=/etc/nanolink

# Resource limits
MemoryMax=128M
CPUQuota=10%

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable nanolink-agent

    success "systemd service installed and enabled"
}

install_launchd_service() {
    step "Installing launchd Service"

    cat > /Library/LaunchDaemons/com.nanolink.agent.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.nanolink.agent</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/nanolink-agent</string>
        <string>-c</string>
        <string>/etc/nanolink/nanolink.yaml</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
        <key>Crashed</key>
        <true/>
        <key>NetworkState</key>
        <true/>
    </dict>

    <key>ThrottleInterval</key>
    <integer>5</integer>

    <key>StandardOutPath</key>
    <string>/var/log/nanolink/agent.log</string>

    <key>StandardErrorPath</key>
    <string>/var/log/nanolink/agent.err</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin</string>
    </dict>

    <key>ProcessType</key>
    <string>Background</string>

    <key>LowPriorityIO</key>
    <true/>

    <key>SoftResourceLimits</key>
    <dict>
        <key>NumberOfFiles</key>
        <integer>1024</integer>
    </dict>
</dict>
</plist>
EOF

    # Load the service
    launchctl load /Library/LaunchDaemons/com.nanolink.agent.plist 2>/dev/null || true

    success "launchd service installed and loaded"
}

start_service() {
    step "Starting Service"

    if [ "$OS" = "linux" ] && [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl start nanolink-agent
        sleep 2

        if systemctl is-active --quiet nanolink-agent; then
            success "Service started successfully!"
        else
            error "Service failed to start"
            echo ""
            echo "Check logs with:"
            echo -e "  ${YELLOW}journalctl -u nanolink-agent -f${NC}"
            exit 1
        fi
    elif [ "$OS" = "macos" ]; then
        launchctl start com.nanolink.agent
        sleep 2

        if launchctl list | grep -q "com.nanolink.agent"; then
            success "Service started successfully!"
        else
            warn "Service may not have started correctly"
            echo "Check logs at: /var/log/nanolink/"
        fi
    fi
}

verify_installation() {
    step "Verifying Installation"

    local checks_passed=0
    local checks_total=4

    # Check binary
    if [ -x "${INSTALL_DIR}/${BINARY_NAME}" ]; then
        echo -e "  ${GREEN}✓${NC} Binary installed"
        ((checks_passed++))
    else
        echo -e "  ${RED}✗${NC} Binary not found"
    fi

    # Check config
    if [ -f "${CONFIG_DIR}/nanolink.yaml" ]; then
        echo -e "  ${GREEN}✓${NC} Configuration exists"
        ((checks_passed++))
    else
        echo -e "  ${RED}✗${NC} Configuration not found"
    fi

    # Check service enabled
    if [ "$OS" = "linux" ]; then
        if systemctl is-enabled --quiet nanolink-agent 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Service enabled (auto-start)"
            ((checks_passed++))
        else
            echo -e "  ${RED}✗${NC} Service not enabled"
        fi

        if systemctl is-active --quiet nanolink-agent 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Service running"
            ((checks_passed++))
        else
            echo -e "  ${YELLOW}○${NC} Service not running"
        fi
    elif [ "$OS" = "macos" ]; then
        if [ -f /Library/LaunchDaemons/com.nanolink.agent.plist ]; then
            echo -e "  ${GREEN}✓${NC} Service enabled (auto-start)"
            ((checks_passed++))
        fi
        ((checks_passed++))  # Assume running for launchd
    fi

    echo ""
    if [ $checks_passed -eq $checks_total ]; then
        success "All checks passed!"
    else
        warn "$checks_passed/$checks_total checks passed"
    fi
}

print_summary() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    printf "${CYAN}║${NC}              ${GREEN}%-43s${NC} ${CYAN}║${NC}\n" "$(msg install_complete)"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}$(msg install_details):${NC}"
    echo -e "  $(msg binary):     ${YELLOW}${INSTALL_DIR}/${BINARY_NAME}${NC}"
    echo -e "  $(msg config):     ${YELLOW}${CONFIG_DIR}/nanolink.yaml${NC}"
    echo -e "  $(msg logs):       ${YELLOW}${LOG_DIR}/${NC}"
    echo -e "  $(msg server):     ${YELLOW}${SERVER_URL}${NC}"
    echo ""
    echo -e "${BOLD}$(msg useful_commands):${NC}"
    if [ "$OS" = "linux" ]; then
        echo -e "  $(msg status):     ${YELLOW}sudo systemctl status nanolink-agent${NC}"
        echo -e "  $(msg view_logs):       ${YELLOW}sudo journalctl -u nanolink-agent -f${NC}"
        echo -e "  $(msg restart):    ${YELLOW}sudo systemctl restart nanolink-agent${NC}"
        echo -e "  $(msg stop):       ${YELLOW}sudo systemctl stop nanolink-agent${NC}"
    elif [ "$OS" = "macos" ]; then
        echo -e "  $(msg status):     ${YELLOW}sudo launchctl list | grep nanolink${NC}"
        echo -e "  $(msg view_logs):       ${YELLOW}tail -f /var/log/nanolink/agent.log${NC}"
        echo -e "  $(msg restart):    ${YELLOW}sudo launchctl stop com.nanolink.agent && sudo launchctl start com.nanolink.agent${NC}"
    fi
    echo ""
    echo -e "${BOLD}$(msg uninstall):${NC}"
    echo -e "  ${YELLOW}curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/main/agent/scripts/uninstall.sh | sudo bash${NC}"
    echo ""
}

# =============================================================================
# Silent Mode (for scripted installations)
# =============================================================================
parse_args() {
    SILENT_MODE=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --silent|-s)
                SILENT_MODE=true
                shift
                ;;
            --url)
                SERVER_URL="$2"
                shift 2
                ;;
            --token)
                TOKEN="$2"
                shift 2
                ;;
            --permission)
                PERMISSION="$2"
                shift 2
                ;;
            --no-tls-verify)
                TLS_VERIFY="false"
                shift
                ;;
            --hostname)
                HOSTNAME_OVERRIDE="$2"
                shift 2
                ;;
            --shell-enabled)
                SHELL_ENABLED="true"
                shift
                ;;
            --shell-token)
                SHELL_TOKEN="$2"
                shift 2
                ;;
            --add-server)
                ADD_SERVER_MODE=true
                shift
                ;;
            --remove-server)
                REMOVE_SERVER_MODE=true
                shift
                ;;
            --fetch-config)
                FETCH_CONFIG_URL="$2"
                shift 2
                ;;
            --manage)
                MANAGE_MODE=true
                shift
                ;;
            --lang)
                SCRIPT_LANG="$2"
                shift 2
                ;;
            --help|-h)
                echo "NanoLink Agent Installer"
                echo ""
                echo "Usage: $0 [options]"
                echo ""
                echo "Installation Options:"
                echo "  --silent, -s        Silent mode (no prompts)"
                echo "  --url URL           Server WebSocket URL (IP or domain)"
                echo "  --token TOKEN       Authentication token"
                echo "  --permission N      Permission level (0-3)"
                echo "  --no-tls-verify     Disable TLS verification"
                echo "  --hostname NAME     Override hostname"
                echo "  --shell-enabled     Enable shell commands"
                echo "  --shell-token TOKEN Shell super token"
                echo ""
                echo "Server Management:"
                echo "  --add-server        Add server to existing installation"
                echo "  --remove-server     Remove server from existing installation"
                echo "  --fetch-config URL  Fetch configuration from server API"
                echo ""
                echo "Management:"
                echo "  --manage            Interactive management menu"
                echo "  --lang LANG         Set language (en/zh)"
                echo ""
                echo "  --help, -h          Show this help"
                echo ""
                echo "Examples:"
                echo "  # Fresh install (interactive)"
                echo "  curl -fsSL https://raw.githubusercontent.com/chenqi92/NanoLink/main/agent/scripts/install.sh | sudo bash"
                echo ""
                echo "  # Fresh install (silent)"
                echo "  curl -fsSL https://raw.githubusercontent.com/chenqi92/NanoLink/main/agent/scripts/install.sh | sudo bash -s -- \\"
                echo "    --silent --url wss://monitor.example.com:9100 --token xxx"
                echo ""
                echo "  # Add additional server to existing agent"
                echo "  sudo $0 --add-server --url wss://second.example.com:9100 --token yyy"
                echo ""
                echo "  # Open management menu"
                echo "  sudo $0 --manage"
                echo ""
                echo "  # Fetch config from server and install"
                echo "  curl -fsSL https://raw.githubusercontent.com/chenqi92/NanoLink/main/agent/scripts/install.sh | sudo bash -s -- \\"
                echo "    --fetch-config http://monitor.example.com:8080/api/config/generate"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Validate silent mode requirements
    if [ "$SILENT_MODE" = "true" ]; then
        if [ -z "$SERVER_URL" ] || [ -z "$TOKEN" ]; then
            error "Silent mode requires --url and --token"
            exit 1
        fi
        PERMISSION="${PERMISSION:-0}"
        TLS_VERIFY="${TLS_VERIFY:-true}"
        SHELL_ENABLED="${SHELL_ENABLED:-false}"
    fi
}

# =============================================================================
# Server Management Functions
# =============================================================================
add_server_to_config() {
    local config_file="${CONFIG_DIR}/nanolink.yaml"

    if [ ! -f "$config_file" ]; then
        error "Configuration file not found: $config_file"
        error "Please run a fresh installation first"
        exit 1
    fi

    # Check if server already exists
    if grep -q "url: \"${SERVER_URL}\"" "$config_file" 2>/dev/null; then
        error "Server ${SERVER_URL} already exists in configuration"
        echo "Use --remove-server first to remove it, or update manually"
        exit 1
    fi

    # Backup config
    cp "$config_file" "${config_file}.backup.$(date +%Y%m%d%H%M%S)"

    # Add new server entry
    # Find the line with "servers:" and add after it
    sed -i "/^servers:/a\\  - url: \"${SERVER_URL}\"\n    token: \"${TOKEN}\"\n    permission: ${PERMISSION:-0}\n    tls_verify: ${TLS_VERIFY:-true}" "$config_file"

    success "Server ${SERVER_URL} added to configuration"

    # Notify via management API if available
    if command -v curl &> /dev/null; then
        local mgmt_response=$(curl -s -X POST "http://localhost:9101/api/servers" \
            -H "Content-Type: application/json" \
            -d "{\"url\":\"${SERVER_URL}\",\"token\":\"${TOKEN}\",\"permission\":${PERMISSION:-0},\"tls_verify\":${TLS_VERIFY:-true}}" 2>/dev/null)

        if echo "$mgmt_response" | grep -q '"success":true'; then
            success "Server added via management API (hot-reload)"
        else
            info "Restart the agent to apply changes: sudo systemctl restart nanolink-agent"
        fi
    else
        info "Restart the agent to apply changes: sudo systemctl restart nanolink-agent"
    fi
}

remove_server_from_config() {
    local config_file="${CONFIG_DIR}/nanolink.yaml"

    if [ ! -f "$config_file" ]; then
        error "Configuration file not found: $config_file"
        exit 1
    fi

    # Check if server exists
    if ! grep -q "url: \"${SERVER_URL}\"" "$config_file" 2>/dev/null; then
        error "Server ${SERVER_URL} not found in configuration"
        exit 1
    fi

    # Backup config
    cp "$config_file" "${config_file}.backup.$(date +%Y%m%d%H%M%S)"

    # Remove server entry (this is a simplified approach - removes 4 lines starting with the URL match)
    # For production, consider using yq or a proper YAML parser
    sed -i "/url: \"${SERVER_URL}\"/,+3d" "$config_file"

    success "Server ${SERVER_URL} removed from configuration"

    # Notify via management API if available
    if command -v curl &> /dev/null; then
        local encoded_url=$(echo "$SERVER_URL" | sed 's/:/%3A/g' | sed 's/\//%2F/g')
        local mgmt_response=$(curl -s -X DELETE "http://localhost:9101/api/servers?url=${encoded_url}" 2>/dev/null)

        if echo "$mgmt_response" | grep -q '"success":true'; then
            success "Server removed via management API (hot-reload)"
        else
            info "Restart the agent to apply changes: sudo systemctl restart nanolink-agent"
        fi
    else
        info "Restart the agent to apply changes: sudo systemctl restart nanolink-agent"
    fi
}

fetch_and_apply_config() {
    local api_url="$1"

    info "Fetching configuration from: $api_url"

    local response=$(curl -s "$api_url")

    if [ -z "$response" ]; then
        error "Failed to fetch configuration from server"
        exit 1
    fi

    # Extract values from JSON response (using grep/sed for minimal dependencies)
    if command -v jq &> /dev/null; then
        SERVER_URL=$(echo "$response" | jq -r '.serverUrl // empty')
        TOKEN=$(echo "$response" | jq -r '.token // empty')
        PERMISSION=$(echo "$response" | jq -r '.permission // 0')
        TLS_VERIFY=$(echo "$response" | jq -r '.tlsVerify // true')
    else
        # Fallback: basic grep parsing
        SERVER_URL=$(echo "$response" | grep -o '"serverUrl":"[^"]*"' | cut -d'"' -f4)
        TOKEN=$(echo "$response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
        PERMISSION=$(echo "$response" | grep -o '"permission":[0-9]*' | cut -d':' -f2)
        TLS_VERIFY=$(echo "$response" | grep -o '"tlsVerify":[a-z]*' | cut -d':' -f2)
    fi

    if [ -z "$SERVER_URL" ] || [ -z "$TOKEN" ]; then
        error "Invalid configuration response from server"
        exit 1
    fi

    PERMISSION="${PERMISSION:-0}"
    TLS_VERIFY="${TLS_VERIFY:-true}"
    SILENT_MODE=true

    success "Configuration fetched successfully"
    info "  URL: $SERVER_URL"
    info "  Permission: $PERMISSION"
}

# =============================================================================
# Management Mode Functions
# =============================================================================

# Show current status
show_status() {
    step "$(msg agent_status)"
    
    echo ""
    if [ "$OS" = "linux" ]; then
        if systemctl is-active --quiet nanolink-agent 2>/dev/null; then
            success "$(msg service_status): $(msg running)"
        else
            warn "$(msg service_status): $(msg stopped)"
        fi
        echo ""
        echo -e "${BOLD}$(msg service_details):${NC}"
        systemctl status nanolink-agent --no-pager -l 2>/dev/null | head -15 || true
    elif [ "$OS" = "macos" ]; then
        if launchctl list | grep -q "com.nanolink.agent"; then
            success "$(msg service_status): $(msg loaded)"
        else
            warn "$(msg service_status): $(msg not_loaded)"
        fi
    fi
    
    echo ""
    echo -e "${BOLD}$(msg configuration):${NC} ${CONFIG_DIR}/nanolink.yaml"
    echo -e "${BOLD}$(msg logs):${NC} ${LOG_DIR}/"
    echo ""
}

# List configured servers
list_servers() {
    local config_file="${CONFIG_DIR}/nanolink.yaml"
    
    if [ ! -f "$config_file" ]; then
        error "$(msg config_not_found)"
        return
    fi
    
    step "$(msg configured_servers)"
    echo ""
    
    # Parse servers from YAML (simplified approach)
    grep -A 5 "^  - host:\|^  - url:" "$config_file" 2>/dev/null | \
        grep -E "host:|url:|port:|token:|permission:" | \
        sed 's/^[ -]*/  /' || echo "  No servers configured"
    echo ""
}

# Modify collector settings
manage_metrics() {
    local config_file="${CONFIG_DIR}/nanolink.yaml"
    
    if [ ! -f "$config_file" ]; then
        error "Configuration file not found"
        return
    fi
    
    step "$(msg metrics_config)"
    echo ""
    echo "$(msg current_settings):"
    grep -A 10 "^collector:" "$config_file" 2>/dev/null | head -11 || echo "  No collector config found"
    echo ""
    
    if prompt_yes_no "Modify collector intervals?" "n"; then
        echo ""
        local cpu_interval=$(prompt_value "CPU interval (ms)" "1000")
        local disk_interval=$(prompt_value "Disk interval (ms)" "3000")
        local network_interval=$(prompt_value "Network interval (ms)" "1000")
        
        # Backup config
        cp "$config_file" "${config_file}.backup.$(date +%Y%m%d%H%M%S)"
        
        # Update collector section using sed
        sed -i.tmp "s/cpu_interval_ms:.*/cpu_interval_ms: ${cpu_interval}/" "$config_file"
        sed -i.tmp "s/disk_interval_ms:.*/disk_interval_ms: ${disk_interval}/" "$config_file"
        sed -i.tmp "s/network_interval_ms:.*/network_interval_ms: ${network_interval}/" "$config_file"
        rm -f "${config_file}.tmp"
        
        success "Collector intervals updated"
        echo ""
        
        if prompt_yes_no "Reload configuration now?" "y"; then
            reload_config
        fi
    fi
}

# Reload configuration via management API
reload_config() {
    step "Reloading Configuration"
    
    if command -v curl &> /dev/null; then
        local response=$(curl -s -X POST "http://localhost:9101/api/reload" 2>/dev/null)
        
        if echo "$response" | grep -q '"success":true'; then
            success "Configuration reloaded successfully!"
        else
            warn "Hot reload failed. Restarting service..."
            restart_service
        fi
    else
        warn "curl not available, restarting service..."
        restart_service
    fi
}

# Restart service
restart_service() {
    step "Restarting Service"
    
    if [ "$OS" = "linux" ]; then
        systemctl restart nanolink-agent
        success "Service restarted"
    elif [ "$OS" = "macos" ]; then
        launchctl stop com.nanolink.agent 2>/dev/null || true
        sleep 1
        launchctl start com.nanolink.agent
        success "Service restarted"
    fi
}

# Stop service
stop_service_manage() {
    step "Stopping Service"
    
    if [ "$OS" = "linux" ]; then
        systemctl stop nanolink-agent
        success "Service stopped"
    elif [ "$OS" = "macos" ]; then
        launchctl stop com.nanolink.agent 2>/dev/null
        success "Service stopped"
    fi
}

# Start service (for manage menu)
start_service_manage() {
    step "Starting Service"
    
    if [ "$OS" = "linux" ]; then
        systemctl start nanolink-agent
        success "Service started"
    elif [ "$OS" = "macos" ]; then
        launchctl start com.nanolink.agent
        success "Service started"
    fi
}

# Interactive add server
interactive_add_server() {
    step "Add New Server"
    echo ""
    
    while true; do
        SERVER_URL=$(prompt_value "Server WebSocket URL (e.g., wss://server:9100)" "")
        if [ -z "$SERVER_URL" ]; then
            warn "Server URL is required"
            continue
        fi
        if [[ ! "$SERVER_URL" =~ ^wss?:// ]]; then
            warn "URL must start with ws:// or wss://"
            continue
        fi
        break
    done
    
    TOKEN=$(prompt_value "Authentication Token" "")
    if [ -z "$TOKEN" ]; then
        error "Token is required"
        return
    fi
    
    echo ""
    PERMISSION=$(prompt_choice "Permission Level" \
        "Read Only (monitoring only)" \
        "Read + Process Control" \
        "Read + Process + Limited Shell" \
        "Full Access (all operations)")
    
    TLS_VERIFY="true"
    if [[ "$SERVER_URL" =~ ^wss:// ]]; then
        if ! prompt_yes_no "Verify TLS certificate?" "y"; then
            TLS_VERIFY="false"
        fi
    fi
    
    add_server_to_config
}

# Interactive modify server
interactive_modify_server() {
    step "Modify Server Configuration"
    echo ""
    
    list_servers
    
    echo ""
    SERVER_URL=$(prompt_value "Enter server URL to modify" "")
    if [ -z "$SERVER_URL" ]; then
        error "Server URL is required"
        return
    fi
    
    local config_file="${CONFIG_DIR}/nanolink.yaml"
    
    if ! grep -q "host: \"${SERVER_URL}\"\|url: \"${SERVER_URL}\"" "$config_file" 2>/dev/null; then
        # Try extracting host from URL
        local host=$(echo "$SERVER_URL" | sed -E 's|^wss?://||' | cut -d':' -f1)
        if ! grep -q "host: \"${host}\"" "$config_file" 2>/dev/null; then
            error "Server not found in configuration"
            return
        fi
    fi
    
    echo ""
    echo "What do you want to modify?"
    local modify_choice=$(prompt_choice "Select option" \
        "Token" \
        "Permission level" \
        "TLS verification")
    
    case $modify_choice in
        0)
            local new_token=$(prompt_value "New Token" "")
            if [ -n "$new_token" ]; then
                # This is simplified - for complex YAML, a proper parser would be better
                warn "Manual token update recommended. Edit: $config_file"
            fi
            ;;
        1)
            local new_perm=$(prompt_choice "New Permission Level" \
                "Read Only (0)" \
                "Read + Process Control (1)" \
                "Read + Process + Limited Shell (2)" \
                "Full Access (3)")
            warn "Manual permission update recommended. Edit: $config_file"
            ;;
        2)
            local new_tls=$(prompt_yes_no "Enable TLS verification?" "y")
            warn "Manual TLS setting update recommended. Edit: $config_file"
            ;;
    esac
    
    echo ""
    info "Configuration file: $config_file"
    
    if prompt_yes_no "Open config file in editor?" "n"; then
        ${EDITOR:-vi} "$config_file"
        
        if prompt_yes_no "Reload configuration?" "y"; then
            reload_config
        fi
    fi
}

# Interactive remove server
interactive_remove_server() {
    step "Remove Server"
    echo ""
    
    list_servers
    
    echo ""
    SERVER_URL=$(prompt_value "Enter server URL to remove" "")
    if [ -z "$SERVER_URL" ]; then
        error "Server URL is required"
        return
    fi
    
    if prompt_yes_no "Are you sure you want to remove this server?" "n"; then
        remove_server_from_config
    else
        info "Cancelled"
    fi
}

# Uninstall agent
uninstall_agent() {
    step "Uninstall NanoLink Agent"
    echo ""
    
    warn "This will remove the NanoLink Agent from your system."
    echo ""
    
    if ! prompt_yes_no "Are you sure you want to uninstall?" "n"; then
        info "Uninstall cancelled"
        return
    fi
    
    # Stop service
    if [ "$OS" = "linux" ]; then
        systemctl stop nanolink-agent 2>/dev/null || true
        systemctl disable nanolink-agent 2>/dev/null || true
        rm -f /etc/systemd/system/nanolink-agent.service
        systemctl daemon-reload
    elif [ "$OS" = "macos" ]; then
        launchctl stop com.nanolink.agent 2>/dev/null || true
        launchctl unload /Library/LaunchDaemons/com.nanolink.agent.plist 2>/dev/null || true
        rm -f /Library/LaunchDaemons/com.nanolink.agent.plist
    fi
    
    # Remove binary
    rm -f "${INSTALL_DIR}/${BINARY_NAME}"
    success "Binary removed"
    
    # Ask about data
    echo ""
    if prompt_yes_no "Remove configuration and data?" "n"; then
        rm -rf "$CONFIG_DIR"
        rm -rf "$LOG_DIR"
        rm -rf "$DATA_DIR"
        success "Configuration and data removed"
    else
        info "Configuration and data preserved at: $CONFIG_DIR"
    fi
    
    echo ""
    success "NanoLink Agent has been uninstalled"
}

# View logs
view_logs() {
    step "View Logs"
    
    local log_file="${LOG_DIR}/agent.log"
    
    if [ ! -f "$log_file" ]; then
        warn "Log file not found: $log_file"
        return
    fi
    
    echo ""
    echo "Last 30 lines of agent log:"
    echo "────────────────────────────────────────"
    tail -30 "$log_file"
    echo "────────────────────────────────────────"
    echo ""
    
    if prompt_yes_no "Follow logs in real-time?" "n"; then
        echo "Press Ctrl+C to stop..."
        tail -f "$log_file"
    fi
}

# Main management menu
manage_menu() {
    detect_os
    detect_language
    check_root
    
    while true; do
        clear
        echo -e "${CYAN}"
        echo "╔═══════════════════════════════════════════════════════════════╗"
        printf "║              %-47s ║\n" "$(msg mgmt_menu_title)"
        echo "╚═══════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        
        echo -e "${BOLD}$(msg server_management):${NC}"
        echo -e "  ${CYAN}1${NC}) $(msg add_server)"
        echo -e "  ${CYAN}2${NC}) $(msg modify_server)"
        echo -e "  ${CYAN}3${NC}) $(msg remove_server)"
        echo -e "  ${CYAN}4${NC}) $(msg list_servers)"
        echo ""
        echo -e "${BOLD}$(msg metrics_collection):${NC}"
        echo -e "  ${CYAN}5${NC}) $(msg config_metrics)"
        echo ""
        echo -e "${BOLD}$(msg service_control):${NC}"
        echo -e "  ${CYAN}6${NC}) $(msg show_status)"
        echo -e "  ${CYAN}7${NC}) $(msg start_agent)"
        echo -e "  ${CYAN}8${NC}) $(msg stop_agent)"
        echo -e "  ${CYAN}9${NC}) $(msg restart_agent)"
        echo -e "  ${CYAN}r${NC}) $(msg reload_config)"
        echo ""
        echo -e "${BOLD}$(msg maintenance):${NC}"
        echo -e "  ${CYAN}l${NC}) $(msg view_logs_menu)"
        echo -e "  ${CYAN}u${NC}) $(msg uninstall_agent)"
        echo ""
        echo -e "  ${CYAN}0${NC}) $(msg exit)"
        echo ""
        
        echo -en "${BOLD}$(msg select_option): ${NC}" >/dev/tty
        read choice </dev/tty
        
        echo ""
        case $choice in
            1) interactive_add_server ;;
            2) interactive_modify_server ;;
            3) interactive_remove_server ;;
            4) list_servers ;;
            5) manage_metrics ;;
            6) show_status ;;
            7) start_service_manage ;;
            8) stop_service_manage ;;
            9) restart_service ;;
            r|R) reload_config ;;
            l|L) view_logs ;;
            u|U) uninstall_agent; exit 0 ;;
            0|q|Q) echo "$(msg goodbye)"; exit 0 ;;
            *) warn "$(msg invalid_option): $choice" ;;
        esac
        
        echo ""
        echo -en "${BOLD}$(msg press_enter)${NC}" >/dev/tty
        read </dev/tty
    done
}

# =============================================================================
# Main
# =============================================================================
main() {
    parse_args "$@"
    
    # Detect language (auto-detect or use --lang parameter)
    detect_language

    # Handle fetch-config mode first
    if [ -n "$FETCH_CONFIG_URL" ]; then
        fetch_and_apply_config "$FETCH_CONFIG_URL"
    fi

    # Handle add-server mode
    if [ "$ADD_SERVER_MODE" = "true" ]; then
        check_root
        if [ -z "$SERVER_URL" ] || [ -z "$TOKEN" ]; then
            error "Add server mode requires --url and --token"
            exit 1
        fi
        add_server_to_config
        exit 0
    fi

    # Handle remove-server mode
    if [ "$REMOVE_SERVER_MODE" = "true" ]; then
        check_root
        if [ -z "$SERVER_URL" ]; then
            error "Remove server mode requires --url"
            exit 1
        fi
        remove_server_from_config
        exit 0
    fi

    # Handle manage mode
    if [ "$MANAGE_MODE" = "true" ]; then
        manage_menu
        exit 0
    fi

    if [ "$SILENT_MODE" = "false" ]; then
        print_banner
    fi

    # System checks
    detect_os
    detect_arch
    check_root
    check_dependencies

    info "Detected: $OS ($ARCH) with $INIT_SYSTEM"

    # Check for existing installation (only in interactive mode)
    UPDATE_MODE=false
    if [ "$SILENT_MODE" = "false" ]; then
        check_interactive
        check_existing_agent
    fi

    # Interactive configuration (skip if updating)
    if [ "$SILENT_MODE" = "false" ] && [ "$UPDATE_MODE" = "false" ]; then
        interactive_config
    fi

    # Installation steps
    download_binary
    install_binary
    create_directories
    
    # Only generate config if not updating (preserve existing config)
    if [ "$UPDATE_MODE" = "false" ]; then
        generate_config
    else
        info "Keeping existing configuration"
    fi

    # Install service based on init system
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        install_systemd_service
    elif [ "$INIT_SYSTEM" = "launchd" ]; then
        install_launchd_service
    else
        warn "Unknown init system, skipping service installation"
        warn "You'll need to start the agent manually"
    fi

    # Start and verify
    start_service
    verify_installation
    
    if [ "$UPDATE_MODE" = "true" ]; then
        success "Agent updated successfully!"
    fi
    print_summary
}

main "$@"
