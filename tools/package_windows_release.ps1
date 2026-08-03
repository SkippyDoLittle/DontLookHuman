[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$GodotPath,

    [ValidatePattern('^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$')]
    [string]$Version = "0.9.0"
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$resolvedGodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
$projectConfigPath = Join-Path $projectRoot "project.godot"
$versionLine = Select-String -LiteralPath $projectConfigPath -Pattern '^config/version="([^"]+)"$' |
    Select-Object -First 1
if ($null -eq $versionLine) {
    throw "Could not read application/config/version from project.godot."
}
$projectVersion = $versionLine.Matches[0].Groups[1].Value
if ($projectVersion -ne $Version) {
    throw "Package version $Version does not match project version $projectVersion."
}
$releaseRoot = Join-Path $projectRoot "export\release"
$folderName = "DontLookHuman-$Version-windows"
$stageRoot = Join-Path $releaseRoot $folderName
$executablePath = Join-Path $stageRoot "DontLookHuman.exe"
$readmePath = Join-Path $stageRoot "README.txt"
$zipPath = Join-Path $releaseRoot "$folderName.zip"
$checksumPath = "$zipPath.sha256"

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
$godotIgnorePath = Join-Path (Join-Path $projectRoot "export") ".gdignore"
if (-not (Test-Path -LiteralPath $godotIgnorePath -PathType Leaf)) {
    [System.IO.File]::WriteAllText($godotIgnorePath, "", [System.Text.UTF8Encoding]::new($false))
}

& $resolvedGodotPath `
    --headless `
    --path $projectRoot `
    --export-release "Windows Desktop" `
    $executablePath
if ($LASTEXITCODE -ne 0) {
    throw "Godot release export failed with exit code $LASTEXITCODE."
}
if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
    throw "Godot reported success but did not create $executablePath."
}

$releaseNotes = @"
DON'T LOOK HUMAN $Version

A short pigeon behavior-stealth game for Windows.

Run DontLookHuman.exe to play. No installation is required.

Keyboard and mouse
  Move: WASD
  Sprint: Shift
  Peck / collect: E
  Camera: Mouse
  Zoom: Mouse wheel
  Pause: Escape

Controller
  Move: Left stick
  Sprint: Left shoulder
  Peck / collect: A
  Camera: Right stick
  Pause: Start

Windows may show an unfamiliar-publisher warning because this build is not code-signed.
"@
$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($readmePath, $releaseNotes, $utf8WithoutBom)

$expectedStageFiles = @($executablePath, $readmePath)
$unexpectedStageFiles = @(
    Get-ChildItem -LiteralPath $stageRoot -File -Recurse |
        Where-Object { $_.FullName -notin $expectedStageFiles }
)
if ($unexpectedStageFiles.Count -gt 0) {
    $unexpectedNames = ($unexpectedStageFiles.FullName -join ", ")
    throw "Release staging contains unexpected files: $unexpectedNames"
}

Compress-Archive -LiteralPath $stageRoot -DestinationPath $zipPath -CompressionLevel Optimal -Force
if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
    throw "The release ZIP was not created."
}

$checksum = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
$checksumLine = "$($checksum.Hash.ToLowerInvariant()) *$([System.IO.Path]::GetFileName($zipPath))`n"
[System.IO.File]::WriteAllText($checksumPath, $checksumLine, $utf8WithoutBom)

$zipSizeMb = [Math]::Round((Get-Item -LiteralPath $zipPath).Length / 1MB, 2)
Write-Output "RELEASE_PACKAGE_OK|version=$Version|zip=$zipPath|size_mb=$zipSizeMb|sha256=$($checksum.Hash.ToLowerInvariant())"
