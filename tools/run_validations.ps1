[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$GodotPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

function Resolve-GodotExecutable {
    param([string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        if (-not (Test-Path -LiteralPath $RequestedPath -PathType Leaf)) {
            throw "Godot executable not found: $RequestedPath"
        }
        return (Resolve-Path -LiteralPath $RequestedPath).Path
    }

    if (-not [string]::IsNullOrWhiteSpace($env:GODOT_PATH)) {
        if (Test-Path -LiteralPath $env:GODOT_PATH -PathType Leaf) {
            return (Resolve-Path -LiteralPath $env:GODOT_PATH).Path
        }
    }

    foreach ($commandName in @("godot4", "godot", "Godot_v4.7-stable_win64_console.exe")) {
        $command = Get-Command $commandName -CommandType Application -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            return $command.Source
        }
    }

    $searchRoots = @(
        (Join-Path $env:USERPROFILE "Desktop\godot"),
        (Join-Path $env:USERPROFILE "OneDrive\Desktop\godot"),
        (Join-Path $env:LOCALAPPDATA "Programs\Godot")
    )
    foreach ($searchRoot in $searchRoots) {
        if (-not (Test-Path -LiteralPath $searchRoot -PathType Container)) {
            continue
        }
        $candidate = Get-ChildItem -LiteralPath $searchRoot -File -Filter "Godot*_console.exe" |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        if ($null -ne $candidate) {
            return $candidate.FullName
        }
    }

    throw "Godot was not found. Pass -GodotPath or set the GODOT_PATH environment variable."
}

function Invoke-GodotValidation {
    param(
        [string]$Executable,
        [string]$ResourcePath
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.Arguments = '--headless --path "{0}" --script "{1}"' -f $projectRoot, $ResourcePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "Failed to start Godot for $ResourcePath"
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        return [PSCustomObject]@{
            ExitCode = $process.ExitCode
            StdOut = $stdout
            StdErr = $stderr
            CombinedOutput = ($stdout + "`n" + $stderr)
        }
    }
    finally {
        $process.Dispose()
    }
}

$resolvedGodotPath = Resolve-GodotExecutable -RequestedPath $GodotPath
$validationScripts = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot "tests") -File -Filter "*_validation.gd" |
    Sort-Object Name)

if ($validationScripts.Count -eq 0) {
    throw "No tests/*_validation.gd scripts were found."
}

Write-Host "Godot: $resolvedGodotPath"
Write-Host "Project: $projectRoot"
Write-Host "Validations: $($validationScripts.Count)"

$failures = @()
$runtimeErrorPattern = '(?im)^\s*(?:SCRIPT ERROR|ERROR):'

foreach ($validationScript in $validationScripts) {
    $resourcePath = "res://tests/$($validationScript.Name)"
    Write-Host "[RUN ] $($validationScript.Name)"
    $result = Invoke-GodotValidation -Executable $resolvedGodotPath -ResourcePath $resourcePath
    $hasRuntimeError = $result.CombinedOutput -match $runtimeErrorPattern

    if ($result.ExitCode -ne 0 -or $hasRuntimeError) {
        $reasons = @()
        if ($result.ExitCode -ne 0) {
            $reasons += "exit code $($result.ExitCode)"
        }
        if ($hasRuntimeError) {
            $reasons += "runtime ERROR/SCRIPT ERROR output"
        }
        Write-Host "[FAIL] $($validationScript.Name): $($reasons -join ', ')" -ForegroundColor Red
        if (-not [string]::IsNullOrWhiteSpace($result.StdOut)) {
            Write-Host $result.StdOut.TrimEnd()
        }
        if (-not [string]::IsNullOrWhiteSpace($result.StdErr)) {
            [Console]::Error.WriteLine($result.StdErr.TrimEnd())
        }
        $failures += $validationScript.Name
        continue
    }

    $resultLine = [regex]::Match($result.StdOut, '(?im)^.*RESULTS?:.*$')
    if ($resultLine.Success) {
        Write-Host "[PASS] $($validationScript.Name) - $($resultLine.Value.Trim())" -ForegroundColor Green
    }
    else {
        Write-Host "[PASS] $($validationScript.Name)" -ForegroundColor Green
    }
}

if ($failures.Count -gt 0) {
    $failureSummary = "Validation failed: {0} of {1} script(s): {2}" -f $failures.Count, $validationScripts.Count, ($failures -join ", ")
    [Console]::Error.WriteLine($failureSummary)
    exit 1
}

Write-Host "All $($validationScripts.Count) validation scripts passed without runtime errors." -ForegroundColor Green
exit 0
