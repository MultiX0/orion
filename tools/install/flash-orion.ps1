# Orion one-click installer for Windows.
#
# Puts the Orion firmware on a LilyGO T-CameraPlus-S3 connected by USB-C.
# Double-click flash-orion.bat next to this file, or run:
#
#   powershell -ExecutionPolicy Bypass -File flash-orion.ps1
#
# Options, for people who want them:
#   -Port COM7         use this port instead of finding the board
#   -Firmware file.bin flash this file instead of the release
#   -DryRun            do everything except write to the board
#   -WorkDir folder    where downloads go
#   -UsbVendorId 303A  the USB vendor id to look for (Espressif)
#   -NoPause           do not wait for Enter at the end
#
# Needs no admin rights. Everything it downloads goes to
# %LOCALAPPDATA%\Orion\flasher and can be deleted afterwards.

[CmdletBinding()]
param(
    [string]$Port,
    [string]$Firmware,
    [string]$FirmwareUrl = 'https://github.com/MultiX0/orion/releases/latest/download/orion-firmware-full.bin',
    [int]$WaitSeconds = 90,
    [string]$WorkDir = (Join-Path $env:LOCALAPPDATA 'Orion\flasher'),
    [string]$UsbVendorId = '303A',
    [switch]$DryRun,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # the progress bar makes downloads very slow on PowerShell 5.1

# GitHub needs TLS 1.2, which older Windows PowerShell does not turn on by itself.
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# Espressif's standalone esptool, used when Python is not available.
$EsptoolVersion = 'v5.4.0'
$EsptoolZipUrl = "https://github.com/espressif/esptool/releases/download/$EsptoolVersion/esptool-$EsptoolVersion-windows-amd64.zip"
$EsptoolZipSha256 = 'b7f6b9dd301a210b31f4829118c909c84aae23107f9ca1fdc14ccf4d7384be2e'

# Where to look for a local firmware file. Pasted into a console, there is no script file.
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

function Say([string]$text) { Write-Host $text }
function Step([string]$text) { Write-Host ''; Write-Host "==> $text" -ForegroundColor Cyan }
function Good([string]$text) { Write-Host "    $text" -ForegroundColor Green }
function Warn([string]$text) { Write-Host "    $text" -ForegroundColor Yellow }

function Stop-WithMessage([string[]]$lines) {
    Write-Host ''
    foreach ($l in $lines) { Write-Host $l -ForegroundColor Red }
    Finish 1
}

function Finish([int]$code) {
    if (-not $NoPause) {
        Write-Host ''
        [void](Read-Host 'Press Enter to close this window')
    }
    exit $code
}

function Show-NoBoardHelp([string]$title = 'No Orion board was found. Things to try:') {
    Say ''
    Say $title
    Say '  1. Use a different USB-C cable. Many cables only charge and carry no data.'
    Say '  2. Plug straight into the computer, not through a hub or a monitor.'
    Say '  3. Put the board in download mode: hold the BOOT button on its side,'
    Say '     tap the RST button once, then let go of BOOT. Then run this again.'
    Say '  4. Try another USB port.'
}

# ---------------------------------------------------------------------------
# Finding the board
# ---------------------------------------------------------------------------

# Returns every serial port that belongs to an Espressif USB device (VID 303A).
# The ESP32-S3 has USB built in, so no driver is needed on Windows 10 and 11.
function Find-BoardPorts {
    $found = @()
    $devices = @()
    try {
        $devices = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop |
            Where-Object { $_.PNPDeviceID -match "VID_$UsbVendorId" -and $_.Name -match '\((COM\d+)\)' })
    } catch {
        $devices = @(Get-WmiObject -Class Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object { $_.PNPDeviceID -match "VID_$UsbVendorId" -and $_.Name -match '\((COM\d+)\)' })
    }
    foreach ($d in $devices) {
        if ($d.Name -match '\((COM\d+)\)') {
            $found += [pscustomobject]@{ Port = $Matches[1]; Name = $d.Name }
        }
    }
    return ,$found
}

