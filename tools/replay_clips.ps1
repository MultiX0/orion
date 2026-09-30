# Plays WAV files through the PC speakers while the board listens, and counts
# wake word detections from serial. This is how the model is tested without a
# human saying the phrase.
#
#   tools\replay_clips.ps1 -Path wakeword\test_clips            a folder
#   tools\replay_clips.ps1 -Path logs\wake_clips\wake_001.wav   one file
#   tools\replay_clips.ps1 -Path clips -Negative                 expect no detections
#
# One serial capture per clip (tools\serial_capture.py, no reset), so every
# detection is attributed to the clip that was playing. The first capture sends
# "ww start" so the pipeline is running. Results go to logs\replay_<time>.txt.
# Put the board's mic within arm's reach of the speakers and turn them up.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [switch]$Negative,
    [double]$Lead = 1.0,
    [double]$Tail = 2.5,
    [string]$Out
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$capture = Join-Path $PSScriptRoot 'serial_capture.py'

if (-not [System.IO.Path]::IsPathRooted($Path)) { $Path = Join-Path $repo $Path }
if (Test-Path $Path -PathType Container) {
    $files = Get-ChildItem $Path -Filter *.wav -File | Sort-Object Name
} elseif (Test-Path $Path -PathType Leaf) {
    $files = @(Get-Item $Path)
} else {
    Write-Error "No such file or folder: $Path"; exit 1
}
if ($files.Count -eq 0) { Write-Error "No .wav files in $Path"; exit 1 }

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
if (-not $Out) { $Out = Join-Path $repo "logs\replay_$stamp.txt" }
$logDir = Join-Path $repo "logs\replay_$stamp"
New-Item -ItemType Directory -Force $logDir | Out-Null

function Wav-Seconds([string]$file) {
    $bytes = [System.IO.File]::ReadAllBytes($file)
    if ($bytes.Length -lt 44) { return 1.0 }
    $rate = [BitConverter]::ToInt32($bytes, 24)
    $blockAlign = [BitConverter]::ToInt16($bytes, 32)
    if ($rate -le 0 -or $blockAlign -le 0) { return 1.0 }
    return ($bytes.Length - 44) / ($rate * $blockAlign)
}

function Start-Capture([string]$logFile, [double]$seconds, [string[]]$send) {
    $argList = @($capture, '--no-reset', '--quiet', '--seconds', $seconds, '--out', $logFile, '--send-delay', '0.3')
    foreach ($s in $send) { $argList += @('--send', "`"$s`"") }
    return Start-Process python -ArgumentList $argList -PassThru -NoNewWindow -WorkingDirectory $repo
}

$results = @()
$first = $true
foreach ($f in $files) {
    $dur = Wav-Seconds $f.FullName
    $seconds = [Math]::Ceiling($Lead + $dur + $Tail)
    $log = Join-Path $logDir ($f.BaseName + '.txt')
    $send = @()
    if ($first) { $send = @('ww start'); $seconds += 1; $first = $false }

    $proc = Start-Capture $log $seconds $send
    Start-Sleep -Seconds ($Lead + 0.8)
    try {
        (New-Object System.Media.SoundPlayer $f.FullName).PlaySync()
    } catch {
        Write-Host "replay: could not play $($f.Name): $_"
    }
    $proc.WaitForExit()

    $hits = 0
    if (Test-Path $log) {
        $hits = @(Select-String -Path $log -Pattern 'DETECTED' -SimpleMatch).Count
    }
    $results += [pscustomobject]@{ clip = $f.Name; seconds = [Math]::Round($dur, 2); detections = $hits }
    Write-Host ("{0,-40} {1,6:N2}s  detections {2}" -f $f.Name, $dur, $hits)
}

$total = $results.Count
$hit = @($results | Where-Object { $_.detections -gt 0 }).Count
$summary = if ($Negative) {
    "replay: $total negative clips, $hit produced a false accept"
} else {
    "replay: $total clips, $hit detected ($([Math]::Round(100.0 * $hit / $total, 1)) percent)"
}
Write-Host $summary
$lines = @("# replay_clips $stamp", "# path: $Path", "")
$lines += $results | ForEach-Object { "{0}`t{1}`t{2}" -f $_.clip, $_.seconds, $_.detections }
$lines += @("", $summary)
Set-Content -Path $Out -Value $lines -Encoding utf8
Write-Host "replay: results in $Out, per clip serial logs in $logDir"
