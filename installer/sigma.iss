#ifndef AppVersion
  #error AppVersion must be supplied by scripts/build-installer.ps1
#endif
#ifndef PayloadExe
  #error PayloadExe must be supplied by scripts/build-installer.ps1
#endif

; /DForth2012 makes the installer of the FORTH 2012 profile. It is another product,
; with its own AppId, folder and shortcuts, so that both can be installed side by side.
#ifdef Forth2012
  #define ProductId "{{84BE3885-1D72-481B-AD5F-6E4E475A7586}"
  #define ProductName "FORTH/Σ (FORTH 2012)"
  #define ProductFolder "FORTH Sigma 2012"
  #define ProductShortcut "FORTH Sigma (FORTH 2012)"
  #define ProductFile "-forth2012"
#else
  #define ProductId "{{3F365E98-9222-41FB-B792-03AF86BFE763}"
  #define ProductName "FORTH/Σ"
  #define ProductFolder "FORTH Sigma"
  #define ProductShortcut "FORTH Sigma"
  #define ProductFile ""
#endif

[Setup]
AppId={#ProductId}
AppName={#ProductName}
AppVersion={#AppVersion}
AppPublisher=fukuyori
DefaultDirName={autopf}\{#ProductFolder}
DefaultGroupName={#ProductFolder}
UninstallDisplayName={#ProductName}
OutputBaseFilename=sigma-{#AppVersion}-windows-x86_64{#ProductFile}-setup
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
Source: "..\docs\USER_MANUAL.md"; DestDir: "{app}\docs"; Flags: ignoreversion
; The libraries of include need the graphics, sound and extension words, which the
; FORTH 2012 profile leaves out (its ZIP leaves them out too).
#ifndef Forth2012
Source: "..\include\*.fs"; DestDir: "{app}\include"; Flags: ignoreversion
#endif

[Icons]
Name: "{group}\{#ProductShortcut}"; Filename: "{app}\sigma.exe"
Name: "{group}\Uninstall {#ProductShortcut}"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\sigma.exe"; Description: "{#ProductName}を起動"; Flags: postinstall nowait skipifsilent
