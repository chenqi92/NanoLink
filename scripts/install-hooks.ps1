<#
.SYNOPSIS
    Install Git hooks for NanoLink project.

.DESCRIPTION
    This script installs the pre-commit hook that automatically removes BOM characters
    from source files before each commit.

.EXAMPLE
    .\install-hooks.ps1
    # Installs Git hooks
#>

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$RootDir = Split-Path $ScriptDir -Parent
$HooksDir = Join-Path $RootDir ".git\hooks"
$HooksSrc = Join-Path $ScriptDir "hooks"

Write-Host "Installing Git hooks for NanoLink..." -ForegroundColor Cyan

# Check if we're in a git repository
if (-not (Test-Path (Join-Path $RootDir ".git"))) {
    Write-Host "Error: Not a git repository. Run this script from the NanoLink root directory." -ForegroundColor Red
    exit 1
}

# Create hooks directory if it doesn't exist
if (-not (Test-Path $HooksDir)) {
    New-Item -ItemType Directory -Path $HooksDir -Force | Out-Null
}

# Install pre-commit hook
$PreCommitSrc = Join-Path $HooksSrc "pre-commit"
$PreCommitDst = Join-Path $HooksDir "pre-commit"

if (Test-Path $PreCommitSrc) {
    Copy-Item $PreCommitSrc $PreCommitDst -Force
    Write-Host "✓ Installed pre-commit hook" -ForegroundColor Green
}
else {
    Write-Host "Error: pre-commit hook source not found at $PreCommitSrc" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Git hooks installed successfully!" -ForegroundColor Green
Write-Host "The pre-commit hook will automatically run BOM removal before each commit."
