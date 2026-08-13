#!/bin/bash
#
# NanoLink Agent Uninstallation Script
# Supports: Linux (systemd), macOS (launchd)
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Internationalization
SCRIPT_LANG=""
SHOW_HELP="false"

detect_language() {
    if [ -n "$SCRIPT_LANG" ]; then
        return
    fi

    local sys_lang="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
    if [[ "$sys_lang" =~ ^zh ]] || [[ "$sys_lang" =~ [Cc]hinese ]]; then
        SCRIPT_LANG="zh"
    else
        SCRIPT_LANG="en"
    fi
}

msg() {
    local key="$1"
    declare -A en_msgs=(
        ["info"]="INFO"
        ["success"]="SUCCESS"
        ["warn"]="WARN"
        ["error"]="ERROR"
        ["usage"]="Usage: uninstall.sh [--lang en|zh]"
        ["unsupported_os"]="Unsupported operating system"
        ["root_required"]="Please run as root (sudo)"
        ["stopping_service"]="Stopping service..."
        ["service_stopped"]="Service stopped"
        ["service_disabled"]="Service disabled"
        ["service_stopped_unloaded"]="Service stopped and unloaded"
        ["removing_service_files"]="Removing service files..."
        ["systemd_removed"]="systemd service removed"
        ["launchd_removed"]="launchd plist removed"
        ["removing_binary"]="Removing binary..."
        ["binary_removed"]="Binary removed"
        ["binary_not_found"]="Binary not found"
        ["data_directories"]="Configuration and data directories:"
        ["config"]="Config"
        ["logs"]="Logs"
        ["data"]="Data"
        ["remove_data_prompt"]="Remove configuration and data? (y/N)"
        ["config_removed"]="Configuration removed"
        ["logs_removed"]="Logs removed"
        ["data_removed"]="Data removed"
        ["data_preserved"]="Configuration and data preserved"
        ["title"]="NanoLink Agent Uninstallation"
        ["detected"]="Detected"
        ["confirm"]="Are you sure you want to uninstall NanoLink Agent? (y/N)"
        ["aborted"]="Aborted"
        ["complete"]="Uninstallation Complete!"
    )
    declare -A zh_msgs=(
        ["info"]="信息"
        ["success"]="成功"
        ["warn"]="警告"
        ["error"]="错误"
        ["usage"]="用法：uninstall.sh [--lang en|zh]"
        ["unsupported_os"]="不支持的操作系统"
        ["root_required"]="请以 root 权限运行（sudo）"
        ["stopping_service"]="正在停止服务..."
        ["service_stopped"]="服务已停止"
        ["service_disabled"]="服务已禁用"
        ["service_stopped_unloaded"]="服务已停止并卸载"
        ["removing_service_files"]="正在删除服务文件..."
        ["systemd_removed"]="systemd 服务已删除"
        ["launchd_removed"]="launchd plist 已删除"
        ["removing_binary"]="正在删除程序文件..."
        ["binary_removed"]="程序文件已删除"
        ["binary_not_found"]="未找到程序文件"
        ["data_directories"]="配置和数据目录："
        ["config"]="配置"
        ["logs"]="日志"
        ["data"]="数据"
        ["remove_data_prompt"]="是否删除配置和数据？(y/N)"
        ["config_removed"]="配置已删除"
        ["logs_removed"]="日志已删除"
        ["data_removed"]="数据已删除"
        ["data_preserved"]="已保留配置和数据"
        ["title"]="卸载 NanoLink Agent"
        ["detected"]="检测到"
        ["confirm"]="确定要卸载 NanoLink Agent 吗？(y/N)"
        ["aborted"]="已取消"
        ["complete"]="卸载完成！"
    )

    if [ "$SCRIPT_LANG" = "zh" ]; then
        echo "${zh_msgs[$key]:-${en_msgs[$key]:-$key}}"
    else
        echo "${en_msgs[$key]:-$key}"
    fi
}

