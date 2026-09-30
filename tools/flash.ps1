# The only way anything reaches the board. There is one board and one COM port,
# so this takes an exclusive lock first. Nothing calls idf.py flash directly.
#
#   tools\flash.ps1                                  flash app, bootloader, table
#   tools\flash.ps1 -App                             flash just the app, faster
#   tools\flash.ps1 -Bin build\x.bin -Address 0x9000 flash one partition image
#   tools\flash.ps1 -Erase                           erase the whole flash
#
# Lock lives at %USERPROFILE%\.orion\flash.lock. Waits up to 15 minutes for it.
# A lock older than 10 minutes is treated as stale and taken over. Always released.

[CmdletBinding()]
param(
    [switch]$App,
    [string]$Bin,
    [string]$Address,
    [switch]$Erase,
    [string]$Port,
    [int]$WaitMinutes = 15
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$lockDir = Join-Path $env:USERPROFILE '.orion'
$lockFile = Join-Path $lockDir 'flash.lock'
$staleAfter = [TimeSpan]::FromMinutes(10)

New-Item -ItemType Directory -Force $lockDir | Out-Null

if (-not $Port) {
    $portFile = Join-Path $PSScriptRoot 'port.txt'
    if (Test-Path $portFile) { $Port = (Get-Content $portFile -Raw).Trim() }
}
if (-not $Port) {
    Write-Error "No port. Pass -Port COMx or write it to tools\port.txt."
    exit 1
}

# ---------------------------------------------------------------------------
# Lock
# ---------------------------------------------------------------------------
$deadline = (Get-Date).AddMinutes($WaitMinutes)
$stream = $null

while ($true) {
    if (Test-Path $lockFile) {
        $age = (Get-Date) - (Get-Item $lockFile).LastWriteTime
        $stale = $age -gt $staleAfter
        $reason = "$([int]$age.TotalMinutes) min old"

        # A killed process never runs its cleanup, so it strands the lock. Waiting
        # the full 10 minutes for a holder that is plainly gone is wasted time.
        if (-not $stale) {
            $text = Get-Content $lockFile -Raw -ErrorAction SilentlyContinue
            if ($text -match 'pid=(\d+)') {
                $holder = [int]$Matches[1]
                if ($holder -ne $PID -and -not (Get-Process -Id $holder -ErrorAction SilentlyContinue)) {
                    $stale = $true
                    $reason = "holder pid $holder is gone"
                }
            }
        }

        if ($stale) {
            Write-Host "flash.ps1: lock is stale ($reason), taking it over"
            Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
        }
    }
    try {
        # Opening with no FileShare is the actual mutual exclusion. The file
        # contents are only there to tell a human who is holding it.
        $stream = [System.IO.File]::Open($lockFile, 'OpenOrCreate', 'ReadWrite', 'None')
        break
    }
    catch [System.IO.IOException] {
        if ((Get-Date) -gt $deadline) {
            Write-Error "flash.ps1: gave up waiting $WaitMinutes min for $lockFile"
            exit 1
        }
        Start-Sleep -Seconds 5
    }
}

try {
    $who = "pid=$PID user=$env:USERNAME at=$(Get-Date -Format s)"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($who)
    $stream.SetLength(0)
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush()

    $idf = Join-Path $PSScriptRoot 'idf.ps1'

    if ($Erase) {
        & powershell -ExecutionPolicy Bypass -File $idf --port $Port erase-flash
        $code = $LASTEXITCODE
    }
    elseif ($Bin) {
        if (-not $Address) { Write-Error "-Bin needs -Address"; exit 1 }
        if (-not [System.IO.Path]::IsPathRooted($Bin)) { $Bin = Join-Path $repo $Bin }
        if (-not (Test-Path $Bin)) { Write-Error "No such image: $Bin"; exit 1 }
        # esptool, not idf.py: idf.py has no write-flash and no --no-build.
        # Writing one partition must not trigger a build either, which is the
        # whole point of provisioning NVS.
        & powershell -ExecutionPolicy Bypass -File $idf --esptool `
            --chip esp32s3 --port $Port write_flash $Address $Bin
        $code = $LASTEXITCODE
    }
    elseif ($App) {
        & powershell -ExecutionPolicy Bypass -File $idf --port $Port app-flash
        $code = $LASTEXITCODE
    }
    else {
        & powershell -ExecutionPolicy Bypass -File $idf --port $Port flash
        $code = $LASTEXITCODE
    }

    if ($code -ne 0) {
        Write-Host ""
        Write-Host "flash.ps1: failed with exit code $code."
        Write-Host "If it could not connect: hold BOOT, tap RST, release BOOT, run again."
    }
    exit $code
}
finally {
    if ($stream) { $stream.Close(); $stream.Dispose() }
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
}
