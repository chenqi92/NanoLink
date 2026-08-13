[CmdletBinding()]
param(
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$runtimeRoot = Join-Path $env:TEMP "nanoops-dev"

function Stop-SavedProcess([string]$Name, [string[]]$ExpectedProcessNames) {
    $pidFile = Join-Path $runtimeRoot "$Name.pid"
    if (-not (Test-Path -LiteralPath $pidFile)) {
        return
    }

    $savedPid = 0
    [void][int]::TryParse((Get-Content -LiteralPath $pidFile -Raw).Trim(), [ref]$savedPid)
    if ($savedPid -gt 0) {
        $process = Get-Process -Id $savedPid -ErrorAction SilentlyContinue
        if ($process -and $ExpectedProcessNames -contains $process.ProcessName) {
            if (-not $Quiet) {
                Write-Host "Stopping $Name (PID $savedPid)..."
            }
            & taskkill.exe /PID $savedPid /T /F 2>$null | Out-Null
        }
    }

    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
Stop-SavedProcess "frontend" @("cmd", "node", "npm")
Stop-SavedProcess "backend" @("nanolink-server")
Remove-Item -LiteralPath (Join-Path $runtimeRoot "frontend.port") -Force -ErrorAction SilentlyContinue

if (-not $Quiet) {
    Write-Host "NanoOps development processes have been stopped." -ForegroundColor Green
}