info() { echo -e "${CYAN}[$(msg info)]${NC} $1"; }
success() { echo -e "${GREEN}[$(msg success)]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(msg warn)]${NC} $1"; }
error() { echo -e "${RED}[$(msg error)]${NC} $1"; }

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --lang)
                SCRIPT_LANG="${2:-}"
                shift 2
                ;;
            --lang=*)
                SCRIPT_LANG="${1#*=}"
                shift
                ;;
            -h|--help)
                SHOW_HELP="true"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [ "$SCRIPT_LANG" != "en" ] && [ "$SCRIPT_LANG" != "zh" ]; then
        SCRIPT_LANG=""
    fi
}

# Configuration
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/nanolink"
LOG_DIR="/var/log/nanolink"
DATA_DIR="/var/lib/nanolink"
SERVICE_NAME="nanolink-agent"
BINARY_NAME="nanolink-agent"

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    else
        error "$(msg unsupported_os): $OSTYPE"
        exit 1
    fi
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "$(msg root_required)"
        exit 1
    fi
}

# Stop and disable service
stop_service() {
    info "$(msg stopping_service)"

    if [ "$OS" = "linux" ]; then
        if systemctl is-active --quiet nanolink-agent 2>/dev/null; then
            systemctl stop nanolink-agent
            success "$(msg service_stopped)"
        fi

        if systemctl is-enabled --quiet nanolink-agent 2>/dev/null; then
            systemctl disable nanolink-agent
            success "$(msg service_disabled)"
        fi
    elif [ "$OS" = "macos" ]; then
        if launchctl list | grep -q "com.nanolink.agent"; then
            launchctl stop com.nanolink.agent 2>/dev/null || true
            launchctl unload /Library/LaunchDaemons/com.nanolink.agent.plist 2>/dev/null || true
            success "$(msg service_stopped_unloaded)"
        fi
    fi
}

# Remove service files
remove_service() {
    info "$(msg removing_service_files)"

    if [ "$OS" = "linux" ]; then
        if [ -f /etc/systemd/system/nanolink-agent.service ]; then
            rm -f /etc/systemd/system/nanolink-agent.service
            systemctl daemon-reload
            success "$(msg systemd_removed)"
        fi
    elif [ "$OS" = "macos" ]; then
        if [ -f /Library/LaunchDaemons/com.nanolink.agent.plist ]; then
            rm -f /Library/LaunchDaemons/com.nanolink.agent.plist
            success "$(msg launchd_removed)"
        fi
    fi
}

# Remove binary
remove_binary() {
    info "$(msg removing_binary)"

    if [ -f "${INSTALL_DIR}/${BINARY_NAME}" ]; then
        rm -f "${INSTALL_DIR}/${BINARY_NAME}"
        success "$(msg binary_removed)"
    else
        warn "$(msg binary_not_found)"
    fi
}

# Remove configuration and data
remove_data() {
    echo ""
    echo -e "${YELLOW}$(msg data_directories)${NC}"
    echo -e "  $(msg config): ${CONFIG_DIR}"
    echo -e "  $(msg logs):   ${LOG_DIR}"
    echo -e "  $(msg data):   ${DATA_DIR}"
    echo ""

    read -p "$(msg remove_data_prompt) " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy是]$ ]]; then
        if [ -d "$CONFIG_DIR" ]; then
            rm -rf "$CONFIG_DIR"
            success "$(msg config_removed)"
        fi

        if [ -d "$LOG_DIR" ]; then
            rm -rf "$LOG_DIR"
            success "$(msg logs_removed)"
        fi

        if [ -d "$DATA_DIR" ]; then
            rm -rf "$DATA_DIR"
            success "$(msg data_removed)"
        fi
    else
        info "$(msg data_preserved)"
    fi
}

# Main
main() {
    parse_args "$@"
    detect_language

    if [ "$SHOW_HELP" = "true" ]; then
        echo "$(msg usage)"
        exit 0
    fi

    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${RED}$(msg title)${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    detect_os
    check_root

    info "$(msg detected): $OS"
    echo ""

    read -p "$(msg confirm) " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy是]$ ]]; then
        info "$(msg aborted)"
        exit 0
    fi

    echo ""
    stop_service
    remove_service
    remove_binary
    remove_data

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${GREEN}$(msg complete)${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

main "$@"
