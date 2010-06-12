[Setup]
AppName=Lumbricus Terrestris
;xxx agree about version naming; could also insert SVN revision via a build script
AppVerName=Lumbricus Terrestris SVN Build
OutputDir=.
OutputBaseFilename=LumbricusSetup
DefaultDirName={pf}\Lumbricus
DefaultGroupName=Lumbricus
AppendDefaultDirName=no
Uninstallable=yes
SolidCompression=yes
PrivilegesRequired=none

;xxx localize custom messages in this setup
[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "de"; MessagesFile: "compiler:Languages\German.isl"

[Files]
Source: "..\bin\*.dll"; DestDir: "{app}\bin"
Source: "..\bin\lumbricus.exe"; DestDir: "{app}\bin"
Source: "..\bin\extractdata.exe"; DestDir: "{app}\bin"
Source: "..\bin\server.exe"; DestDir: "{app}\bin"
Source: "..\share\lumbricus\*"; Excludes: "data2,.svn,Thumbs.db"; DestDir: "{app}\share\lumbricus"; Flags: ignoreversion recursesubdirs sortfilesbyextension
Source: "..\src\README"; DestDir: "{app}"; DestName: "ReadMe.txt"

[Run]
Filename: "{app}\ReadMe.txt"; Description: "View the README file"; Flags: postinstall shellexec skipifsilent unchecked
Filename: "{app}\bin\lumbricus.exe"; Description: "Start Lumbricus now!"; Flags: postinstall nowait skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\share\lumbricus\data2"

[Icons]
Name: "{group}\Lumbricus"; Filename: "{app}\bin\lumbricus.exe"; WorkingDir: "{app}\bin"
Name: "{group}\{cm:UninstallProgram,Lumbricus}"; Filename: "{uninstallexe}"

[Code]
var
  WwpPage: TWizardPage;
  ConvertBtn: TButton;
  WwpDirTree: TFolderTreeView;
  ConvertDone: Boolean;

//Run extractdata.exe to convert WWP files
procedure ConvertBtnClick(Sender: TObject);
var
  res: Integer;
begin
  if not FileExists(WwpDirTree.Directory + '\wwp.exe') then begin
    MsgBox('Worms World Party™ has not been found in the selected directory. Please select the correct directory.', mbError, MB_OK);
    Exit;
  end;
  ConvertBtn.Enabled := False;
  ConvertBtn.Caption := 'Working...';
  Exec(ExpandConstant('{app}\bin\extractdata.exe'), '"' + WwpDirTree.Directory + '"', ExpandConstant('{app}\bin'), SW_SHOW, ewWaitUntilTerminated, res);
  ConvertBtn.Caption := 'Conversion done';
  ConvertDone := True;
end;

procedure InitializeWizard();
var InfoLbl: TLabel;
begin
  // Create WWP dir page
  WwpPage := CreateCustomPage(wpInstalling,
    'Convert WWP graphics for Lumbricus', 'Select your Worms World Party™ folder');

  ConvertBtn := TButton.Create(WwpPage);
  ConvertBtn.Width := ScaleX(100);
  ConvertBtn.Height := ScaleY(23);
  ConvertBtn.Left := WwpPage.SurfaceWidth / 2 - ConvertBtn.Width / 2;
  ConvertBtn.Top := WwpPage.SurfaceHeight - ConvertBtn.Height;
  ConvertBtn.Caption := 'Start conversion';
  ConvertBtn.OnClick := @ConvertBtnClick;
  ConvertBtn.Parent := WwpPage.Surface;

  InfoLbl := TLabel.Create(WwpPage);
  InfoLbl.Width := WwpPage.SurfaceWidth;
  //xxx fixed height (autosize didn't really work)
  InfoLbl.Height := ScaleY(65);
  //InfoLbl.Align := alTop;
  InfoLbl.AutoSize := False;
  InfoLbl.WordWrap := True;
  InfoLbl.Caption := 'Lumbricus can use graphics from the original Worms World Party™, provided you own the game, using an included converter.'#13#10#13#10 +
    'If you want to use this feature, browse for your WWP folder (i.e. where wwp.exe is located), and click "Start conversion".';
  InfoLbl.Parent := WwpPage.Surface;

  WwpDirTree := TFolderTreeView.Create(WwpPage);
  WwpDirTree.Width := WwpPage.SurfaceWidth * 2 / 3;
  WwpDirTree.Height := WwpPage.SurfaceHeight - ConvertBtn.Height - InfoLbl.Height - 10;
  WwpDirTree.Left := WwpPage.SurfaceWidth / 2 - WwpDirTree.Width / 2;
  WwpDirTree.Top := InfoLbl.Height + 5;
  WwpDirTree.Parent := WwpPage.Surface;
  //WwpDirTree.Directory := ExpandConstant('{src}');
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  //Show a warning if the user tries to skip the WWP conversion
  if (CurPageID = WwpPage.ID) and not ConvertDone then begin
    if MsgBox('Really continue without graphics conversion? Keep in mind that the included (GPLed) graphics are very ugly...',
      mbConfirmation, MB_YESNO) = IDNO then Result := False
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  userDir, settingsFile: String;
begin
  if CurStep = ssPostInstall then begin
    //Write chosen locale to lumbricus config file
    userDir := ExpandConstant('{userdocs}\Lumbricus');
    settingsFile := userDir + '\settings2.conf';
    //Don't overwrite
    if not FileExists(settingsFile) then begin
      ForceDirectories(userDir);
      SaveStringToFile(settingsFile, ExpandConstant('locale = "{language}"'), False);
    end;
  end;
end;