function Select-BoardPort {
    if ($Port) {
        Good "Using the port you gave: $Port"
        return $Port
    }
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    $told = $false
    while ($true) {
        $ports = Find-BoardPorts
        if ($ports.Count -eq 1) {
            Good "Found the board on $($ports[0].Port) ($($ports[0].Name))"
            return $ports[0].Port
        }
        if ($ports.Count -gt 1) {
            Warn 'More than one board is connected:'
            for ($i = 0; $i -lt $ports.Count; $i++) {
                Say "      $($i + 1). $($ports[$i].Port)  $($ports[$i].Name)"
            }
            $pick = Read-Host '    Type the number of the board to use'
            $n = 0
            if ([int]::TryParse($pick, [ref]$n) -and $n -ge 1 -and $n -le $ports.Count) {
                return $ports[$n - 1].Port
            }
            Stop-WithMessage @('That was not one of the numbers. Unplug the boards you do not want to use and run this again.')
        }
        if ((Get-Date) -gt $deadline) {
            Show-NoBoardHelp
            Stop-WithMessage @('', 'Stopped: no board found.')
        }
        if (-not $told) {
            Warn 'No board yet. Plug the board in with a USB-C data cable now.'
            Warn 'Already plugged in? Hold BOOT on its side, tap RST, then let go of BOOT.'
            Warn "Waiting up to $WaitSeconds seconds..."
            $told = $true
        }
        Start-Sleep -Seconds 2
    }
}

# ---------------------------------------------------------------------------
# Getting esptool
# ---------------------------------------------------------------------------

# Returns the command (as an array) that runs Python, or $null. The Microsoft
# Store placeholder named python.exe does nothing, so each one is tried for real.
function Find-Python {
    $ErrorActionPreference = 'Continue'
    $candidates = @(@('py', '-3'), @('python'), @('python3'))
    foreach ($c in $candidates) {
        $exe = $c[0]
        if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { continue }
        $rest = @()
        if ($c.Count -gt 1) { $rest = $c[1..($c.Count - 1)] }
        try {
            $out = & $exe @rest -c 'import sys; print(sys.version_info[0])' 2>$null
            if ($LASTEXITCODE -eq 0 -and "$out".Trim() -eq '3') { return ,$c }
        } catch { }
    }
    return $null
}

function Test-Command([string[]]$cmd) {
    return ($null -ne (Get-EsptoolMajor $cmd))
}

# Runs "esptool version" and returns the major version number, or $null when it does not run.
function Get-EsptoolMajor([string[]]$cmd) {
    $ErrorActionPreference = 'Continue'
    $exe = $cmd[0]
    $rest = @()
    if ($cmd.Count -gt 1) { $rest = $cmd[1..($cmd.Count - 1)] }
    try {
        $out = & $exe @rest version 2>$null | Out-String
        if ($LASTEXITCODE -ne 0) { return $null }
        if ($out -match '(\d+)\.\d+') { return [int]$Matches[1] }
        return 0
    } catch { return $null }
}

function Get-FileSha256([string]$path) {
    return (Get-FileHash -Algorithm SHA256 -Path $path).Hash.ToLowerInvariant()
}

