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

info() { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

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
        error "Unsupported operating system: $OSTYPE"
        exit 1
    fi
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Please run as root (sudo)"
        exit 1
    fi
}

# Stop and disable service
stop_service() {
    info "Stopping service..."

    if [ "$OS" = "linux" ]; then
        if systemctl is-active --quiet nanolink-agent 2>/dev/null; then
            systemctl stop nanolink-agent
            success "Service stopped"
        fi

        if systemctl is-enabled --quiet nanolink-agent 2>/dev/null; then
            systemctl disable nanolink-agent
            success "Service disabled"
        fi
    elif [ "$OS" = "macos" ]; then
        if launchctl list | grep -q "com.nanolink.agent"; then
            launchctl stop com.nanolink.agent 2>/dev/null || true
            launchctl unload /Library/LaunchDaemons/com.nanolink.agent.plist 2>/dev/null || true
            success "Service stopped and unloaded"
        fi
    fi
}

# Remove service files
remove_service() {
    info "Removing service files..."

    if [ "$OS" = "linux" ]; then
        if [ -f /etc/systemd/system/nanolink-agent.service ]; then
            rm -f /etc/systemd/system/nanolink-agent.service
            systemctl daemon-reload
            success "systemd service removed"
        fi
    elif [ "$OS" = "macos" ]; then
        if [ -f /Library/LaunchDaemons/com.nanolink.agent.plist ]; then
            rm -f /Library/LaunchDaemons/com.nanolink.agent.plist
            success "launchd plist removed"
        fi
    fi
}

# Remove binary
remove_binary() {
    info "Removing binary..."

    if [ -f "${INSTALL_DIR}/${BINARY_NAME}" ]; then
        rm -f "${INSTALL_DIR}/${BINARY_NAME}"
        success "Binary removed"
    else
        warn "Binary not found"
    fi
}

# Remove configuration and data
remove_data() {
    echo ""
    echo -e "${YELLOW}Configuration and data directories:${NC}"
    echo -e "  Config: ${CONFIG_DIR}"
    echo -e "  Logs:   ${LOG_DIR}"
    echo -e "  Data:   ${DATA_DIR}"
    echo ""

    read -p "Remove configuration and data? (y/N) " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [ -d "$CONFIG_DIR" ]; then
            rm -rf "$CONFIG_DIR"
            success "Configuration removed"
        fi

        if [ -d "$LOG_DIR" ]; then
            rm -rf "$LOG_DIR"
            success "Logs removed"
        fi

        if [ -d "$DATA_DIR" ]; then
            rm -rf "$DATA_DIR"
            success "Data removed"
        fi
    else
        info "Configuration and data preserved"
    fi
}

# Main
main() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}            ${RED}NanoLink Agent Uninstallation${NC}                      ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    detect_os
    check_root

    info "Detected: $OS"
    echo ""

    read -p "Are you sure you want to uninstall NanoLink Agent? (y/N) " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Aborted"
        exit 0
    fi

    echo ""
    stop_service
    remove_service
    remove_binary
    remove_data

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}              ${GREEN}Uninstallation Complete!${NC}                        ${GREEN}║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

main "$@"
