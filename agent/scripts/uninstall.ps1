#Requires -RunAsAdministrator
<#
.SYNOPSIS
    NanoLink Agent Uninstallation Script for Windows

.DESCRIPTION
    Removes the NanoLink monitoring agent and associated files.
#>

$ErrorActionPreference = "Stop"

# Configuration
$ServiceName = "NanoLinkAgent"
$InstallDir = "C:\Program Files\NanoLink"
$ConfigDir = "C:\ProgramData\NanoLink"
$LogDir = "C:\ProgramData\NanoLink\logs"

function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Err { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

function Stop-ExistingService {
    Write-Info "Stopping service..."

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -eq "Running") {
            Stop-Service -Name $ServiceName -Force
            Write-Success "Service stopped"
        }

        Write-Info "Removing service..."
        sc.exe delete $ServiceName | Out-Null
        Start-Sleep -Seconds 2
        Write-Success "Service removed"
    } else {
        Write-Warn "Service not found"
    }
}

function Remove-Binary {
    Write-Info "Removing binary..."

    if (Test-Path $InstallDir) {
        Remove-Item -Path $InstallDir -Recurse -Force
        Write-Success "Binary removed"
    } else {
        Write-Warn "Binary directory not found"
    }
}

function Remove-Data {
    Write-Host ""
    Write-Host "Configuration and data directories:" -ForegroundColor Yellow
    Write-Host "  Config: $ConfigDir"
    Write-Host "  Logs:   $LogDir"
    Write-Host ""

    $response = Read-Host -Prompt "Remove configuration and data? (y/N)"

    if ($response -match "^[Yy]$") {
        if (Test-Path $ConfigDir) {
            Remove-Item -Path $ConfigDir -Recurse -Force
            Write-Success "Configuration and data removed"
        }
    } else {
        Write-Info "Configuration and data preserved"
    }
}

function Main {
    Write-Host ""
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host "          NanoLink Agent Uninstallation" -ForegroundColor Red
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host ""

    $response = Read-Host -Prompt "Are you sure you want to uninstall NanoLink Agent? (y/N)"
    if ($response -notmatch "^[Yy]$") {
        Write-Info "Aborted"
        return
    }

    Write-Host ""
    Stop-ExistingService
    Remove-Binary
    Remove-Data

    Write-Host ""
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host "          Uninstallation Complete!" -ForegroundColor Green
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host ""
}

Main
