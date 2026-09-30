# Builds this checkout in a short build directory and flashes the app partition
# only, and only when the build succeeded.
#
# The short directory is because a deep checkout path is too long for Windows
# MAX_PATH once esp-tflite-micro's object paths are added. The app partition
# at 0x10000 is the one tools\flash.ps1 -App writes; the assets, model and nvs
# partitions are left as they are.
#
#   powershell -ExecutionPolicy Bypass -File tools\cloud\build_flash_app.ps1
#   powershell -ExecutionPolicy Bypass -File tools\cloud\build_flash_app.ps1 -NoFlash

[CmdletBinding()]
param(
    [string]$BuildDir = 'C:\ocl_build',
    [switch]$NoFlash
)

# Continue: the child's stderr ("Activating ESP-IDF") is not an error, and
# Windows PowerShell 5.1 would abort on it under Stop.
$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$log = Join-Path $repo 'logs\build.txt'
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null

& powershell -ExecutionPolicy Bypass -File (Join-Path $repo 'tools\idf.ps1') -B $BuildDir build *> $log
$ok = Select-String -Path $log -Pattern 'Project build complete' -Quiet
Select-String -Path $log -Pattern 'error:|FAILED|undefined reference' | Select-Object -First 12 |
    ForEach-Object { $_.Line }
if (-not $ok) {
    Write-Host 'build_flash_app: build FAILED, nothing flashed'
    exit 1
}
Write-Host 'build_flash_app: build ok'
if ($NoFlash) { exit 0 }

& powershell -ExecutionPolicy Bypass -File (Join-Path $repo 'tools\flash.ps1') `
    -Bin (Join-Path $BuildDir 'orion.bin') -Address 0x10000 *>&1 |
    Select-String -Pattern 'Hash of data|error|failed' | ForEach-Object { $_.Line.Trim() }
exit $LASTEXITCODE
