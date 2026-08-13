[CmdletBinding()]
param(
    [switch]$NoBrowser,
    [switch]$SkipBackendBuild
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$webRoot = Join-Path $repoRoot "apps\server\web"
$serverRoot = Join-Path $repoRoot "apps\server"
$buildRoot = Join-Path $repoRoot "build"
$serverBinary = Join-Path $buildRoot "nanolink-server.exe"
$configFile = Join-Path $repoRoot "config.yaml"
$runtimeRoot = Join-Path $env:TEMP "nanoops-dev"
$backendLog = Join-Path $runtimeRoot "backend.log"
$backendErrorLog = Join-Path $runtimeRoot "backend.error.log"
$frontendLog = Join-Path $runtimeRoot "frontend.log"
$frontendErrorLog = Join-Path $runtimeRoot "frontend.error.log"
$healthUrl = "http://localhost:8080/api/health"

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Wait-Http([string]$Url, [int]$TimeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 2
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
                return $true
            }
        } catch {
            Start-Sleep -Milliseconds 500
        }
    }
    return $false
}

function Test-Http([string]$Url) {
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 2
        return $response.StatusCode -ge 200 -and $response.StatusCode -lt 400
    } catch {
        return $false
    }
}

function Test-TcpPortAvailable([int]$Port) {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
    try {
        $listener.Start()
        return $true
    } catch {
        return $false
    } finally {
        $listener.Stop()
    }
}

function Find-FrontendPort {
    foreach ($port in 5173..5183) {
        if (Test-TcpPortAvailable $port) {
            return $port
        }
    }
    throw "No free Web development port was found in the range 5173-5183."
}

function Show-LogTail([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        Get-Content -LiteralPath $Path -Tail 40
    }
}

function Assert-Command([string]$Name, [string]$InstallHint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is not installed. $InstallHint"
    }
}

