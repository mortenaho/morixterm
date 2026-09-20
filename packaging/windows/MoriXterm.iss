#define MyAppName "MoriXterm"
#define MyAppVersion GetEnv("MORIXTERM_VERSION")
#define MyAppPublisher "mortenaho"
#define MyAppURL "https://github.com/mortenaho/morixterm"
#define MyAppExeName "morixtrem.exe"

[Setup]
AppId={{7D95EC26-E0C8-4A50-9337-2C235F0D6A52}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\MoriXterm
DefaultGroupName=MoriXterm
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\release
OutputBaseFilename=MoriXterm-{#MyAppVersion}-Windows-x64-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}

[Files]
Source: "..\..\dist\windows\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\MoriXterm"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\MoriXterm"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch MoriXterm"; Flags: nowait postinstall skipifsilent
