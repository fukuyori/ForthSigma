#ifndef AppVersion
  #error AppVersion must be supplied by scripts/build-installer.ps1
#endif
#ifndef PayloadExe
  #error PayloadExe must be supplied by scripts/build-installer.ps1
#endif

[Setup]
AppId={{3F365E98-9222-41FB-B792-03AF86BFE763}
AppName=FORTH/Σ
AppVersion={#AppVersion}
AppPublisher=fukuyori
DefaultDirName={autopf}\FORTH Sigma
DefaultGroupName=FORTH Sigma
UninstallDisplayName=FORTH/Σ
OutputBaseFilename=FORTH-Sigma-Setup-{#AppVersion}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
DisableProgramGroupPage=yes
LicenseFile=..\LICENSE
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
Uninstallable=yes

#ifdef EnableSigning
SignTool=sigma
SignedUninstaller=yes
#endif

[Files]
Source: "{#PayloadExe}"; DestDir: "{app}"; DestName: "sigma.exe"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\forth\sigma\USER_MANUAL.md"; DestDir: "{app}\docs"; Flags: ignoreversion

[Icons]
Name: "{group}\FORTH Sigma"; Filename: "{app}\sigma.exe"
Name: "{group}\Uninstall FORTH Sigma"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\sigma.exe"; Description: "FORTH/Σを起動"; Flags: postinstall nowait skipifsilent
