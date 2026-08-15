[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$GodotPath,

    [ValidatePattern('^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$')]
    [string]$Version = "0.9.0",

    [string]$OutputRoot = "",

    [switch]$Force,

    [switch]$SkipSmokeTest,

    [ValidateRange(5, 120)]
    [int]$SmokeTimeoutSeconds = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-PathWithin {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Parent
    )
    $candidateFull = [System.IO.Path]::GetFullPath($Candidate)
    $parentFull = [System.IO.Path]::GetFullPath($Parent).TrimEnd([char[]]"\/")
    $parentPrefix = $parentFull + [System.IO.Path]::DirectorySeparatorChar
    return $candidateFull.StartsWith($parentPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-NonEmptyFile {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$Label,
        [long]$MinimumBytes = 1
    )
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "$Label was not created: $LiteralPath"
    }
    $length = (Get-Item -LiteralPath $LiteralPath).Length
    if ($length -lt $MinimumBytes) {
        throw "$Label is unexpectedly small ($length bytes; expected at least $MinimumBytes): $LiteralPath"
    }
}

function Assert-WindowsExecutable {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    Assert-NonEmptyFile -LiteralPath $LiteralPath -Label "Windows executable" -MinimumBytes 1MB
    $stream = [System.IO.File]::OpenRead($LiteralPath)
    try {
        $firstByte = $stream.ReadByte()
        $secondByte = $stream.ReadByte()
        if ($firstByte -ne 0x4D -or $secondByte -ne 0x5A) {
            throw "Exported executable does not have a Windows PE MZ header: $LiteralPath"
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Invoke-ExportedGameSmoke {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $smokeProfileRoot = Join-Path $tempRoot ("dont-look-human-smoke-" + [guid]::NewGuid().ToString("N"))
    if (-not (Test-PathWithin -Candidate $smokeProfileRoot -Parent $tempRoot)) {
        throw "Resolved smoke-test profile escaped the system temp directory: $smokeProfileRoot"
    }
    $smokeAppData = Join-Path $smokeProfileRoot "AppData\Roaming"
    $smokeLocalAppData = Join-Path $smokeProfileRoot "AppData\Local"
    New-Item -ItemType Directory -Path $smokeAppData -Force | Out-Null
    New-Item -ItemType Directory -Path $smokeLocalAppData -Force | Out-Null

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.WorkingDirectory = [System.IO.Path]::GetDirectoryName($Executable)
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.Arguments = "--headless --audio-driver Dummy --quit-after 30"
    $startInfo.Environment["APPDATA"] = $smokeAppData
    $startInfo.Environment["LOCALAPPDATA"] = $smokeLocalAppData
    $startInfo.Environment["USERPROFILE"] = $smokeProfileRoot

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "Could not launch the exported-game smoke test."
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw "Exported-game smoke test exceeded its bounded $TimeoutSeconds second timeout."
        }
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        $combinedOutput = $stdout + "`n" + $stderr
        if ($process.ExitCode -ne 0) {
            throw "Exported-game smoke test failed with exit code $($process.ExitCode).`n$combinedOutput"
        }
        if ($combinedOutput -match '(?im)^\s*(?:SCRIPT ERROR|ERROR):') {
            throw "Exported-game smoke test emitted a runtime ERROR/SCRIPT ERROR.`n$combinedOutput"
        }
        return "passed"
    }
    finally {
        $process.Dispose()
        if (
            (Test-Path -LiteralPath $smokeProfileRoot -PathType Container) -and
            (Test-PathWithin -Candidate $smokeProfileRoot -Parent $tempRoot)
        ) {
            Remove-Item -LiteralPath $smokeProfileRoot -Recurse -Force
        }
    }
}

function Assert-ReleaseZip {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$FolderName
    )
    Assert-NonEmptyFile -LiteralPath $LiteralPath -Label "Release ZIP" -MinimumBytes 100KB
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($LiteralPath)
    try {
        $entryMap = @{}
        foreach ($entry in $archive.Entries) {
            $normalizedName = $entry.FullName.Replace('\', '/').TrimStart('/')
            if (-not [string]::IsNullOrWhiteSpace($entry.Name)) {
                $entryMap[$normalizedName] = $entry.Length
            }
        }
        $expectedEntries = @(
            "$FolderName/DontLookHuman.exe",
            "$FolderName/README.txt"
        )
        if ($entryMap.Count -ne $expectedEntries.Count) {
            throw "Release ZIP contains $($entryMap.Count) files; expected exactly $($expectedEntries.Count)."
        }
        foreach ($expectedEntry in $expectedEntries) {
            if (-not $entryMap.ContainsKey($expectedEntry)) {
                throw "Release ZIP is missing $expectedEntry."
            }
            if ([long]$entryMap[$expectedEntry] -le 0) {
                throw "Release ZIP entry is empty: $expectedEntry"
            }
        }
    }
    finally {
        $archive.Dispose()
    }
}

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable not found: $GodotPath"
}
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

$exportRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot "export"))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $releaseRoot = Join-Path $exportRoot "release"
}
elseif ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    $releaseRoot = [System.IO.Path]::GetFullPath($OutputRoot)
}
else {
    $releaseRoot = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $OutputRoot))
}
if (-not (Test-PathWithin -Candidate $releaseRoot -Parent $exportRoot)) {
    throw "Release output must be a child of the project export directory: $releaseRoot"
}

$folderName = "DontLookHuman-$Version-windows"
$stageRoot = Join-Path $releaseRoot $folderName
$executablePath = Join-Path $stageRoot "DontLookHuman.exe"
$readmePath = Join-Path $stageRoot "README.txt"
$zipPath = Join-Path $releaseRoot "$folderName.zip"
$checksumPath = "$zipPath.sha256"
foreach ($targetPath in @($stageRoot, $zipPath, $checksumPath)) {
    if (-not (Test-PathWithin -Candidate $targetPath -Parent $releaseRoot)) {
        throw "Resolved release target escaped its output root: $targetPath"
    }
}

$existingTargets = @(
    @($stageRoot, $zipPath, $checksumPath) |
        Where-Object { Test-Path -LiteralPath $_ }
)
if ($existingTargets.Count -gt 0 -and -not $Force) {
    throw "Release targets already exist. Choose a new -OutputRoot or pass -Force for these exact generated targets: $($existingTargets -join ', ')"
}
if ($Force) {
    if (Test-Path -LiteralPath $stageRoot -PathType Container) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force
    }
    foreach ($generatedFile in @($zipPath, $checksumPath)) {
        if (Test-Path -LiteralPath $generatedFile -PathType Leaf) {
            Remove-Item -LiteralPath $generatedFile -Force
        }
    }
}

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
$godotIgnorePath = Join-Path $exportRoot ".gdignore"
if (-not (Test-Path -LiteralPath $godotIgnorePath -PathType Leaf)) {
    New-Item -ItemType Directory -Path $exportRoot -Force | Out-Null
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
Assert-WindowsExecutable -LiteralPath $executablePath

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
Assert-NonEmptyFile -LiteralPath $readmePath -Label "Release README"

$expectedStageFiles = @($executablePath, $readmePath)
$unexpectedStageFiles = @(
    Get-ChildItem -LiteralPath $stageRoot -File -Recurse |
        Where-Object { $_.FullName -notin $expectedStageFiles }
)
if ($unexpectedStageFiles.Count -gt 0) {
    $unexpectedNames = ($unexpectedStageFiles.FullName -join ", ")
    throw "Release staging contains unexpected files: $unexpectedNames"
}

$smokeStatus = "skipped"
if (-not $SkipSmokeTest) {
    $smokeStatus = Invoke-ExportedGameSmoke `
        -Executable $executablePath `
        -TimeoutSeconds $SmokeTimeoutSeconds
}

Compress-Archive -LiteralPath $stageRoot -DestinationPath $zipPath -CompressionLevel Optimal
Assert-ReleaseZip -LiteralPath $zipPath -FolderName $folderName

$checksum = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
$checksumHex = $checksum.Hash.ToLowerInvariant()
$checksumLine = "$checksumHex *$([System.IO.Path]::GetFileName($zipPath))`n"
[System.IO.File]::WriteAllText($checksumPath, $checksumLine, $utf8WithoutBom)
Assert-NonEmptyFile -LiteralPath $checksumPath -Label "SHA-256 checksum"
$writtenChecksum = [System.IO.File]::ReadAllText($checksumPath).Trim()
$expectedChecksum = "$checksumHex *$([System.IO.Path]::GetFileName($zipPath))"
if ($writtenChecksum -cne $expectedChecksum) {
    throw "Written SHA-256 checksum does not match the packaged ZIP."
}
$verifiedChecksum = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($verifiedChecksum -cne $checksumHex) {
    throw "Release ZIP changed while its SHA-256 checksum was being written."
}

$zipSizeMb = [Math]::Round((Get-Item -LiteralPath $zipPath).Length / 1MB, 2)
Write-Output "RELEASE_PACKAGE_OK|version=$Version|exe=$executablePath|zip=$zipPath|checksum=$checksumPath|size_mb=$zipSizeMb|sha256=$checksumHex|smoke=$smokeStatus"
