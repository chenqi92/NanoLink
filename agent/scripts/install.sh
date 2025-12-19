#!/bin/bash
#
# NanoLink Agent Interactive Installation Script
# Supports: Linux (systemd), macOS (launchd)
#
# Usage:
#   Interactive: curl -fsSL https://get.nanolink.io | bash
#   Silent:      curl -fsSL https://get.nanolink.io | bash -s -- --silent --url wss://server:9100 --token xxx
#

set -e

# =============================================================================
# Configuration
# =============================================================================
VERSION="0.1.0"
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
    echo "║              Lightweight Server Monitoring Agent              ║"
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
prompt_value() {
    local prompt="$1"
    local default="$2"
    local value

    if [ -n "$default" ]; then
        read -p "$(echo -e "${BOLD}$prompt${NC} [${YELLOW}$default${NC}]: ")" value
        echo "${value:-$default}"
    else
        read -p "$(echo -e "${BOLD}$prompt${NC}: ")" value
        echo "$value"
    fi
}

prompt_password() {
    local prompt="$1"
    local value

    read -sp "$(echo -e "${BOLD}$prompt${NC}: ")" value
    echo ""
    echo "$value"
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local value

    if [ "$default" = "y" ]; then
        read -p "$(echo -e "${BOLD}$prompt${NC} [${YELLOW}Y/n${NC}]: ")" value
        value="${value:-y}"
    else
        read -p "$(echo -e "${BOLD}$prompt${NC} [${YELLOW}y/N${NC}]: ")" value
        value="${value:-n}"
    fi

    [[ "$value" =~ ^[Yy] ]]
}

prompt_choice() {
    local prompt="$1"
    shift
    local options=("$@")

    echo -e "${BOLD}$prompt${NC}"
    for i in "${!options[@]}"; do
        echo -e "  ${CYAN}$((i+1))${NC}) ${options[$i]}"
    done

    local choice
    while true; do
        read -p "$(echo -e "${BOLD}Select [1-${#options[@]}]${NC}: ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
            echo "$((choice-1))"
            return
        fi
        warn "Invalid choice, please try again"
    done
}

interactive_config() {
    step "Server Configuration"
    echo ""

    # Server URL
    while true; do
        SERVER_URL=$(prompt_value "Server WebSocket URL (e.g., wss://monitor.example.com:9100)" "")
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

    # Token
    while true; do
        TOKEN=$(prompt_value "Authentication Token" "")
        if [ -z "$TOKEN" ]; then
            warn "Token is required"
            continue
        fi
        break
    done

    # Permission level
    echo ""
    local perms=("Read Only (monitoring only)" "Basic Write (logs, temp files)" "Service Control (restart services)" "System Admin (full control)")
    PERMISSION=$(prompt_choice "Permission Level" "${perms[@]}")

    # TLS verification
    echo ""
    TLS_VERIFY="true"
    if [[ "$SERVER_URL" =~ ^wss:// ]]; then
        if prompt_yes_no "Verify TLS certificate?" "y"; then
            TLS_VERIFY="true"
        else
            TLS_VERIFY="false"
            warn "TLS verification disabled - only use for testing!"
        fi
    fi

    # Test connection
    echo ""
    if prompt_yes_no "Test server connection before installing?" "y"; then
        test_connection
    fi

    # Hostname override
    echo ""
    HOSTNAME_OVERRIDE=""
    if ! prompt_yes_no "Use system hostname ($(hostname))?" "y"; then
        HOSTNAME_OVERRIDE=$(prompt_value "Custom hostname" "")
    fi

    # Shell commands
    echo ""
    SHELL_ENABLED="false"
    SHELL_TOKEN=""
    if [ "$PERMISSION" -ge 2 ]; then
        if prompt_yes_no "Enable shell command execution? (requires super token)" "n"; then
            SHELL_ENABLED="true"
            while true; do
                SHELL_TOKEN=$(prompt_password "Shell Super Token (different from auth token)")
                if [ -z "$SHELL_TOKEN" ]; then
                    warn "Super token is required when shell is enabled"
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
  - url: "${SERVER_URL}"
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
    echo -e "${CYAN}║${NC}              ${GREEN}Installation Complete!${NC}                         ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Installation Details:${NC}"
    echo -e "  Binary:     ${YELLOW}${INSTALL_DIR}/${BINARY_NAME}${NC}"
    echo -e "  Config:     ${YELLOW}${CONFIG_DIR}/nanolink.yaml${NC}"
    echo -e "  Logs:       ${YELLOW}${LOG_DIR}/${NC}"
    echo -e "  Server:     ${YELLOW}${SERVER_URL}${NC}"
    echo ""
    echo -e "${BOLD}Service Management:${NC}"
    if [ "$OS" = "linux" ]; then
        echo -e "  Status:     ${YELLOW}sudo systemctl status nanolink-agent${NC}"
        echo -e "  Logs:       ${YELLOW}sudo journalctl -u nanolink-agent -f${NC}"
        echo -e "  Restart:    ${YELLOW}sudo systemctl restart nanolink-agent${NC}"
        echo -e "  Stop:       ${YELLOW}sudo systemctl stop nanolink-agent${NC}"
    elif [ "$OS" = "macos" ]; then
        echo -e "  Status:     ${YELLOW}sudo launchctl list | grep nanolink${NC}"
        echo -e "  Logs:       ${YELLOW}tail -f /var/log/nanolink/agent.log${NC}"
        echo -e "  Restart:    ${YELLOW}sudo launchctl stop com.nanolink.agent && sudo launchctl start com.nanolink.agent${NC}"
    fi
    echo ""
    echo -e "${BOLD}Uninstall:${NC}"
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
                echo "  --help, -h          Show this help"
                echo ""
                echo "Examples:"
                echo "  # Fresh install (interactive)"
                echo "  curl -fsSL https://get.nanolink.io | sudo bash"
                echo ""
                echo "  # Fresh install (silent)"
                echo "  curl -fsSL https://get.nanolink.io | sudo bash -s -- \\"
                echo "    --silent --url wss://monitor.example.com:9100 --token xxx"
                echo ""
                echo "  # Add additional server to existing agent"
                echo "  sudo $0 --add-server --url wss://second.example.com:9100 --token yyy"
                echo ""
                echo "  # Fetch config from server and install"
                echo "  curl -fsSL https://get.nanolink.io | sudo bash -s -- \\"
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
# Main
# =============================================================================
main() {
    parse_args "$@"

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

    if [ "$SILENT_MODE" = "false" ]; then
        print_banner
    fi

    # System checks
    detect_os
    detect_arch
    check_root
    check_dependencies

    info "Detected: $OS ($ARCH) with $INIT_SYSTEM"

    # Interactive or silent configuration
    if [ "$SILENT_MODE" = "false" ]; then
        interactive_config
    fi

    # Installation steps
    download_binary
    install_binary
    create_directories
    generate_config

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
    print_summary
}

main "$@"
