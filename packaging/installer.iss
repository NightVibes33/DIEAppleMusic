; Installer for 死ねアップル. Everything the app needs is inside; nothing is downloaded.
; Run it again later and it offers to update, repair or uninstall what's there.
#define AppName "死ねアップル"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define AppExe "死ねアップル.exe"
#define AppGuid "{8C3F7A52-6D1E-4B8F-9A47-2E5D7C1B9F03}"

[Setup]
AppId={{#AppGuid}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
VersionInfoVersion={#AppVersion}
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} Setup
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; An update installs into the same folder without asking again.
DisableDirPage=auto
UsePreviousAppDir=yes
UsePreviousTasks=yes
; Installs for the current user without admin rights; can be switched to all users.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputBaseFilename={#AppName}-Setup
SetupIconFile=..\gui\app.ico
; The app icon in the top-right of every installer page, sharp at any display scale.
WizardSmallImageFile=wizard\small-55.bmp,wizard\small-64.bmp,wizard\small-69.bmp,wizard\small-83.bmp,wizard\small-92.bmp,wizard\small-110.bmp,wizard\small-138.bmp
; The side panel on the first and last pages (replaces Inno Setup's stock box picture).
; One image per display scale (100-250%); stretching covers any in-between size,
; so the panel always fills edge to edge.
WizardImageFile=wizard\side-164.bmp,wizard\side-205.bmp,wizard\side-246.bmp,wizard\side-287.bmp,wizard\side-328.bmp,wizard\side-369.bmp,wizard\side-410.bmp
WizardImageStretch=yes
; Tells Windows to refresh icons after installing, so the desktop and Start menu
; show the new icon instead of one cached from an earlier version.
ChangesAssociations=yes
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2
SolidCompression=yes
LZMANumBlockThreads=4
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.15063
WizardStyle=modern
; Closes the app if it's open during an update, and reopens nothing by itself.
CloseApplications=force
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\app\{#AppName}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; An update replaces the whole program folder, so files that a newer build no
; longer ships can't linger. Settings, sign-in and music live elsewhere.
Type: filesandordirs; Name: "{app}\_internal"
; Remove flat Qt runtime copies left by older builds; a stale copy can shadow QtCore.
Type: files; Name: "{app}\Qt6Core.dll"
; Remove unrelated ICU builds that old packages collected from other software.
Type: files; Name: "{app}\icu*.dll"

[Icons]
; Shortcuts take their picture from app.ico, so Windows never reuses an icon it
; cached for the exe path from an older version.
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; IconFilename: "{app}\app.ico"; AppUserModelID: "ShineAppuru.Desktop"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; IconFilename: "{app}\app.ico"; Tasks: desktopicon; AppUserModelID: "ShineAppuru.Desktop"

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
const
  UninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#AppGuid}_is1';

var
  InstalledVersion, InstalledUninstaller, InstalledLocation: String;
  ChoicePage: TInputOptionWizardPage;
  ClosingAfterUninstall: Boolean;

{ Finds an existing installation, per-user or for all users. }
function FindInstalled(): Boolean;
var
  Roots: array of Integer;
  I: Integer;
begin
  Result := False;
  SetArrayLength(Roots, 3);
  Roots[0] := HKEY_CURRENT_USER;
  Roots[1] := HKEY_LOCAL_MACHINE_64;
  Roots[2] := HKEY_LOCAL_MACHINE_32;
  for I := 0 to GetArrayLength(Roots) - 1 do
    if RegQueryStringValue(Roots[I], UninstallKey, 'UninstallString', InstalledUninstaller) then
    begin
      if not RegQueryStringValue(Roots[I], UninstallKey, 'DisplayVersion', InstalledVersion) then
        InstalledVersion := '';
      if not RegQueryStringValue(Roots[I], UninstallKey, 'InstallLocation', InstalledLocation) then
        InstalledLocation := '';
      Result := True;
      Exit;
    end;
end;

{ Runs a PowerShell snippet against the programs running from Folder ($p holds
  them) and returns its exit code. }
function RunForAppProcesses(Folder, Script: String): Integer;
begin
  if not Exec('powershell.exe',
      '-NoProfile -NonInteractive -WindowStyle Hidden -Command "' +
      '$d = ''' + RemoveBackslashUnlessRoot(Folder) + '\''; ' +
      '$p = @(Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith($d, [StringComparison]::OrdinalIgnoreCase) }); ' +
      Script + '"', '', SW_HIDE, ewWaitUntilTerminated, Result) then
    Result := -1;
end;

function IsAppRunning(Folder: String): Boolean;
begin
  Result := RunForAppProcesses(Folder, 'if ($p.Count) { exit 1 } else { exit 0 }') = 1;
end;

{ If the app is running from Folder, offers to close it (asks it nicely first,
  like clicking X, then forces it). False if the person says no or it won't close. }
function CloseRunningApp(Folder: String; Silent: Boolean): Boolean;
var
  Tries: Integer;
begin
  Result := True;
  if (Folder = '') or not IsAppRunning(Folder) then
    Exit;
  Log('The app is running from ' + Folder);
  if not Silent then
    if MsgBox('{#AppName} is open.' + #13#10 + #13#10 + 'Setup needs to close it to continue. Close it now?',
              mbConfirmation, MB_YESNO) <> IDYES then
    begin
      Result := False;
      Exit;
    end;
  RunForAppProcesses(Folder,
    '$p | ForEach-Object { [void]$_.CloseMainWindow() }; ' +
    '$p | Wait-Process -Timeout 6 -ErrorAction SilentlyContinue; ' +
    '$p | Where-Object { -not $_.HasExited } | Stop-Process -Force -ErrorAction SilentlyContinue');
  for Tries := 1 to 5 do
  begin
    if not IsAppRunning(Folder) then
      Exit;
    Sleep(500);
  end;
  Result := False;
  if not Silent then
    MsgBox('{#AppName} could not be closed. Close it yourself, then run Setup again.', mbError, MB_OK);
end;

{ Before anything else: an installed copy that's open must close first. }
function InitializeSetup(): Boolean;
begin
  Result := True;
  if FindInstalled() then
    Result := CloseRunningApp(InstalledLocation, WizardSilent());
end;

function InitializeUninstall(): Boolean;
begin
  Result := CloseRunningApp(ExpandConstant('{app}'), UninstallSilent());
end;

{ -1 if the installed copy is older than this installer, 0 if the same, 1 if newer. }
function CompareWithInstalled(): Integer;
var
  Mine, Theirs: Int64;
begin
  if (InstalledVersion = '') or not StrToVersion(InstalledVersion, Theirs) then
  begin
    Result := -1;  { unknown version: treat as older }
    Exit;
  end;
  StrToVersion('{#AppVersion}', Mine);
  Result := ComparePackedVersion(Theirs, Mine);
end;

procedure InitializeWizard();
var
  Order: Integer;
  Title, Intro, Keep: String;
begin
  if not FindInstalled() then
    Exit;
  Order := CompareWithInstalled();
  Keep := 'Your settings, Apple ID sign-in and music are kept.';
  if Order < 0 then
  begin
    Title := 'Update {#AppName}';
    if InstalledVersion <> '' then
      Intro := 'Version ' + InstalledVersion + ' is installed. This installer has version {#AppVersion}.'
    else
      Intro := 'An older version is installed. This installer has version {#AppVersion}.';
  end
  else if Order = 0 then
  begin
    Title := '{#AppName} is already installed';
    Intro := 'Version {#AppVersion} is already installed on this computer.';
  end
  else
  begin
    Title := 'A newer version is installed';
    Intro := 'Version ' + InstalledVersion + ' is installed, which is newer than this installer ({#AppVersion}).';
  end;
  ChoicePage := CreateInputOptionPage(wpWelcome, Title, 'Choose what to do.', Intro, True, False);
  if Order < 0 then
    ChoicePage.Add('Update to version {#AppVersion}' + #13#10 + Keep)
  else if Order = 0 then
    ChoicePage.Add('Repair (reinstall version {#AppVersion})' + #13#10 + Keep)
  else
    ChoicePage.Add('Replace it with older version {#AppVersion} (not recommended)' + #13#10 + Keep);
  ChoicePage.Add('Uninstall {#AppName}');
  if Order > 0 then
    ChoicePage.SelectedValueIndex := 1
  else
    ChoicePage.SelectedValueIndex := 0;
end;

{ Runs the existing uninstaller (it asks whether to also remove settings). }
function RunUninstaller(): Boolean;
var
  Exe: String;
  Code: Integer;
begin
  Exe := RemoveQuotes(InstalledUninstaller);
  Result := Exec(Exe, '/NORESTART', '', SW_SHOWNORMAL, ewWaitUntilTerminated, Code) and (Code = 0);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (ChoicePage <> nil) and (CurPageID = ChoicePage.ID) and (ChoicePage.SelectedValueIndex = 1) then
  begin
    Result := False;
    if RunUninstaller() then
    begin
      ClosingAfterUninstall := True;
      WizardForm.Close;
    end;
  end;
end;

procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  { After uninstalling, close without asking "Exit Setup?". }
  if ClosingAfterUninstall then
    Confirm := False;
end;

{ Update and repair don't need the welcome text twice. }
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (ChoicePage <> nil) and (PageID = wpSelectTasks) and (ChoicePage.SelectedValueIndex = 0);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usPostUninstall) and not UninstallSilent then
    { Phrased so the default answer (Yes, highlighted) is the safe one. }
    if MsgBox('Keep your settings, Apple ID sign-in and download history on this computer?' + #13#10 +
              'Choose No to remove them too. Your downloaded music is never affected.', mbConfirmation, MB_YESNO) = IDNO then
    begin
      DelTree(ExpandConstant('{userappdata}\{#AppName}'), True, True, True);
      DelTree(ExpandConstant('{localappdata}\{#AppName}'), True, True, True);
    end;
end;
