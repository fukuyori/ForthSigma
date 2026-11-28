#ifndef AppVersion
  #error AppVersion must be supplied by scripts/build-installer.ps1
#endif
#ifndef PayloadExe
  #error PayloadExe must be supplied by scripts/build-installer.ps1
#endif

; /DForth2012 makes the installer of the FORTH 2012 profile. It is another product,
; with its own AppId, folder, shortcuts and command name (sigma-forth2012, as in the
; macOS package), so that both can be installed and both can be on the PATH.
#ifdef Forth2012
  #define ProductId "{{84BE3885-1D72-481B-AD5F-6E4E475A7586}"
  #define ProductName "FORTH/Σ (FORTH 2012)"
  #define ProductFolder "FORTH Sigma 2012"
  #define ProductShortcut "FORTH Sigma (FORTH 2012)"
  #define ProductFile "-forth2012"
  #define ProductExe "sigma-forth2012.exe"
#else
  #define ProductId "{{3F365E98-9222-41FB-B792-03AF86BFE763}"
  #define ProductName "FORTH/Σ"
  #define ProductFolder "FORTH Sigma"
  #define ProductShortcut "FORTH Sigma"
  #define ProductFile ""
  #define ProductExe "sigma.exe"
#endif

[Setup]
AppId={#ProductId}
AppName={#ProductName}
AppVersion={#AppVersion}
AppPublisher=fukuyori
DefaultDirName={autopf}\{#ProductFolder}
DefaultGroupName={#ProductFolder}
UninstallDisplayName={#ProductName}
; The icon of the program (assets\icon), for the setup program and for the list of
; installed apps.
SetupIconFile=..\assets\icon\sigma.ico
UninstallDisplayIcon={app}\{#ProductExe}
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
; Tell running programs that the PATH changed.
ChangesEnvironment=yes

#ifdef EnableSigning
SignTool=sigma
SignedUninstaller=yes
#endif

[Tasks]
Name: "addtopath"; Description: "{#ProductExe} のフォルダーを PATH に追加する"

[Files]
Source: "{#PayloadExe}"; DestDir: "{app}"; DestName: "{#ProductExe}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\docs\USER_MANUAL.md"; DestDir: "{app}\docs"; Flags: ignoreversion
; The libraries of include need the graphics, sound and extension words, which the
; FORTH 2012 profile leaves out (its ZIP leaves them out too).
#ifndef Forth2012
Source: "..\include\*.fs"; DestDir: "{app}\include"; Flags: ignoreversion
#endif

[Registry]
; The folder is added to the system PATH once; the uninstaller takes it out again.
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; \
    ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}"; \
    Tasks: addtopath; Check: NeedsAddPath(ExpandConstant('{app}'))

[Icons]
Name: "{group}\{#ProductShortcut}"; Filename: "{app}\{#ProductExe}"
Name: "{group}\Uninstall {#ProductShortcut}"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\{#ProductExe}"; Description: "{#ProductName}を起動"; Flags: postinstall nowait skipifsilent

[Code]
const
  EnvironmentKey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment';

// True when the folder is not yet one of the entries of the system PATH.
function NeedsAddPath(Folder: string): Boolean;
var
  Paths: string;
begin
  if not RegQueryStringValue(HKEY_LOCAL_MACHINE, EnvironmentKey, 'Path', Paths) then
  begin
    Result := True;
    exit;
  end;
  Result := Pos(';' + Uppercase(Folder) + ';', ';' + Uppercase(Paths) + ';') = 0;
end;

// Takes every entry equal to the folder out of the system PATH.
procedure RemovePath(Folder: string);
var
  Paths, Entry, Kept: string;
  P: Integer;
begin
  if not RegQueryStringValue(HKEY_LOCAL_MACHINE, EnvironmentKey, 'Path', Paths) then
    exit;
  Kept := '';
  Paths := Paths + ';';
  while Paths <> '' do
  begin
    P := Pos(';', Paths);
    Entry := Copy(Paths, 1, P - 1);
    Delete(Paths, 1, P);
    if (Entry <> '') and (CompareText(Entry, Folder) <> 0) then
    begin
      if Kept <> '' then
        Kept := Kept + ';';
      Kept := Kept + Entry;
    end;
  end;
  RegWriteExpandStringValue(HKEY_LOCAL_MACHINE, EnvironmentKey, 'Path', Kept);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
    RemovePath(ExpandConstant('{app}'));
end;
