; TagQt Inno Setup Installer Script
; Version is injected by CI, never hardcode it here

#define MyAppName "TagQt"
#define MyAppPublisher "TagQt"
#define MyAppURL "https://github.com/near-link/tagqt"
#define MyAppExeName "TagQt.exe"

[Setup]
AppId={{F3A7B2C1-D4E5-4F60-A1B2-C3D4E5F60718}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}/releases
VersionInfoVersion={#MyAppNumericVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=A music metadata editor built with Python and Qt
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=installer_output
OutputBaseFilename=TagQt-windows-{#MyAppVersion}-setup
SetupIconFile=assets\logo.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName} {#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
MinVersion=10.0
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DisableProgramGroupPage=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; \
  Description: "{cm:CreateDesktopIcon}"; \
  GroupDescription: "{cm:AdditionalIcons}"; \
  Flags: unchecked

[Files]
Source: "dist\TagQt\*"; \
  DestDir: "{app}"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; \
  Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; \
  Filename: "{app}\{#MyAppExeName}"; \
  Tasks: desktopicon
Name: "{group}\Uninstall {#MyAppName}"; \
  Filename: "{uninstallexe}"

[Run]
Filename: "{app}\{#MyAppExeName}"; \
  Description: "{cm:LaunchProgram,{#MyAppName}}"; \
  Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\__pycache__"
Type: filesandordirs; Name: "{app}\logs"
