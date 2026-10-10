; Inno Setup script for Hyde Music (Windows x64).
; Built by CI:  iscc /DAppVersion=1.0.0 packaging\windows\hyde-music.iss
; Input:  build\windows\x64\runner\Release\  (flutter build windows --release)
; Output: dist\HydeMusic-<version>-windows-x64-Setup.exe

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
; Never change AppId: it is how Windows recognises updates of the same app.
AppId={{192E692B-BF24-4B42-8FB6-C1D85C640791}
AppName=Hyde Music
AppVersion={#AppVersion}
AppVerName=Hyde Music {#AppVersion}
AppPublisher=Hyde OpenSource
AppPublisherURL=https://www.hydeos.tech/music-docs.html
AppSupportURL=https://github.com/Hyde-OpenSource/Hyde-Music-Desktop/issues
AppUpdatesURL=https://github.com/Hyde-OpenSource/Hyde-Music-Desktop/releases
DefaultDirName={autopf}\Hyde Music
DefaultGroupName=Hyde Music
DisableProgramGroupPage=yes
; Per-user install by default (no admin prompt); users can choose all users.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\dist
OutputBaseFilename=HydeMusic-{#AppVersion}-windows-x64-Setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\HydeMusic.exe
UninstallDisplayName=Hyde Music
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=yes
MinVersion=10.0.17763

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Hyde Music"; Filename: "{app}\HydeMusic.exe"
Name: "{group}\Uninstall Hyde Music"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Hyde Music"; Filename: "{app}\HydeMusic.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\HydeMusic.exe"; Description: "{cm:LaunchProgram,Hyde Music}"; Flags: nowait postinstall skipifsilent
