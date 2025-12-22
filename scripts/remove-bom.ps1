<#
.SYNOPSIS
    Remove BOM (Byte Order Mark) from text files in the NanoLink project.

.DESCRIPTION
    This script scans specified file types for UTF-8 BOM (0xEF 0xBB 0xBF) and removes it.
    BOM characters can cause build failures in Go, Python, and Docker.

.PARAMETER Path
    Root directory to scan. Defaults to repository root.

.PARAMETER Extensions
    File extensions to check. Defaults to common source files.

.PARAMETER DryRun
    If specified, only report files with BOM without modifying them.

.EXAMPLE
    .\remove-bom.ps1
    # Scan and fix all files in the repository

.EXAMPLE
    .\remove-bom.ps1 -DryRun
    # Only report files with BOM, don't fix them
#>

param(
    [string]$Path = (Split-Path $PSScriptRoot -Parent),
    [string[]]$Extensions = @("*.go", "*.py", "*.rs", "*.toml", "*.json", "*.yaml", "*.yml", "*.java", "*.tsx", "*.ts", "*.js"),
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# UTF-8 BOM bytes
$BOM = [byte[]]@(0xEF, 0xBB, 0xBF)

# Also check VERSION file specifically
$SpecificFiles = @(
    "VERSION"
)

Write-Host "Scanning for BOM characters in: $Path" -ForegroundColor Cyan
Write-Host "Extensions: $($Extensions -join ', ')" -ForegroundColor Gray

$foundCount = 0
$fixedCount = 0

function Test-HasBOM {
    param([string]$FilePath)
    
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    if ($bytes.Length -ge 3) {
        return ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    }
    return $false
}

function Remove-BOMFromFile {
    param([string]$FilePath)
    
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        # Remove first 3 bytes (BOM)
        $newBytes = $bytes[3..($bytes.Length - 1)]
        [System.IO.File]::WriteAllBytes($FilePath, [byte[]]$newBytes)
        return $true
    }
    return $false
}

# Scan files by extension
foreach ($ext in $Extensions) {
    $files = Get-ChildItem -Path $Path -Filter $ext -Recurse -File -ErrorAction SilentlyContinue |
             Where-Object { $_.FullName -notmatch '[\\/](node_modules|\.git|target|build|dist|__pycache__)[\\/]' }
    
    foreach ($file in $files) {
        if (Test-HasBOM $file.FullName) {
            $foundCount++
            $relativePath = $file.FullName.Substring($Path.Length + 1)
            
            if ($DryRun) {
                Write-Host "  [BOM] $relativePath" -ForegroundColor Yellow
            } else {
                if (Remove-BOMFromFile $file.FullName) {
                    Write-Host "  [FIXED] $relativePath" -ForegroundColor Green
                    $fixedCount++
                }
            }
        }
    }
}

# Check specific files
foreach ($specificFile in $SpecificFiles) {
    $filePath = Join-Path $Path $specificFile
    if (Test-Path $filePath) {
        if (Test-HasBOM $filePath) {
            $foundCount++
            
            if ($DryRun) {
                Write-Host "  [BOM] $specificFile" -ForegroundColor Yellow
            } else {
                if (Remove-BOMFromFile $filePath) {
                    Write-Host "  [FIXED] $specificFile" -ForegroundColor Green
                    $fixedCount++
                }
            }
        }
    }
}

Write-Host ""
if ($DryRun) {
    Write-Host "Found $foundCount file(s) with BOM. Run without -DryRun to fix." -ForegroundColor Cyan
} else {
    if ($fixedCount -gt 0) {
        Write-Host "Fixed $fixedCount file(s)." -ForegroundColor Green
    } else {
        Write-Host "No files with BOM found." -ForegroundColor Green
    }
}
