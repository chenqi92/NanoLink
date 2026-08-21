param(
    [string]$ZigPath = "",
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptDir = Split-Path -Parent $PSCommandPath
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..")).Path
$serverRoot = Join-Path $repoRoot "apps\server"
$webRoot = Join-Path $serverRoot "web"
$standaloneRoot = Join-Path $serverRoot "standalone"
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repoRoot "dist"
}
if (-not $ZigPath) {
    $ZigPath = Join-Path $repoRoot ".codex-cache\tools\zig-x86_64-windows-0.15.2\zig.exe"
}
if (-not (Test-Path -LiteralPath $ZigPath -PathType Leaf)) {
    throw "Zig compiler not found: $ZigPath"
}

$version = (Get-Content (Join-Path $repoRoot "VERSION") -Raw).Trim()
$gitSafeRoot = $repoRoot.Replace("\", "/")
$commitOutput = & git -c "safe.directory=$gitSafeRoot" -C $repoRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw "Unable to read Git commit" }
$commit = ($commitOutput | Select-Object -First 1).Trim()
$dirty = & git -c "safe.directory=$gitSafeRoot" -C $repoRoot status --porcelain=v1 -- apps/server apps/docker scripts/tasks/build-server-dist.ps1
if ($LASTEXITCODE -ne 0) { throw "Unable to read Git status" }
$commitLabel = if ($dirty) { "$commit-dirty" } else { $commit }
$buildTime = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
$packageName = "nanoops-server-linux-amd64-$version"
$packageDir = Join-Path $OutputRoot $packageName
$archivePath = Join-Path $OutputRoot "$packageName.tar.gz"

Write-Host "==> Building the embedded Web dashboard"
Push-Location $webRoot
try {
    if (-not (Test-Path -LiteralPath (Join-Path $webRoot "node_modules"))) {
        & npm.cmd ci --no-audit --no-fund
        if ($LASTEXITCODE -ne 0) { throw "npm ci failed" }
    }
    & npm.cmd run build
    if ($LASTEXITCODE -ne 0) { throw "Web build failed" }
} finally {
    Pop-Location
}

Write-Host "==> Running Server tests and vet with Go 1.26.6"
$env:GOTOOLCHAIN = "go1.26.6"
$env:GOCACHE = Join-Path $repoRoot ".codex-cache\go-build"
Push-Location $serverRoot
try {
    & go test ./...
    if ($LASTEXITCODE -ne 0) { throw "Go tests failed" }
    & go vet ./...
    if ($LASTEXITCODE -ne 0) { throw "go vet failed" }
} finally {
    Pop-Location
}

if (Test-Path -LiteralPath $packageDir) {
    Remove-Item -Recurse -Force -LiteralPath $packageDir
}
New-Item -ItemType Directory -Force -Path $packageDir | Out-Null

Write-Host "==> Cross-compiling a static Linux/amd64 binary with SQLite"
$binaryPath = Join-Path $packageDir "nanoops-server"
$env:CGO_ENABLED = "1"
$env:GOOS = "linux"
$env:GOARCH = "amd64"
$env:CC = "$ZigPath cc -target x86_64-linux-musl"
$env:ZIG_GLOBAL_CACHE_DIR = Join-Path $repoRoot ".codex-cache\zig-global"
$env:ZIG_LOCAL_CACHE_DIR = Join-Path $repoRoot ".codex-cache\zig-local"
$versionPkg = "github.com/chenqi92/NanoLink/apps/server/internal/version"
$ldflags = "-s -w -linkmode external -extldflags=-static " +
    "-X $versionPkg.Version=$version " +
    "-X $versionPkg.Commit=$commitLabel " +
    "-X $versionPkg.BuildTime=$buildTime"
Push-Location $serverRoot
try {
    & go build -mod=readonly -buildvcs=false -trimpath -ldflags $ldflags -o $binaryPath ./cmd
    if ($LASTEXITCODE -ne 0) { throw "Linux Server build failed" }
} finally {
    Pop-Location
}

Copy-Item (Join-Path $standaloneRoot "server-config.example.yaml") (Join-Path $packageDir "config.yaml")
Copy-Item (Join-Path $standaloneRoot "server.env.example") $packageDir
Copy-Item (Join-Path $standaloneRoot "nanoops-server.service") $packageDir
Copy-Item (Join-Path $standaloneRoot "nginx-nanoops.conf.example") $packageDir
Copy-Item (Join-Path $standaloneRoot "install.sh") $packageDir
Copy-Item (Join-Path $standaloneRoot "README_CN.md") $packageDir
Copy-Item (Join-Path $standaloneRoot "SECURITY_AUDIT_CN.md") $packageDir

$buildInfo = @(
    "version=$version"
    "commit=$commitLabel"
    "build_time=$buildTime"
    "go_toolchain=1.26.6"
    "target=linux/amd64"
    "libc=static-musl"
) -join "`n"
[IO.File]::WriteAllText((Join-Path $packageDir "BUILD-INFO.txt"), "$buildInfo`n", [Text.UTF8Encoding]::new($false))

$manifestLines = Get-ChildItem -LiteralPath $packageDir -File |
    Where-Object Name -ne "SHA256SUMS" |
    Sort-Object Name |
    ForEach-Object {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
        "$hash  $($_.Name)"
    }
[IO.File]::WriteAllText((Join-Path $packageDir "SHA256SUMS"), (($manifestLines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))

if (Test-Path -LiteralPath $archivePath) {
    Remove-Item -Force -LiteralPath $archivePath
}
& tar -czf $archivePath -C $OutputRoot $packageName
if ($LASTEXITCODE -ne 0) { throw "Creating release archive failed" }
$archiveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$archivePath.sha256", "$archiveHash  $([IO.Path]::GetFileName($archivePath))`n", [Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "Dist directory: $packageDir"
Write-Host "Archive:        $archivePath"
Write-Host "SHA-256:       $archiveHash"
