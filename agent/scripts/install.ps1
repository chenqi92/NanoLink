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
    Server WebSocket URL (required in silent mode)

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
    .\install.ps1 -Silent -Url "wss://server:9100" -Token "your_token"
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
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# =============================================================================
# Configuration
# =============================================================================
$Script:VERSION = "0.2.6"
$Script:ServiceName = "NanoLinkAgent"
$Script:ServiceDisplayName = "NanoLink Monitoring Agent"
$Script:InstallDir = "C:\Program Files\NanoLink"
$Script:ConfigDir = "C:\ProgramData\NanoLink"
$Script:LogDir = "C:\ProgramData\NanoLink\logs"
$Script:BinaryName = "nanolink-agent.exe"
$Script:GitHubRepo = "chenqi92/NanoLink"

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

    # Server URL
    while ($true) {
        $Script:ServerUrl = Read-PromptValue -Prompt "Server WebSocket URL (e.g., wss://monitor.example.com:9100)" -Required
        if ($Script:ServerUrl -notmatch "^wss?://") {
            Write-Warn "URL must start with ws:// or wss://"
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

    # TLS verification
    Write-Host ""
    $Script:TlsVerify = $true
    if ($Script:ServerUrl -match "^wss://") {
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
  - host: "$([System.Uri]::new($Script:ServerUrl).Host)"
    port: $(if (([System.Uri]::new($Script:ServerUrl)).Port -gt 0) { ([System.Uri]::new($Script:ServerUrl)).Port } else { 39100 })
    tls_enabled: $($Script:ServerUrl -match '^wss://' ? 'true' : 'false')
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
  -Url URL          Server WebSocket URL (IP or domain)
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

  -Help             Show this help

Examples:
  # Interactive installation
  .\install.ps1

  # Silent installation
  .\install.ps1 -Silent -Url "wss://server:9100" -Token "your_token"

  # Add additional server to existing agent
  .\install.ps1 -AddServer -Url "wss://second.example.com:9100" -Token "yyy"

  # Remove a server
  .\install.ps1 -RemoveServer -Url "wss://old.example.com:9100"

  # Fetch config from server and install
  .\install.ps1 -FetchConfig "http://monitor.example.com:8080/api/config/generate"
"@
}

# =============================================================================
# Main
# =============================================================================
function Main {
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

    # Interactive configuration if not silent
    if (-not $Silent) {
        Get-InteractiveConfig
    }

    # Installation steps
    Stop-ExistingService
    Remove-ExistingService
    New-Directories
    Get-Binary
    New-Configuration
    Install-Service
    Start-InstalledService
    Test-Installation
    Write-Summary
}

Main
