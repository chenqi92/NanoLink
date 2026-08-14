[CmdletBinding()]
param(
    [string]$Alias = "nanoops",
    [int]$ValidityDays = 10000
)

$ErrorActionPreference = "Stop"

function New-SigningSecret {
    $bytes = [byte[]]::new(32)
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$androidRoot = Join-Path $repoRoot "apps\android"
$signingDir = Join-Path $androidRoot "signing"
$keystorePath = Join-Path $signingDir "nanoops-release.jks"
$propertiesPath = Join-Path $androidRoot "keystore.properties"

if (Test-Path -LiteralPath $keystorePath) {
    throw "Release keystore already exists: $keystorePath`nRefusing to replace the app's signing identity."
}
if (Test-Path -LiteralPath $propertiesPath) {
    throw "Signing properties already exist: $propertiesPath`nRefusing to overwrite credentials."
}

$keytool = Get-Command keytool -ErrorAction Stop
$storePassword = New-SigningSecret
$keyPassword = New-SigningSecret

New-Item -ItemType Directory -Force -Path $signingDir | Out-Null
$env:NANOOPS_STORE_PASSWORD = $storePassword
$env:NANOOPS_KEY_PASSWORD = $keyPassword

try {
    & $keytool.Source `
        -genkeypair `
        -v `
        -keystore $keystorePath `
        -storetype JKS `
        -alias $Alias `
        -keyalg RSA `
        -keysize 2048 `
        -validity $ValidityDays `
        -dname "CN=NanoOps, OU=Mobile, O=netok.cn, C=CN" `
        '-storepass:env' NANOOPS_STORE_PASSWORD `
        '-keypass:env' NANOOPS_KEY_PASSWORD
    if ($LASTEXITCODE -ne 0) {
        throw "keytool failed with exit code $LASTEXITCODE"
    }

    $properties = @(
        "# Local NanoOps Android release signing credentials. Never commit this file."
        "storeFile=signing/nanoops-release.jks"
        "storePassword=$storePassword"
        "keyAlias=$Alias"
        "keyPassword=$keyPassword"
    )
    [IO.File]::WriteAllLines($propertiesPath, $properties, [Text.UTF8Encoding]::new($false))
}
finally {
    Remove-Item Env:NANOOPS_STORE_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:NANOOPS_KEY_PASSWORD -ErrorAction SilentlyContinue
}

Write-Host "Created Android release signing identity:" -ForegroundColor Green
Write-Host "  Keystore:   $keystorePath"
Write-Host "  Credentials: $propertiesPath"
Write-Warning "Back up both files together. Losing the keystore prevents signing future updates with this app identity."
