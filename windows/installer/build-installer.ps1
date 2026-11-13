# Builds Orion's Windows setup program, everything a new PC needs inside it:
# the app, the Microsoft C++ runtime, and the Node.js the PC agent runs on.
# See docs/RELEASING.md.
#
#   powershell -ExecutionPolicy Bypass -File windows\installer\build-installer.ps1
#   powershell -ExecutionPolicy Bypass -File windows\installer\build-installer.ps1 -SkipFlutterBuild
#
# Writes build\installer\Orion-<version>-windows-x64-setup.exe. Targets Windows
# PowerShell 5.1.

[CmdletBinding()]
param(
    [switch]$SkipFlutterBuild
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is many times slower with the bar

# Node.js for the PC agent (dsh, its MCP servers, every npx they start). Pinned
# with its checksum from https://nodejs.org/dist/<version>/SHASUMS256.txt: the
# agent has full access to the PC, so this changes only on purpose.
$NodeVersion = 'v24.22.2'
$NodeSha256 = 'ca1bff5d8ead13c9f2ea404a176db46bd430704d5b5113734049fa365e7799e2'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$work = Join-Path $repo 'build\installer'
New-Item -ItemType Directory -Force $work | Out-Null

# The version, from pubspec.yaml: 1.2.3+4 is 1.2.3.
$pubspec = Get-Content (Join-Path $repo 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)') { throw 'No version in pubspec.yaml' }
$version = $Matches[1]
Write-Host "Orion $version"

# 1. Node, downloaded once and checked against the published checksum.
$zipName = "node-$NodeVersion-win-x64.zip"
$zip = Join-Path $work $zipName
if (-not (Test-Path $zip)) {
    Write-Host "Downloading $zipName"
    Invoke-WebRequest "https://nodejs.org/dist/$NodeVersion/$zipName" -OutFile $zip -UseBasicParsing
}
$sha = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sha -ne $NodeSha256) {
    Remove-Item $zip -Force
    throw "$zipName checksum $sha is not the pinned $NodeSha256"
}
$nodeDir = Join-Path $work "node-$NodeVersion-win-x64"
if (-not (Test-Path (Join-Path $nodeDir 'node.exe'))) {
    if (Test-Path $nodeDir) { Remove-Item $nodeDir -Recurse -Force }
    Expand-Archive $zip -DestinationPath $work -Force
}
Write-Host "Node $NodeVersion checked: $sha"

# 2. The Microsoft C++ runtime, from the newest Visual Studio.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) { throw 'vswhere.exe not found: install Visual Studio with C++' }
$vs = & $vswhere -latest -products '*' -property installationPath
$crt = Get-ChildItem (Join-Path $vs 'VC\Redist\MSVC') -Directory |
       Where-Object { $_.Name -match '^\d' } | Sort-Object Name -Descending |
       ForEach-Object { Get-ChildItem (Join-Path $_.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' } |
       Select-Object -First 1
if (-not $crt) { throw "No x64 Microsoft.VC*.CRT under $vs\VC\Redist\MSVC" }
Write-Host "C++ runtime: $($crt.FullName)"

# 3. The app.
if (-not $SkipFlutterBuild) {
    Push-Location $repo
    try {
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed ($LASTEXITCODE)" }
    } finally { Pop-Location }
}
if (-not (Test-Path (Join-Path $repo 'build\windows\x64\runner\Release\orion.exe'))) { throw 'No build\windows\x64\runner\Release\orion.exe' }

# 4. The setup program.
$iscc = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 (ISCC.exe) not found: https://jrsoftware.org/isinfo.php' }
& $iscc "/DAppVersion=$version" "/DRedistDir=$($crt.FullName)" "/DNodeDir=$nodeDir" (Join-Path $PSScriptRoot 'orion.iss')
if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }

$setup = Join-Path $work "Orion-$version-windows-x64-setup.exe"
Write-Host "Built $setup ($([math]::Round((Get-Item $setup).Length / 1MB, 1)) MB)"
