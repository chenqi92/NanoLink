#Requires -RunAsAdministrator
<#
.SYNOPSIS
    NanoOps Agent Uninstallation Script for Windows

.DESCRIPTION
    Removes the NanoOps monitoring agent and associated files.
#>

[CmdletBinding()]
param(
    [ValidateSet("en", "zh")]
    [string]$Lang
)

$ErrorActionPreference = "Stop"

# Configuration
$ServiceName = "NanoLinkAgent"
$InstallDir = "C:\Program Files\NanoOps"
$ConfigDir = "C:\ProgramData\NanoOps"
$LogDir = "C:\ProgramData\NanoOps\logs"

$Script:ScriptLang = if ($Lang) {
    $Lang
} elseif ($PSUICulture -like "zh*") {
    "zh"
} else {
    "en"
}

$Script:EnMsgs = @{
    info = "INFO"
    success = "SUCCESS"
    warn = "WARN"
    error = "ERROR"
    stopping_service = "Stopping service..."
    service_stopped = "Service stopped"
    removing_service = "Removing service..."
    service_removed = "Service removed"
    service_not_found = "Service not found"
    removing_binary = "Removing binary..."
    binary_removed = "Binary removed"
    binary_not_found = "Binary directory not found"
    data_directories = "Configuration and data directories:"
    config = "Config"
    logs = "Logs"
    remove_data_prompt = "Remove configuration and data? (y/N)"
    data_removed = "Configuration and data removed"
    data_preserved = "Configuration and data preserved"
    title = "NanoOps Agent Uninstallation"
    confirm = "Are you sure you want to uninstall NanoOps Agent? (y/N)"
    aborted = "Aborted"
    complete = "Uninstallation Complete!"
}

$Script:ZhMsgs = @{
    info = "信息"
    success = "成功"
    warn = "警告"
    error = "错误"
    stopping_service = "正在停止服务..."
    service_stopped = "服务已停止"
    removing_service = "正在删除服务..."
    service_removed = "服务已删除"
    service_not_found = "未找到服务"
    removing_binary = "正在删除程序文件..."
    binary_removed = "程序文件已删除"
    binary_not_found = "未找到程序目录"
    data_directories = "配置和数据目录："
    config = "配置"
    logs = "日志"
    remove_data_prompt = "是否删除配置和数据？(y/N)"
    data_removed = "配置和数据已删除"
    data_preserved = "已保留配置和数据"
    title = "卸载 NanoOps Agent"
    confirm = "确定要卸载 NanoOps Agent 吗？(y/N)"
    aborted = "已取消"
    complete = "卸载完成！"
}

function Get-Msg {
    param([string]$Key)
    $dictionary = if ($Script:ScriptLang -eq "zh") { $Script:ZhMsgs } else { $Script:EnMsgs }
    if ($dictionary.ContainsKey($Key)) { return $dictionary[$Key] }
    if ($Script:EnMsgs.ContainsKey($Key)) { return $Script:EnMsgs[$Key] }
    return $Key
}

function Write-Info { param([string]$Message) Write-Host "[$(Get-Msg 'info')] $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "[$(Get-Msg 'success')] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[$(Get-Msg 'warn')] $Message" -ForegroundColor Yellow }
function Write-Err { param([string]$Message) Write-Host "[$(Get-Msg 'error')] $Message" -ForegroundColor Red }

function Stop-ExistingService {
    Write-Info (Get-Msg "stopping_service")

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -eq "Running") {
            Stop-Service -Name $ServiceName -Force
            Write-Success (Get-Msg "service_stopped")
        }

        Write-Info (Get-Msg "removing_service")
        sc.exe delete $ServiceName | Out-Null
        Start-Sleep -Seconds 2
        Write-Success (Get-Msg "service_removed")
    } else {
        Write-Warn (Get-Msg "service_not_found")
    }
}

function Remove-Binary {
    Write-Info (Get-Msg "removing_binary")

    if (Test-Path $InstallDir) {
        Remove-Item -Path $InstallDir -Recurse -Force
        Write-Success (Get-Msg "binary_removed")
    } else {
        Write-Warn (Get-Msg "binary_not_found")
    }
}

function Remove-Data {
    Write-Host ""
    Write-Host (Get-Msg "data_directories") -ForegroundColor Yellow
    Write-Host "  $(Get-Msg 'config'): $ConfigDir"
    Write-Host "  $(Get-Msg 'logs'):   $LogDir"
    Write-Host ""

    $response = Read-Host -Prompt (Get-Msg "remove_data_prompt")

    if ($response -match "^[Yy是]$") {
        if (Test-Path $ConfigDir) {
            Remove-Item -Path $ConfigDir -Recurse -Force
            Write-Success (Get-Msg "data_removed")
        }
    } else {
        Write-Info (Get-Msg "data_preserved")
    }
}

function Main {
    Write-Host ""
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host "          $(Get-Msg 'title')" -ForegroundColor Red
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host ""

    $response = Read-Host -Prompt (Get-Msg "confirm")
    if ($response -notmatch "^[Yy是]$") {
        Write-Info (Get-Msg "aborted")
        return
    }

    Write-Host ""
    Stop-ExistingService
    Remove-Binary
    Remove-Data

    Write-Host ""
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host "          $(Get-Msg 'complete')" -ForegroundColor Green
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host ""
}

Main
