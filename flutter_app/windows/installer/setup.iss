[Setup]
AppName=TagFix
AppVersion={#MyAppVersion}
DefaultDirName={autopf}\TagFix
ArchitecturesInstallIn64BitMode=x64
OutputBaseFilename=TagFix_Setup_{#MyAppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\TagFix"; Filename: "{app}\TagFix.exe"
Name: "{autodesktop}\TagFix"; Filename: "{app}\TagFix.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\TagFix.exe"; Description: "{cm:LaunchProgram,TagFix}"; Flags: nowait postinstall skipifsilent
