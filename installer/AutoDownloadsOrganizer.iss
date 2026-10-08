#define AppName "AutoDownloadsOrganizer"
#define AppVersion "6.0.0"
#define AppPublisher "AutoDownloadsOrganizer"
#define PackageName "AutoDownloadsOrganizer-" + AppVersion

[Setup]
AppId={{71F4D338-A113-4A36-9024-31926E26C7B1}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
PrivilegesRequired=lowest
OutputDir=..\release
OutputBaseFilename={#AppName}-Setup-{#AppVersion}
SetupIconFile=..\assets\AutoDownloadsOrganizer.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\AutoDownloadsOrganizer.exe

[Tasks]
Name: "autostart"; Description: "Start monitoring Downloads when I sign in to Windows"; GroupDescription: "Startup:"; Flags: unchecked
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "..\release\{#PackageName}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\AutoDownloadsOrganizer"; Filename: "{app}\AutoDownloadsOrganizer.exe"
Name: "{group}\Uninstall AutoDownloadsOrganizer"; Filename: "{uninstallexe}"
Name: "{userdesktop}\AutoDownloadsOrganizer"; Filename: "{app}\AutoDownloadsOrganizer.exe"; Tasks: desktopicon
Name: "{userstartup}\AutoDownloadsOrganizer"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Watch-Downloads.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\AutoDownloadsOrganizer.exe"; Tasks: autostart

[Run]
Filename: "{app}\AutoDownloadsOrganizer.exe"; Description: "Launch AutoDownloadsOrganizer"; Flags: postinstall nowait skipifsilent