# Returns the command (as an array) that runs esptool.
function Get-Esptool {
    # A standalone esptool left by an earlier run
    $toolDir = Join-Path $WorkDir "esptool-$EsptoolVersion"
    $cached = Get-ChildItem -Path $toolDir -Filter 'esptool.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cached -and (Test-Command @($cached.FullName))) {
        Good 'Using esptool from an earlier run.'
        return ,@($cached.FullName)
    }

    $python = Find-Python
    if ($python) {
        $pyExe = $python[0]
        $pyRest = @()
        if ($python.Count -gt 1) { $pyRest = $python[1..($python.Count - 1)] }

        # esptool already installed for this Python
        $cmd = $python + @('-m', 'esptool')
        if (Test-Command $cmd) {
            Good 'Using the esptool that is already installed.'
            return ,$cmd
        }

        # A private Python environment, so nothing else on the computer changes.
        $venv = Join-Path $WorkDir 'venv'
        $venvPy = Join-Path $venv 'Scripts\python.exe'
        $cmd = @($venvPy, '-m', 'esptool')
        if ((Test-Path $venvPy) -and (Test-Command $cmd)) {
            Good 'Using esptool from an earlier run.'
            return ,$cmd
        }
        Say '    Python found. Installing esptool into a private folder (a few MB)...'
        $ErrorActionPreference = 'Continue'
        try {
            & $pyExe @pyRest -m venv $venv 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0 -and (Test-Path $venvPy)) {
                & $venvPy -m pip install --disable-pip-version-check --quiet esptool 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0 -and (Test-Command $cmd)) {
                    Good 'esptool is ready.'
                    return ,$cmd
                }
            }
        } catch { }
        $ErrorActionPreference = 'Stop'
        Warn 'Could not install esptool with Python. Downloading it from Espressif instead.'
    } else {
        Say '    Python is not installed. That is fine: using the esptool that Espressif publishes.'
    }

    # Espressif's standalone build, checked against the SHA256 GitHub lists for it
    $zip = Join-Path $WorkDir "esptool-$EsptoolVersion-windows-amd64.zip"
    Say "    Downloading esptool $EsptoolVersion (about 65 MB, only the first time)..."
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $EsptoolZipUrl -OutFile $zip
    } catch {
        Stop-WithMessage @(
            'Could not download esptool from GitHub.',
            'Check that this computer is online, then run this again.',
            "Details: $($_.Exception.Message)")
    }
    $got = Get-FileSha256 $zip
    if ($got -ne $EsptoolZipSha256) {
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Stop-WithMessage @(
            'The esptool download is damaged or not the expected file, so it was not used.',
            'Run this again. If it keeps happening, your network may be changing downloads.')
    }
    if (Test-Path $toolDir) { Remove-Item $toolDir -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $toolDir -Force
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    $exe = Get-ChildItem -Path $toolDir -Filter 'esptool.exe' -Recurse | Select-Object -First 1
    if (-not $exe -or -not (Test-Command @($exe.FullName))) {
        Stop-WithMessage @('esptool was downloaded but does not start. Your antivirus may have blocked it.')
    }
    Good 'esptool is ready.'
    return ,@($exe.FullName)
}

# ---------------------------------------------------------------------------
# Getting the firmware
# ---------------------------------------------------------------------------

# Reads the first 64 hex characters from a .sha256 file ("<hash>  <name>" or just "<hash>").
function Read-ShaFile([string]$path) {
    $text = Get-Content -Path $path -Raw
    if ($text -match '([0-9a-fA-F]{64})') { return $Matches[1].ToLowerInvariant() }
    return $null
}

function Find-LocalFirmware {
    if ($Firmware) {
        if (-not (Test-Path $Firmware)) { Stop-WithMessage @("The file $Firmware does not exist.") }
        return (Resolve-Path $Firmware).Path
    }
    $plain = Join-Path $ScriptDir 'orion-firmware-full.bin'
    if (Test-Path $plain) { return $plain }
    # A versioned release file, such as orion-firmware-1.0.0-full.bin. Newest first.
    $versioned = Get-ChildItem -Path $ScriptDir -Filter 'orion-firmware-*-full.bin' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($versioned) { return $versioned.FullName }
    return $null
}

