; Orion for Windows, the setup program (Inno Setup 6.3 or later).
;
; It installs for the current user, so it needs no admin rights, and carries
; everything a new PC is missing next to orion.exe: the Microsoft C++ runtime, so it
; runs without the Visual C++ Redistributable, and Node.js in {app}\node, which the
; PC agent runs on (dsh and its MCP servers). That Node is Orion's own: it is not
; put on the user's PATH, and it is removed with Orion. See docs/RELEASING.md.
;
;   powershell -ExecutionPolicy Bypass -File windows\installer\build-installer.ps1
;
; builds the app, fetches and checks Node, and runs
;
;   ISCC /DAppVersion=1.0.0 /DRedistDir="<VS>\VC\Redist\MSVC\<ver>\x64\Microsoft.VC145.CRT" /DNodeDir="<node-vX-win-x64>" windows\installer\orion.iss
;
; The result is build\installer\Orion-<version>-windows-x64-setup.exe.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\build\installer"
#endif
#ifndef RedistDir
  #error Pass /DRedistDir= the x64 Microsoft.VC14x.CRT folder of your Visual Studio
#endif
#ifndef NodeDir
  #error Pass /DNodeDir= the unpacked node-vX-win-x64 folder (build-installer.ps1 does)
#endif

[Setup]
; Never change the AppId: upgrades and the uninstaller find Orion by it.
AppId={{FBFAE5A2-6129-4F8C-ACA9-5BDE61E949AC}
AppName=Orion
AppVersion={#AppVersion}
AppVerName=Orion {#AppVersion}
AppPublisher=MultiX0
AppPublisherURL=https://www.joinorion.io
AppSupportURL=https://github.com/MultiX0/orion/issues
AppUpdatesURL=https://github.com/MultiX0/orion/releases/latest
DefaultDirName={autopf}\Orion
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=Orion-{#AppVersion}-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\orion.exe
UninstallDisplayName=Orion
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
CloseApplications=yes
RestartApplications=no
VersionInfoVersion={#AppVersion}
VersionInfoCompany=MultiX0
VersionInfoProductName=Orion
VersionInfoDescription=Orion setup

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RedistDir}\msvcp140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RedistDir}\vcruntime140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RedistDir}\vcruntime140_1.dll"; DestDir: "{app}"; Flags: ignoreversion
; Node.js for the PC agent, replaced whole on an upgrade.
Source: "{#NodeDir}\*"; DestDir: "{app}\node"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
Type: filesandordirs; Name: "{app}\node"

[UninstallDelete]
; Anything npm left beside the bundled Node.
Type: filesandordirs; Name: "{app}\node"

[Icons]
Name: "{autoprograms}\Orion"; Filename: "{app}\orion.exe"
Name: "{autodesktop}\Orion"; Filename: "{app}\orion.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\orion.exe"; Description: "{cm:LaunchProgram,Orion}"; Flags: nowait postinstall skipifsilent
