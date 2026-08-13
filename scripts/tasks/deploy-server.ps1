[CmdletBinding()]
param(
    [string]$ConfigPath = "",
    [switch]$AllowDirty,
    [switch]$SkipChecks,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $repoRoot ".env.deploy"
} elseif (-not [IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path $repoRoot $ConfigPath
}

$cacheRoot = Join-Path $repoRoot ".codex-cache\deploy"
$archivePath = $null
$remoteScriptPath = $null

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Invoke-External([string]$FilePath, [string[]]$Arguments) {
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE"
    }
}

function Read-CommandOutput([string]$FilePath, [string[]]$Arguments) {
    $output = & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE"
    }
    return ($output -join "`n").Trim()
}

function Assert-Command([string]$Name, [string]$InstallHint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is not installed. $InstallHint"
    }
}

function Import-DotEnv([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Deployment config not found: $Path`nCopy .env.deploy.example to .env.deploy and edit it."
    }

    foreach ($rawLine in Get-Content -LiteralPath $Path) {
        $line = $rawLine.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith("#")) {
            continue
        }
        $separator = $line.IndexOf("=")
        if ($separator -lt 1) {
            throw "Invalid .env line: $rawLine"
        }
        $name = $line.Substring(0, $separator).Trim()
        $value = $line.Substring($separator + 1).Trim()
        if ($name -notmatch "^[A-Za-z_][A-Za-z0-9_]*$") {
            throw "Invalid environment variable name: $name"
        }
        if ($value.Length -ge 2) {
            $first = $value[0]
            $last = $value[$value.Length - 1]
            if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }
        [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
}

function Get-RequiredSetting([string]$Name) {
    $value = [Environment]::GetEnvironmentVariable($Name, "Process")
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "$Name is required in $ConfigPath"
    }
    return $value.Trim()
}

function Assert-Match([string]$Name, [string]$Value, [string]$Pattern) {
    if ($Value -notmatch $Pattern) {
        throw "$Name contains an unsupported value: $Value"
    }
}

function Escape-BashSingleQuoted([string]$Value) {
    $replacement = ([string][char]39) + [char]34 + [char]39 + [char]34 + [char]39
    return $Value.Replace("'", $replacement)
}

function Get-Sha256File([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha256.ComputeHash($stream))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha256.Dispose()
        $stream.Dispose()
    }
}

try {
    Push-Location $repoRoot
    Assert-Command "git" "Install Git for Windows."
    Assert-Command "ssh" "Install the Windows OpenSSH client."
    Assert-Command "scp" "Install the Windows OpenSSH client."
    Assert-Command "tar.exe" "Install a tar implementation (Windows includes bsdtar)."

    Import-DotEnv $ConfigPath

    $sshHost = Get-RequiredSetting "DEPLOY_SSH_HOST"
    $sshPortText = Get-RequiredSetting "DEPLOY_SSH_PORT"
    $remoteUploadDir = Get-RequiredSetting "DEPLOY_REMOTE_UPLOAD_DIR"
    $remoteBuildRoot = Get-RequiredSetting "DEPLOY_REMOTE_BUILD_ROOT"
    $composeDir = Get-RequiredSetting "DEPLOY_COMPOSE_DIR"
    $composeService = Get-RequiredSetting "DEPLOY_COMPOSE_SERVICE"
    $imageRepository = Get-RequiredSetting "DEPLOY_IMAGE_REPOSITORY"
    $healthTimeoutText = Get-RequiredSetting "DEPLOY_HEALTH_TIMEOUT_SECONDS"
    $publicUrl = [Environment]::GetEnvironmentVariable("DEPLOY_PUBLIC_URL", "Process")
    if ($null -eq $publicUrl) { $publicUrl = "" }
    $publicUrl = $publicUrl.TrimEnd("/")
    $identityFile = [Environment]::GetEnvironmentVariable("DEPLOY_SSH_IDENTITY_FILE", "Process")
    $expectedAgentText = [Environment]::GetEnvironmentVariable("DEPLOY_EXPECTED_AGENT_COUNT", "Process")
    if ([string]::IsNullOrWhiteSpace($expectedAgentText)) { $expectedAgentText = "0" }
    $allowDirtyText = [Environment]::GetEnvironmentVariable("DEPLOY_ALLOW_DIRTY", "Process")
    if ([string]::IsNullOrWhiteSpace($allowDirtyText)) { $allowDirtyText = "false" }
    if ($allowDirtyText -notmatch "^(?i:true|false)$") {
        throw "DEPLOY_ALLOW_DIRTY must be true or false."
    }
    $allowDirtyFromConfig = $allowDirtyText -ieq "true"

    Assert-Match "DEPLOY_SSH_HOST" $sshHost "^[A-Za-z0-9_.@-]+$"
    Assert-Match "DEPLOY_REMOTE_UPLOAD_DIR" $remoteUploadDir "^/[A-Za-z0-9._/-]+$"
    Assert-Match "DEPLOY_REMOTE_BUILD_ROOT" $remoteBuildRoot "^/[A-Za-z0-9._/-]+$"
    Assert-Match "DEPLOY_COMPOSE_DIR" $composeDir "^/[A-Za-z0-9._/-]+$"
    Assert-Match "DEPLOY_COMPOSE_SERVICE" $composeService "^[A-Za-z0-9._-]+$"
    Assert-Match "DEPLOY_IMAGE_REPOSITORY" $imageRepository "^[A-Za-z0-9._/-]+$"
    if ($publicUrl -and $publicUrl -notmatch "^https://[A-Za-z0-9._:-]+$") {
        throw "DEPLOY_PUBLIC_URL must be an HTTPS origin without a path."
    }

    $sshPort = 0
    $healthTimeout = 0
    $expectedAgents = 0
    if (-not [int]::TryParse($sshPortText, [ref]$sshPort) -or $sshPort -lt 1 -or $sshPort -gt 65535) {
        throw "DEPLOY_SSH_PORT must be between 1 and 65535."
    }
    if (-not [int]::TryParse($healthTimeoutText, [ref]$healthTimeout) -or $healthTimeout -lt 30 -or $healthTimeout -gt 900) {
        throw "DEPLOY_HEALTH_TIMEOUT_SECONDS must be between 30 and 900."
    }
    if (-not [int]::TryParse($expectedAgentText, [ref]$expectedAgents) -or $expectedAgents -lt 0) {
        throw "DEPLOY_EXPECTED_AGENT_COUNT must be zero or greater."
    }

    $sshArgs = @("-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-p", "$sshPort")
    $scpArgs = @("-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-P", "$sshPort")
    if (-not [string]::IsNullOrWhiteSpace($identityFile)) {
        $identityFile = [IO.Path]::GetFullPath($identityFile)
        if (-not (Test-Path -LiteralPath $identityFile)) {
            throw "SSH identity file does not exist: $identityFile"
        }
        $sshArgs += @("-i", $identityFile)
        $scpArgs += @("-i", $identityFile)
    }

    $version = (Get-Content -LiteralPath (Join-Path $repoRoot "VERSION") -Raw).Trim()
    Assert-Match "VERSION" $version "^[A-Za-z0-9][A-Za-z0-9._-]*$"
    $fullCommit = Read-CommandOutput "git" @("-c", "safe.directory=$($repoRoot.Replace('\','/'))", "rev-parse", "HEAD")
    $shortCommit = $fullCommit.Substring(0, 7)
    $dirtyFiles = @(git -c "safe.directory=$($repoRoot.Replace('\','/'))" status --porcelain=v1)
    $isDirty = $dirtyFiles.Count -gt 0
    if ($isDirty -and -not $AllowDirty -and -not $allowDirtyFromConfig) {
        Write-Host ($dirtyFiles -join "`n") -ForegroundColor Yellow
        throw "The working tree is not clean. Commit the changes, use -AllowDirty, or set DEPLOY_ALLOW_DIRTY=true locally."
    }

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")
    $buildTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    if ($isDirty) {
        $releaseId = "$shortCommit-dirty-$timestamp"
        $commitLabel = "$fullCommit-dirty"
    } else {
        $releaseId = "$shortCommit-$timestamp"
        $commitLabel = $fullCommit
    }
    $imageTag = "$imageRepository`:$version-$shortCommit"
    if ($isDirty) { $imageTag = "$imageRepository`:$version-$shortCommit-dirty-$timestamp" }

    Write-Host "Release: $releaseId"
    Write-Host "Source:  $commitLabel"
    Write-Host "Image:   $imageTag"
    Write-Host "Target:  $sshHost"

    if (-not $SkipChecks) {
        Write-Step "Running Go Server tests and vet"
        $goCache = Join-Path $repoRoot ".codex-cache\go-build"
        New-Item -ItemType Directory -Force $goCache | Out-Null
        $env:GOCACHE = $goCache
        Push-Location (Join-Path $repoRoot "apps\server")
        try {
            Invoke-External "go" @("test", "./...")
            Invoke-External "go" @("vet", "./...")
        } finally {
            Pop-Location
        }

        Write-Step "Running Web lint and production build"
        Push-Location (Join-Path $repoRoot "apps\server\web")
        try {
            if (-not (Test-Path -LiteralPath "node_modules")) {
                Invoke-External "npm.cmd" @("ci", "--no-audit", "--no-fund")
            }
            Invoke-External "npm.cmd" @("run", "lint")
            Invoke-External "npm.cmd" @("run", "build")
        } finally {
            Pop-Location
        }
    }

    Write-Step "Creating the release archive"
    New-Item -ItemType Directory -Force $cacheRoot | Out-Null
    $archiveName = "nanolink-$releaseId.tar"
    $archivePath = Join-Path $cacheRoot $archiveName
    if ($isDirty) {
        Invoke-External "tar.exe" @(
            "-cf", $archivePath,
            "--exclude=apps/server/web/node_modules",
            "--exclude=apps/server/web/dist",
            "--exclude=apps/server/web/.vite",
            "--exclude=apps/server/data",
            "--exclude=apps/server/nanolink-server",
            "--exclude=apps/server/nanolink.exe",
            "VERSION", "apps/docker/Dockerfile", "apps/server", "sdk/protocol/nanolink.proto"
        )
    } else {
        Invoke-External "git" @(
            "-c", "safe.directory=$($repoRoot.Replace('\','/'))",
            "archive", "--format=tar", "--output=$archivePath", "HEAD",
            "VERSION", "apps/docker/Dockerfile", "apps/server", "sdk/protocol/nanolink.proto"
        )
    }
    $archiveHash = Get-Sha256File $archivePath
    Write-Host "Archive SHA-256: $archiveHash"

    $remoteArchive = "$remoteUploadDir/$archiveName"
    $remoteScriptName = "deploy-$releaseId.sh"
    $remoteScript = "$remoteUploadDir/$remoteScriptName"
    $remoteBuildDir = "$remoteBuildRoot/build-$releaseId"
    $backupFile = "$composeDir/docker-compose.yml.pre-$releaseId"
    $smokeName = "nanolink-smoke-$shortCommit-$timestamp"

    $template = @'
#!/usr/bin/env bash
set -Eeuo pipefail

archive='__ARCHIVE__'
archive_sha='__ARCHIVE_SHA__'
build_dir='__BUILD_DIR__'
compose_dir='__COMPOSE_DIR__'
compose_service='__COMPOSE_SERVICE__'
image_tag='__IMAGE_TAG__'
version='__VERSION__'
commit_label='__COMMIT_LABEL__'
build_time='__BUILD_TIME__'
backup_file='__BACKUP_FILE__'
smoke_name='__SMOKE_NAME__'
health_timeout=__HEALTH_TIMEOUT__
expected_agents=__EXPECTED_AGENTS__
public_url='__PUBLIC_URL__'
rollback_needed=0

cleanup() {
  sudo docker rm -fv "$smoke_name" >/dev/null 2>&1 || true
  rm -f "$archive" '__REMOTE_SCRIPT__'
}

on_error() {
  code=$?
  set +e
  if [ "$rollback_needed" -eq 1 ] && [ -f "$backup_file" ]; then
    echo "Deployment failed; restoring $backup_file" >&2
    sudo cp -a "$backup_file" "$compose_dir/docker-compose.yml"
    (cd "$compose_dir" && sudo docker compose up -d --no-deps "$compose_service")
  fi
  cleanup
  exit "$code"
}

trap on_error ERR
trap cleanup EXIT

echo "$archive_sha  $archive" | sha256sum -c -
test ! -e "$build_dir"
sudo mkdir -p "$build_dir"
sudo tar -xf "$archive" -C "$build_dir"
sudo chown -R "$(id -u):$(id -g)" "$build_dir"

cd "$build_dir"
sudo docker build \
  --build-arg "VERSION=$version" \
  --build-arg "GIT_COMMIT=$commit_label" \
  --build-arg "BUILD_TIME=$build_time" \
  -t "$image_tag" \
  -f apps/docker/Dockerfile .

sudo docker run -d --name "$smoke_name" \
  -e NANOLINK_JWT_SECRET=smoke-test-only-key-at-least-32-bytes \
  "$image_tag" >/dev/null

smoke_ok=0
for ((i=0; i<30; i++)); do
  if sudo docker exec "$smoke_name" wget -qO- http://127.0.0.1:8080/api/health >/dev/null 2>&1; then
    smoke_ok=1
    break
  fi
  sleep 1
done
test "$smoke_ok" -eq 1
sudo docker exec "$smoke_name" /app/nanolink-server -version
sudo docker rm -fv "$smoke_name" >/dev/null

cd "$compose_dir"
image_lines=$(grep -Ec '^[[:space:]]+image:[[:space:]]*' docker-compose.yml)
test "$image_lines" -eq 1
sudo cp -a docker-compose.yml "$backup_file"
rollback_needed=1
sudo sed -i -E "s|^([[:space:]]*image:[[:space:]]*).*$|\1$image_tag|" docker-compose.yml
sudo docker compose config --quiet

sudo docker compose up -d --no-deps "$compose_service"

healthy=0
container_id=''
for ((i=0; i<health_timeout; i++)); do
  container_id=$(sudo docker compose ps -q "$compose_service" 2>/dev/null || true)
  status=$(sudo docker inspect "$container_id" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' 2>/dev/null || true)
  if [ "$status" = healthy ]; then
    healthy=1
    break
  fi
  sleep 1
done
test "$healthy" -eq 1
test -n "$container_id"

health_json=$(curl -fsS http://127.0.0.1:8080/api/health)
echo "Health: $health_json"
local_asset=$(curl -fsSL http://127.0.0.1:8080/dashboard | grep -o 'assets/index-[A-Za-z0-9_-]*\.js' | head -n 1 || true)
echo "Local asset: $local_asset"

if [ "$expected_agents" -gt 0 ]; then
  for ((i=0; i<health_timeout; i++)); do
    health_json=$(curl -fsS http://127.0.0.1:8080/api/health)
    agent_count=$(printf '%s' "$health_json" | grep -o '"agentCount":[0-9]*' | cut -d: -f2 || true)
    if [ "${agent_count:-0}" -ge "$expected_agents" ]; then
      break
    fi
    sleep 1
  done
  if [ "${agent_count:-0}" -lt "$expected_agents" ]; then
    echo "Warning: expected $expected_agents agents, currently ${agent_count:-0}" >&2
  fi
fi

if [ -n "$public_url" ]; then
  public_asset=$(curl -fsSL "$public_url/dashboard" | grep -o 'assets/index-[A-Za-z0-9_-]*\.js' | head -n 1 || true)
  echo "Public asset: $public_asset"
  if [ -n "$local_asset" ] && [ "$public_asset" != "$local_asset" ]; then
    echo "Warning: public asset has not converged to the local asset yet." >&2
  fi
fi

error_count=$(sudo docker logs --since 5m "$container_id" 2>&1 | grep -F -c 'level":"error' || true)
echo "Recent error count: $error_count"
sudo docker inspect "$container_id" --format 'Image={{.Config.Image}} Health={{.State.Health.Status}} Restarts={{.RestartCount}}'
sudo docker exec "$container_id" /app/nanolink-server -version

rollback_needed=0
trap - ERR
echo "DEPLOY_OK image=$image_tag backup=$backup_file"
'@

    $replacements = [ordered]@{
        "__ARCHIVE__" = $remoteArchive
        "__ARCHIVE_SHA__" = $archiveHash
        "__BUILD_DIR__" = $remoteBuildDir
        "__COMPOSE_DIR__" = $composeDir
        "__COMPOSE_SERVICE__" = $composeService
        "__IMAGE_TAG__" = $imageTag
        "__VERSION__" = $version
        "__COMMIT_LABEL__" = $commitLabel
        "__BUILD_TIME__" = $buildTime
        "__BACKUP_FILE__" = $backupFile
        "__SMOKE_NAME__" = $smokeName
        "__HEALTH_TIMEOUT__" = "$healthTimeout"
        "__EXPECTED_AGENTS__" = "$expectedAgents"
        "__PUBLIC_URL__" = $publicUrl
        "__REMOTE_SCRIPT__" = $remoteScript
    }
    foreach ($entry in $replacements.GetEnumerator()) {
        $template = $template.Replace($entry.Key, (Escape-BashSingleQuoted $entry.Value))
    }

    $remoteScriptPath = Join-Path $cacheRoot $remoteScriptName
    [IO.File]::WriteAllText($remoteScriptPath, $template.Replace("`r`n", "`n") + "`n", [Text.UTF8Encoding]::new($false))

    if ($DryRun) {
        Write-Host "Generated remote rollout script: $remoteScriptName"
        Write-Host "`nDry run completed; no remote changes were made." -ForegroundColor Green
        exit 0
    }

    Write-Step "Verifying passwordless SSH access"
    Invoke-External "ssh" ($sshArgs + @($sshHost, "printf nanoops-deploy-ready"))

    Write-Step "Uploading the release"
    Invoke-External "scp" ($scpArgs + @($archivePath, $remoteScriptPath, "$sshHost`:$remoteUploadDir/"))

    Write-Step "Validating the remote rollout script"
    Invoke-External "ssh" ($sshArgs + @($sshHost, "bash -n '$remoteScript'"))

    Write-Step "Building and rolling out on the Server"
    Invoke-External "ssh" ($sshArgs + @($sshHost, "bash '$remoteScript'"))

    Write-Host "`nNanoOps Server deployment completed successfully." -ForegroundColor Green
    Write-Host "Image:  $imageTag"
    Write-Host "Source: $commitLabel"
    Write-Host "Backup: $backupFile"
} catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    Pop-Location -ErrorAction SilentlyContinue
    if ($archivePath) { Remove-Item -LiteralPath $archivePath -Force -ErrorAction SilentlyContinue }
    if ($remoteScriptPath) { Remove-Item -LiteralPath $remoteScriptPath -Force -ErrorAction SilentlyContinue }
}
