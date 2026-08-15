[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$GodotPath,

    [string]$OutputDirectory = "",

    [ValidateRange(0.1, 30.0)]
    [double]$WarmupSeconds = 2.0,

    [ValidateRange(0.25, 60.0)]
    [double]$SampleSeconds = 5.0,

    [ValidateRange(30, 1800)]
    [int]$TimeoutSeconds = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable not found: $GodotPath"
}
$resolvedGodotPath = (Resolve-Path -LiteralPath $GodotPath).Path

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot "docs\performance"
}
elseif (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot $OutputDirectory
}
$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$projectPrefix = $projectRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if (-not $resolvedOutputDirectory.StartsWith($projectPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Benchmark output must stay inside the project: $resolvedOutputDirectory"
}
New-Item -ItemType Directory -Path $resolvedOutputDirectory -Force | Out-Null

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $resolvedGodotPath
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $false
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
if ($projectRoot.Contains('"') -or $resolvedOutputDirectory.Contains('"')) {
    throw "Benchmark paths cannot contain a double-quote character."
}
$warmupText = $WarmupSeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture)
$sampleText = $SampleSeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture)
$startInfo.Arguments = '--path "{0}" --script "res://tools/performance_benchmark.gd" -- "--output-dir={1}" "--warmup-seconds={2}" "--sample-seconds={3}"' -f `
    $projectRoot, $resolvedOutputDirectory, $warmupText, $sampleText

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
try {
    if (-not $process.Start()) {
        throw "Failed to start the visible-renderer benchmark."
    }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.Kill($true)
        $process.WaitForExit()
        throw "Visible-renderer benchmark exceeded the bounded $TimeoutSeconds second timeout."
    }
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    $combinedOutput = $stdout + "`n" + $stderr
    if (-not [string]::IsNullOrWhiteSpace($stdout)) {
        Write-Output $stdout.TrimEnd()
    }
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
        [Console]::Error.WriteLine($stderr.TrimEnd())
    }
    if ($process.ExitCode -ne 0) {
        throw "Visible-renderer benchmark failed with exit code $($process.ExitCode)."
    }
    if ($combinedOutput -match '(?im)^\s*(?:SCRIPT ERROR|ERROR):') {
        throw "Visible-renderer benchmark emitted a runtime ERROR/SCRIPT ERROR."
    }
    if ($stdout -notmatch '(?m)^PERFORMANCE_BENCHMARK_OK\|') {
        throw "Visible-renderer benchmark exited without its success marker."
    }
}
finally {
    $process.Dispose()
}

$jsonPath = Join-Path $resolvedOutputDirectory "performance_baseline.json"
$markdownPath = Join-Path $resolvedOutputDirectory "performance_baseline.md"
if (-not (Test-Path -LiteralPath $jsonPath -PathType Leaf)) {
    throw "Benchmark did not create its JSON report: $jsonPath"
}
if (-not (Test-Path -LiteralPath $markdownPath -PathType Leaf)) {
    throw "Benchmark did not create its Markdown report: $markdownPath"
}
Write-Output "PERFORMANCE_REPORTS_OK|json=$jsonPath|markdown=$markdownPath"