function Get-Firmware {
    $local = Find-LocalFirmware
    if ($local) {
        Good "Using the firmware file $local"
        $shaFile = "$local.sha256"
        $expected = $null
        if (Test-Path $shaFile) { $expected = Read-ShaFile $shaFile }
        if ($expected) {
            if ((Get-FileSha256 $local) -ne $expected) {
                Stop-WithMessage @(
                    "$(Split-Path -Leaf $local) does not match its checksum file.",
                    'The file is damaged or incomplete. Download it again.')
            }
            Good 'Checksum matches.'
        } else {
            Warn 'No checksum file next to it, so it could not be checked.'
        }
        return $local
    }

    $bin = Join-Path $WorkDir 'orion-firmware-full.bin'
    $sha = "$bin.sha256"
    Say '    Downloading the latest Orion firmware...'
    Remove-Item $bin, $sha -Force -ErrorAction SilentlyContinue
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $FirmwareUrl -OutFile $bin
    } catch {
        Remove-Item $bin -Force -ErrorAction SilentlyContinue
        Stop-WithMessage @(
            'Could not download the Orion firmware.',
            "Address: $FirmwareUrl",
            'Check that this computer is online. If it is, the release may not be published yet:',
            'download orion-firmware-full.bin from https://github.com/MultiX0/orion/releases,',
            'put it in the same folder as this script, and run this again.',
            "Details: $($_.Exception.Message)")
    }
    $size = (Get-Item $bin).Length
    if ($size -lt 65536) {
        Stop-WithMessage @("The downloaded firmware is only $size bytes, which is too small to be real. Try again later.")
    }
    Good ("Downloaded {0:N1} MB." -f ($size / 1MB))

    $expected = $null
    try {
        Invoke-WebRequest -UseBasicParsing -Uri "$FirmwareUrl.sha256" -OutFile $sha
        $expected = Read-ShaFile $sha
    } catch { }
    if ($expected) {
        if ((Get-FileSha256 $bin) -ne $expected) {
            Remove-Item $bin -Force -ErrorAction SilentlyContinue
            Stop-WithMessage @(
                'The firmware download does not match its published checksum, so it was not used.',
                'Run this again. If it keeps happening, your network may be changing downloads.')
        }
        Good 'Checksum matches the release.'
    } else {
        Warn 'The release has no checksum file, so the download could not be checked.'
    }
    return $bin
}

# ---------------------------------------------------------------------------
# Flashing
# ---------------------------------------------------------------------------

function Invoke-Flash([string[]]$esptool, [string]$port, [string]$bin) {
    $ErrorActionPreference = 'Continue'
    $exe = $esptool[0]
    $rest = @()
    if ($esptool.Count -gt 1) { $rest = $esptool[1..($esptool.Count - 1)] }
    # esptool 5 renamed write_flash to write-flash and warns about the old name.
    $write = 'write_flash'
    $major = Get-EsptoolMajor $esptool
    if ($major -ge 5) { $write = 'write-flash' }
    foreach ($baud in 460800, 115200) {
        $flashArgs = $rest + @('--chip', 'esp32s3', '--port', $port, '--baud', "$baud", $write, '0x0', $bin)
        if ($DryRun) {
            Warn "Dry run, nothing written. Would run: $exe $($flashArgs -join ' ')"
            return $true
        }
        Say "    Writing at $baud baud. Do not unplug the board..."
        # Out-Host keeps esptool's output on screen and out of this function's return value.
        & $exe @flashArgs | Out-Host
        if ($LASTEXITCODE -eq 0) { return $true }
        if ($baud -ne 115200) {
            Warn 'That did not work. Trying again more slowly.'
            Start-Sleep -Seconds 2
        }
    }
    return $false
}

# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '  Orion installer' -ForegroundColor White
Write-Host '  This puts the Orion software on your LilyGO T-CameraPlus-S3.'
Write-Host '  It takes a few minutes. Keep the board plugged in until it says Done.'
if ($DryRun) { Write-Host '  Dry run: the board will not be written.' -ForegroundColor Yellow }

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

Step 'Step 1 of 4: finding your board'
$boardPort = Select-BoardPort

Step 'Step 2 of 4: getting the flashing tool'
$esptool = Get-Esptool

Step 'Step 3 of 4: getting the Orion firmware'
$bin = Get-Firmware

Step 'Step 4 of 4: installing Orion on the board'
$ok = Invoke-Flash $esptool $boardPort $bin
if (-not $ok) {
    Show-NoBoardHelp 'The board did not answer. Things to try:'
    Say '  5. Close any other program that may be using the board (Arduino, a serial monitor).'
    Stop-WithMessage @('', 'Stopped: the firmware could not be written. Nothing is broken; you can run this again.')
}

Write-Host ''
if ($DryRun) {
    Write-Host 'Dry run finished. Everything is ready; nothing was written.' -ForegroundColor Green
} else {
    Write-Host 'Done. Orion is installed.' -ForegroundColor Green
    Say 'The board restarts by itself and shows a setup screen with its name and a code.'
    Say 'If the screen stays dark, tap the RST button on the side of the board once.'
    Say ''
    Say 'Next: open the Orion app on your phone or PC and tap "Find my Orion".'
    Say 'Get the app here: https://github.com/MultiX0/orion/releases/latest'
}
Finish 0
