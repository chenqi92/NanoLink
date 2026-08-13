[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("menu", "start", "stop", "deploy", "deploy-dry-run", "version", "install-hooks", "remove-bom")]
    [string]$Action = "menu",
    [string]$Version = "",
    [string]$ConfigPath = "",
    [switch]$AllowDirty,
    [switch]$SkipChecks,
    [switch]$DryRun,
    [switch]$NoBrowser,
    [switch]$SkipBackendBuild,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$taskRoot = Join-Path $PSScriptRoot "tasks"

function Invoke-NanoTask {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string[]]$Arguments = @()
    )

    $taskPath = Join-Path $taskRoot $Name
    if (-not (Test-Path -LiteralPath $taskPath)) {
        throw "Internal task not found: $taskPath"
    }

    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $taskPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE"
    }
}

function Get-DeployArguments([switch]$ForceDryRun) {
    $taskArguments = @()
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        $taskArguments += @("-ConfigPath", $ConfigPath)
    }
    if ($AllowDirty) { $taskArguments += "-AllowDirty" }
    if ($SkipChecks) { $taskArguments += "-SkipChecks" }
    if ($DryRun -or $ForceDryRun) { $taskArguments += "-DryRun" }
    return $taskArguments
}

function Confirm-ProductionDeployment {
    if ($Yes) { return $true }
    Write-Host "This will build and deploy NanoOps Server to production." -ForegroundColor Yellow
    return (Read-Host "Type DEPLOY to continue") -ceq "DEPLOY"
}

function Invoke-NanoAction([string]$SelectedAction) {
    Push-Location $repoRoot
    try {
        switch ($SelectedAction) {
            "start" {
                $taskArguments = @()
                if ($NoBrowser) { $taskArguments += "-NoBrowser" }
                if ($SkipBackendBuild) { $taskArguments += "-SkipBackendBuild" }
                Invoke-NanoTask "start-dev.ps1" $taskArguments
            }
            "stop" {
                Invoke-NanoTask "stop-dev.ps1"
            }
            "deploy" {
                if (-not (Confirm-ProductionDeployment)) {
                    Write-Host "Deployment cancelled." -ForegroundColor Yellow
                    return
                }
                Invoke-NanoTask "deploy-server.ps1" (Get-DeployArguments)
            }
            "deploy-dry-run" {
                Invoke-NanoTask "deploy-server.ps1" (Get-DeployArguments -ForceDryRun)
            }
            "version" {
                $newVersion = $Version
                if ([string]::IsNullOrWhiteSpace($newVersion)) {
                    $newVersion = Read-Host "New semantic version (for example 0.5.0)"
                }
                if ([string]::IsNullOrWhiteSpace($newVersion)) {
                    throw "A version is required."
                }
                Invoke-NanoTask "bump-version.ps1" @($newVersion)
            }
            "install-hooks" {
                Invoke-NanoTask "install-hooks.ps1"
            }
            "remove-bom" {
                $taskArguments = @()
                if ($DryRun) { $taskArguments += "-DryRun" }
                Invoke-NanoTask "remove-bom.ps1" $taskArguments
            }
            default {
                throw "Unsupported action: $SelectedAction"
            }
        }
    } finally {
        Pop-Location
    }
}

function Show-NanoMenu {
    while ($true) {
        Write-Host ""
        Write-Host "NanoOps Project Console" -ForegroundColor Cyan
        Write-Host "  1. Start development environment"
        Write-Host "  2. Stop development environment"
        Write-Host "  3. Deploy Server to production"
        Write-Host "  4. Validate deployment (DryRun)"
        Write-Host "  5. Bump project version"
        Write-Host "  6. Install Git hooks"
        Write-Host "  7. Scan and remove BOM"
        Write-Host "  0. Exit"
        $choice = Read-Host "Select"

        $selectedAction = switch ($choice) {
            "1" { "start" }
            "2" { "stop" }
            "3" { "deploy" }
            "4" { "deploy-dry-run" }
            "5" { "version" }
            "6" { "install-hooks" }
            "7" { "remove-bom" }
            "0" { return }
            default { $null }
        }

        if (-not $selectedAction) {
            Write-Host "Invalid selection." -ForegroundColor Yellow
            continue
        }

        try {
            Invoke-NanoAction $selectedAction
        } catch {
            Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        }
        [void](Read-Host "Press Enter to return to the menu")
    }
}

try {
    if ($Action -eq "menu") {
        Show-NanoMenu
    } else {
        Invoke-NanoAction $Action
    }
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
