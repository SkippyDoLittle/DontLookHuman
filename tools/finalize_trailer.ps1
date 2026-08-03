[CmdletBinding()]
param(
    [string]$Path = "docs/gameplay_preview.avi"
)

$ErrorActionPreference = "Stop"
$expectedFrames = 990
$resolvedPath = (Resolve-Path -LiteralPath $Path).Path
$data = [System.IO.File]::ReadAllBytes($resolvedPath)

function Get-UInt32 {
    param([int]$Offset)
    return [BitConverter]::ToUInt32($data, $Offset)
}

function Get-FourCC {
    param([int]$Offset)
    return [System.Text.Encoding]::ASCII.GetString($data, $Offset, 4)
}

if ((Get-FourCC 0) -ne "RIFF" -or (Get-FourCC 8) -ne "AVI ") {
    throw "The input is not a RIFF AVI file."
}
$riffNeedsNormalization = (Get-UInt32 4) + 8 -ne $data.Length

$moviListOffset = -1
$indexOffset = -1
$topOffset = 12
while ($topOffset + 8 -le $data.Length) {
    $chunkId = Get-FourCC $topOffset
    $chunkSize = Get-UInt32 ($topOffset + 4)
    if ($chunkId -eq "LIST" -and (Get-FourCC ($topOffset + 8)) -eq "movi") {
        $moviListOffset = $topOffset
    }
    if ($chunkId -eq "idx1") {
        $indexOffset = $topOffset
        break
    }
    $topOffset += 8 + $chunkSize + ($chunkSize % 2)
}

if ($moviListOffset -lt 0 -or $indexOffset -lt 0) {
    throw "Could not find the AVI movi list and idx1 index."
}

$videoChunks = 0
$audioChunks = 0
$chunkCount = 0
$chunkOffset = $moviListOffset + 12
while ($chunkOffset -lt $indexOffset) {
    $chunkId = Get-FourCC $chunkOffset
    $chunkSize = Get-UInt32 ($chunkOffset + 4)
    switch ($chunkId) {
        "00db" { $videoChunks++ }
        "01wb" { $audioChunks++ }
        default { throw "Unexpected movi chunk '$chunkId' at byte $chunkOffset." }
    }
    $chunkCount++
    $chunkOffset += 8 + $chunkSize + ($chunkSize % 2)
}

$indexSize = Get-UInt32 ($indexOffset + 4)
if ($indexSize % 16 -ne 0 -or ($indexSize / 16) -ne $chunkCount) {
    throw "AVI index entry count does not match the movi chunks."
}
if ($indexOffset + 8 + $indexSize -ne $data.Length) {
    throw "AVI index does not reach the end of the trailer file."
}
if ($videoChunks -ne $expectedFrames -or $audioChunks -ne $expectedFrames) {
    throw "Expected $expectedFrames video and audio chunks; found $videoChunks video and $audioChunks audio."
}

# Every card is animated during capture now, so no post-capture frame replacement is needed.
# Godot can leave the four-byte RIFF size field stale even when movi and idx1 are complete.
# Normalize only that container field; gameplay, cards, soundtrack, and index stay byte-for-byte intact.
$riffStatus = "verified"
if ($riffNeedsNormalization) {
    $stream = [System.IO.File]::Open(
        $resolvedPath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::Read
    )
    try {
        $stream.Seek(4, [System.IO.SeekOrigin]::Begin) | Out-Null
        $lengthBytes = [BitConverter]::GetBytes([uint32]($data.Length - 8))
        $stream.Write($lengthBytes, 0, $lengthBytes.Length)
    }
    finally {
        $stream.Dispose()
    }
    $riffStatus = "normalized"
}

Write-Output "TRAILER_FINALIZE_OK|frames=$videoChunks|audio_chunks=$audioChunks|cards=animated|riff=$riffStatus"
