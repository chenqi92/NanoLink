# NanoLink Version Bump Script for Windows
# Usage: .\bump-version.ps1 <new_version>
# Example: .\bump-version.ps1 0.2.0

param(
    [Parameter(Position=0)]
    [string]$NewVersion
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir

# Colors
function Write-Info { Write-Host "[INFO] $args" -ForegroundColor Blue }
function Write-Success { Write-Host "[SUCCESS] $args" -ForegroundColor Green }
function Write-Warn { Write-Host "[WARN] $args" -ForegroundColor Yellow }
function Write-Err { Write-Host "[ERROR] $args" -ForegroundColor Red; exit 1 }

# Validate version format (semver)
function Test-Version {
    param([string]$Version)
    if ($Version -notmatch '^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?$') {
        Write-Err "Invalid version format: $Version. Expected semver format (e.g., 1.2.3, 1.2.3-beta.1)"
    }
}

# Get current version from version.json
function Get-CurrentVersion {
    $versionFile = Join-Path $ScriptDir "version.json"
    $json = Get-Content $versionFile -Raw | ConvertFrom-Json
    return $json.version
}

# Update version in a file
function Update-FileVersion {
    param(
        [string]$RelativePath,
        [string]$OldVersion,
        [string]$NewVersion
    )

    $FullPath = Join-Path $RootDir $RelativePath

    if (-not (Test-Path $FullPath)) {
        Write-Warn "File not found: $RelativePath"
        return
    }

    try {
        $content = Get-Content $FullPath -Raw -Encoding UTF8
        $newContent = $content -replace [regex]::Escape($OldVersion), $NewVersion

        if ($content -ne $newContent) {
            # Preserve line endings
            $newContent | Set-Content $FullPath -NoNewline -Encoding UTF8
            Write-Success "Updated: $RelativePath"
        } else {
            Write-Warn "No changes in: $RelativePath"
        }
    }
    catch {
        Write-Warn "Failed to update: $RelativePath - $_"
    }
}

# Main
function Main {
    if ([string]::IsNullOrEmpty($NewVersion)) {
        Write-Host "Usage: .\bump-version.ps1 <new_version>"
        Write-Host ""
        Write-Host "Examples:"
        Write-Host "  .\bump-version.ps1 0.2.0"
        Write-Host "  .\bump-version.ps1 1.0.0-beta.1"
        Write-Host ""
        $current = Get-CurrentVersion
        Write-Host "Current version: $current"
        exit 0
    }

    Test-Version $NewVersion

    $CurrentVersion = Get-CurrentVersion

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "  NanoLink Version Bump"
    Write-Host "=========================================="
    Write-Host ""
    Write-Info "Current version: $CurrentVersion"
    Write-Info "New version:     $NewVersion"
    Write-Host ""

    # Confirm
    $confirm = Read-Host "Continue? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Info "Aborted."
        exit 0
    }

    Write-Host ""
    Write-Info "Updating version in all files..."
    Write-Host ""

    # Files to update
    $files = @(
        "agent/Cargo.toml",
        "agent/src/main.rs",
        "sdk/java/pom.xml",
        "sdk/go/nanolink/version.go",
        "sdk/python/pyproject.toml",
        "sdk/python/nanolink/__init__.py",
        "dashboard/package.json",
        "apps/server/cmd/main.go",
        "apps/server/web/package.json",
        "apps/desktop/pubspec.yaml",
        "demo/spring-boot/pom.xml",
        "scripts/version.json"
    )

    foreach ($file in $files) {
        Update-FileVersion -RelativePath $file -OldVersion $CurrentVersion -NewVersion $NewVersion
    }

    Write-Host ""
    Write-Success "Version bumped from $CurrentVersion to $NewVersion"
    Write-Host ""
    Write-Info "Next steps:"
    Write-Host "  1. Review changes: git diff"
    Write-Host "  2. Commit: git commit -am `"chore: bump version to $NewVersion`""
    Write-Host "  3. Tag: git tag v$NewVersion"
    Write-Host "  4. Push: git push && git push --tags"
    Write-Host ""
}

Main