try {
    New-Item -ItemType Directory -Force -Path $runtimeRoot, $buildRoot | Out-Null

    Write-Step "Stopping the previous script-managed development processes"
    & (Join-Path $PSScriptRoot "stop-dev.ps1") -Quiet

    Assert-Command "node" "Install Node.js 24 or newer and reopen this script."
    Assert-Command "npm.cmd" "Install Node.js 24 or newer and reopen this script."

    Write-Step "Synchronizing Web dependencies"
    Push-Location $webRoot
    try {
        & npm.cmd install --prefer-offline --no-audit --no-fund
        if ($LASTEXITCODE -ne 0) {
            throw "npm install failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }

    if ([string]::IsNullOrWhiteSpace($env:NANOLINK_JWT_SECRET)) {
        $env:NANOLINK_JWT_SECRET = "development-test-secret-key-32bytes-or-more-20260812"
    }
    if ([string]::IsNullOrWhiteSpace($env:NANOLINK_ADMIN_USERNAME)) {
        $env:NANOLINK_ADMIN_USERNAME = "admin"
    }
    if ([string]::IsNullOrWhiteSpace($env:NANOLINK_ADMIN_PASSWORD)) {
        $env:NANOLINK_ADMIN_PASSWORD = "admin123456"
    }

    # Some Windows developer shells expose both Path and PATH after invoking
    # toolchains. Windows PowerShell's Start-Process treats those as duplicate
    # dictionary keys, so normalize the process-level entry before spawning.
    $processPath = $env:Path
    Remove-Item -LiteralPath "Env:Path" -Force -ErrorAction SilentlyContinue
    $env:Path = $processPath

    $startedBackend = $false
    if (Test-Http $healthUrl) {
        Write-Step "Reusing the healthy Server API already running on port 8080"
    } else {
        if (-not (Test-TcpPortAvailable 8080)) {
            throw "Port 8080 is occupied, but its NanoOps health endpoint is unavailable. Stop that process or change the Server port."
        }

        if (-not $SkipBackendBuild) {
            Assert-Command "go" "Install the Go toolchain required by apps/server."

            Write-Step "Building the local Server"
            Push-Location $serverRoot
            try {
                $env:CGO_ENABLED = "1"
                # Development builds do not need Go's automatic VCS stamp. Turning
                # it off also keeps the script usable when Windows Git marks a
                # shared checkout as having different ownership.
                & go build -buildvcs=false -o $serverBinary ./cmd
                if ($LASTEXITCODE -ne 0) {
                    throw "go build failed with exit code $LASTEXITCODE. On Windows, make sure GCC is installed for SQLite/CGO."
                }
            } finally {
                Pop-Location
            }
        } elseif (-not (Test-Path -LiteralPath $serverBinary)) {
            throw "-SkipBackendBuild was used, but $serverBinary does not exist."
        }

        if (-not (Test-Path -LiteralPath $configFile)) {
            Write-Step "Creating the local development configuration"
            Copy-Item -LiteralPath (Join-Path $repoRoot "apps\docker\config.yaml") -Destination $configFile
            $config = Get-Content -LiteralPath $configFile -Raw
            $config = $config.Replace("/app/data/nanolink.db", "./nanolink.db")
            Set-Content -LiteralPath $configFile -Value $config -NoNewline
        }

        Remove-Item -LiteralPath $backendLog, $backendErrorLog -Force -ErrorAction SilentlyContinue
        Write-Step "Starting the Server API"
        $backend = Start-Process -FilePath $serverBinary `
            -ArgumentList @("-config", $configFile) `
            -WorkingDirectory $repoRoot `
            -RedirectStandardOutput $backendLog `
            -RedirectStandardError $backendErrorLog `
            -WindowStyle Hidden `
            -PassThru
        Set-Content -LiteralPath (Join-Path $runtimeRoot "backend.pid") -Value $backend.Id

        Start-Sleep -Milliseconds 500
        $backend.Refresh()
        if ($backend.HasExited) {
            Show-LogTail $backendLog
            Show-LogTail $backendErrorLog
            throw "The Server process exited before its health check completed."
        }

        if (-not (Wait-Http $healthUrl 30)) {
            Write-Host "`nServer output:" -ForegroundColor Yellow
            Show-LogTail $backendLog
            Show-LogTail $backendErrorLog
            throw "The Server API did not become healthy at $healthUrl"
        }
        $startedBackend = $true
    }

    $frontendPort = Find-FrontendPort
    $dashboardUrl = "http://localhost:$frontendPort/dashboard/"
    Set-Content -LiteralPath (Join-Path $runtimeRoot "frontend.port") -Value $frontendPort
    Remove-Item -LiteralPath $frontendLog, $frontendErrorLog -Force -ErrorAction SilentlyContinue
    Write-Step "Starting the Web development server on port $frontendPort"
    $frontend = Start-Process -FilePath "npm.cmd" `
        -ArgumentList @("run", "dev", "--", "--host", "0.0.0.0", "--port", "$frontendPort", "--strictPort") `
        -WorkingDirectory $webRoot `
        -RedirectStandardOutput $frontendLog `
        -RedirectStandardError $frontendErrorLog `
        -WindowStyle Hidden `
        -PassThru
    Set-Content -LiteralPath (Join-Path $runtimeRoot "frontend.pid") -Value $frontend.Id

    Start-Sleep -Milliseconds 500
    $frontend.Refresh()
    if ($frontend.HasExited) {
        Show-LogTail $frontendLog
        Show-LogTail $frontendErrorLog
        throw "The Web process exited before its health check completed."
    }

    if (-not (Wait-Http $dashboardUrl 30)) {
        Write-Host "`nWeb output:" -ForegroundColor Yellow
        Show-LogTail $frontendLog
        Show-LogTail $frontendErrorLog
        throw "The Web development server did not become ready at $dashboardUrl"
    }

    Write-Host "`nNanoOps development environment is ready." -ForegroundColor Green
    Write-Host "Web:        $dashboardUrl"
    Write-Host "Server API: $healthUrl"
    if ($startedBackend) {
        Write-Host "Account:    $($env:NANOLINK_ADMIN_USERNAME) / $($env:NANOLINK_ADMIN_PASSWORD)"
    } else {
        Write-Host "Account:    Use the credentials of the existing Server API"
    }
    Write-Host "Logs:       $runtimeRoot"
    Write-Host "Stop:       Double-click stop-dev.bat"

    if (-not $NoBrowser) {
        Start-Process $dashboardUrl
    }
} catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
