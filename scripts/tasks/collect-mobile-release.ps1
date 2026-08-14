[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$androidRoot = Join-Path $repoRoot "apps\android"
$outputDir = Join-Path $repoRoot "artifacts\mobile"
$apkSource = Join-Path $androidRoot "app\build\outputs\apk\release\app-release.apk"
$bundleSource = Join-Path $androidRoot "app\build\outputs\bundle\release\app-release.aab"
$propertiesPath = Join-Path $androidRoot "keystore.properties"

foreach ($requiredPath in @($apkSource, $bundleSource, $propertiesPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required release file is missing: $requiredPath"
    }
}

New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$artifacts = [ordered]@{
    (Join-Path $outputDir "NanoOps-0.5.0-android.apk") = $apkSource
    (Join-Path $outputDir "NanoOps-0.5.0-android.aab") = $bundleSource
    (Join-Path $outputDir "NanoOps-AppIcon-Light-1024.png") = (Join-Path $repoRoot "apps\branding\nanoops-icon-light-1024.png")
    (Join-Path $outputDir "NanoOps-AppIcon-Dark-1024.png") = (Join-Path $repoRoot "apps\branding\nanoops-icon-dark-1024.png")
    (Join-Path $outputDir "NanoOps-AppIcon-Tinted-1024.png") = (Join-Path $repoRoot "apps\branding\nanoops-icon-tinted-1024.png")
    (Join-Path $outputDir "NanoOps-PlayStore-512.png") = (Join-Path $repoRoot "apps\branding\nanoops-playstore-512.png")
}

foreach ($entry in $artifacts.GetEnumerator()) {
    Copy-Item -LiteralPath $entry.Value -Destination $entry.Key -Force
}

$properties = @{}
foreach ($line in [IO.File]::ReadAllLines($propertiesPath)) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith('#') -or -not $trimmed.Contains('=')) {
        continue
    }
    $parts = $trimmed.Split('=', 2)
    $properties[$parts[0].Trim()] = $parts[1].Trim()
}

$keystorePath = Join-Path $androidRoot $properties.storeFile
$certificatePath = Join-Path $outputDir "NanoOps-Android-Release-Certificate.pem"
$env:NANOOPS_STORE_PASSWORD = $properties.storePassword
try {
    & keytool `
        -exportcert `
        -rfc `
        -keystore $keystorePath `
        -alias $properties.keyAlias `
        '-storepass:env' NANOOPS_STORE_PASSWORD `
        -file $certificatePath
    if ($LASTEXITCODE -ne 0) {
        throw "keytool certificate export failed with exit code $LASTEXITCODE"
    }
}
finally {
    Remove-Item Env:NANOOPS_STORE_PASSWORD -ErrorAction SilentlyContinue
}

$checksumTargets = Get-ChildItem -LiteralPath $outputDir -File |
    Where-Object Name -NE "SHA256SUMS.txt" |
    Sort-Object Name
$checksumLines = foreach ($file in $checksumTargets) {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
    "$hash  $($file.Name)"
}
[IO.File]::WriteAllLines(
    (Join-Path $outputDir "SHA256SUMS.txt"),
    $checksumLines,
    [Text.UTF8Encoding]::new($false)
)

Get-ChildItem -LiteralPath $outputDir -File |
    Sort-Object Name |
    Select-Object Name, Length, LastWriteTime
