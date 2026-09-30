# Runs idf.py inside firmware/ with the ESP-IDF environment loaded.
# Build with:  powershell -ExecutionPolicy Bypass -File tools\idf.ps1 build
# Targets Windows PowerShell 5.1, which every Windows machine has, and stays
# compatible with pwsh (PowerShell 7).

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$IdfArgs
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$firmware = Join-Path $repo 'firmware'

function Find-IdfPath {
    if ($env:ORION_IDF_PATH -and (Test-Path (Join-Path $env:ORION_IDF_PATH 'export.ps1'))) {
        return $env:ORION_IDF_PATH
    }
    if ($env:IDF_PATH -and (Test-Path (Join-Path $env:IDF_PATH 'export.ps1'))) {
        return $env:IDF_PATH
    }
    $roots = @('C:\Espressif\frameworks', "$env:USERPROFILE\esp", 'C:\esp')
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $hit = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
               Where-Object { Test-Path (Join-Path $_.FullName 'export.ps1') } |
               Sort-Object Name -Descending | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

$idfPath = Find-IdfPath
if (-not $idfPath) {
    Write-Error "ESP-IDF not found. Looked at ORION_IDF_PATH, IDF_PATH, C:\Espressif\frameworks, $env:USERPROFILE\esp, C:\esp."
    exit 1
}

$env:IDF_PATH = $idfPath
if (-not $env:IDF_TOOLS_PATH) { $env:IDF_TOOLS_PATH = "$env:USERPROFILE\.espressif" }

# Called from Git Bash, this inherits MSYSTEM and friends. ESP-IDF's activation
# refuses to run when it sees them, with "MSys/Mingw is not supported". Clear
# the markers so either shell works.
foreach ($v in 'MSYSTEM', 'MINGW_PREFIX', 'MINGW_CHOST', 'MSYS2_PATH_TYPE', 'MSYSTEM_PREFIX') {
    if (Test-Path "env:$v") { Remove-Item "env:$v" -ErrorAction SilentlyContinue }
}

# export.ps1 shells out to python, which writes its banner to stderr. Windows
# PowerShell 5.1 turns native stderr into ErrorRecords, so with
# ErrorActionPreference Stop the export dies on its own progress messages.
# Drop to Continue across the call, then put it back.
$prev = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& (Join-Path $idfPath 'export.ps1') | Out-Null
$ErrorActionPreference = $prev

if (-not $env:IDF_PYTHON_ENV_PATH) {
    Write-Error "ESP-IDF export did not set up the environment. Check $idfPath\export.ps1."
    exit 1
}

if (-not (Test-Path $firmware)) {
    Write-Error "No firmware directory at $firmware"
    exit 1
}

Push-Location $firmware
try {
    # `--esptool ...` runs esptool inside the IDF environment instead of idf.py.
    # Writing a single partition image is not something idf.py can do, and this
    # keeps one place that knows how to activate ESP-IDF.
    if ($IdfArgs.Count -gt 0 -and $IdfArgs[0] -eq '--esptool') {
        $rest = @($IdfArgs | Select-Object -Skip 1)
        & python -m esptool @rest
    }
    else {
        $idfPy = Join-Path $env:IDF_PATH 'tools\idf.py'
        & python $idfPy @IdfArgs
    }
    $code = $LASTEXITCODE
}
finally {
    Pop-Location
}

exit $code
