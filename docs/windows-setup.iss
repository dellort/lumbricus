; Requires Inno Preprocessor (part of Inno QuickStart Pack)
; If "Full" is defined (iscc /dFull), all the WWP files are included
;   (which would be illegal, don't publish the result)

; Read SVN revision from entries file (line 4)
#define i
#define hFile = FileOpen(SourcePath + "\.svn\entries")
#if !hFile
  #error SVN entries file not found. Not run from SVN working copy?
#endif
#for {i = 0; i < 3; i++} \
  FileRead(hFile)
#define SVNRevision FileRead(hFile)
#expr FileClose(hFile)
#pragma message "Working copy revision is " + SVNRevision

[Setup]
AppName=Lumbricus Terrestris
;xxx agree about version naming/numbering (for now, SVN revision)
AppVerName=Lumbricus Terrestris SVN {#SVNRevision} {#Defined(Full)?"Full":""}
VersionInfoVersion=0.1.0.{#SVNRevision}
OutputDir=.
OutputBaseFilename=LumbricusSetup_r{#SVNRevision}{#Defined(Full)?"_full":""}
DefaultDirName={pf}\Lumbricus
DefaultGroupName=Lumbricus
AppendDefaultDirName=no
Uninstallable=yes
SolidCompression=yes
PrivilegesRequired=none

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "de"; MessagesFile: "compiler:Languages\German.isl"

[CustomMessages]
en.ViewReadme=View the README file
en.LaunchGame=Play Lumbricus now!
en.ConvertPageTitle=Convert WWP graphics for Lumbricus
en.ConvertPageSubtitle=Select your Worms World Party™ folder
en.ConvertInfoText=Lumbricus can use graphics from the original Worms World Party™, provided you own the game, using an included converter.%n%nIf you want to use this feature, browse for your WWP folder (i.e. where wwp.exe is located), and click "Start conversion".
en.ConvertInvalidDir=Worms World Party™ has not been found in the selected directory. Please select the correct directory.
en.ConvertSkipWarning=Really continue without graphics conversion? Keep in mind that the included (GPLed) graphics are very ugly...
en.ConvertStart=Start conversion
en.ConvertWorking=Working...
en.ConvertDone=Conversion done

de.ViewReadme=LIESMICH-Datei anzeigen
de.LaunchGame=Lumbricus jetzt spielen!
de.ConvertPageTitle=WWP-Grafiken in Lumbricus importieren
de.ConvertPageSubtitle=Wählen Sie Ihr Worms World Party™-Verzeichnis aus
de.ConvertInfoText=Besitzen Sie eine Kopie von Worms World Party™, kann Lumbricus die Grafiken des Originalspiels mit einem enthaltenen Konverter importieren.%n%nFalls Sie dieses Feature verwenden möchten, wählen Sie unten ihr WWP-Verzeichnis aus und klicken "Import starten".
de.ConvertInvalidDir=Worms World Party™ wurde im gewählten Verzeichnis nicht gefunden. Bitte wählen Sie das korrekte Verzeichnis aus.
de.ConvertSkipWarning=Wirklich ohne Grafik-Import fortfahren? Die enthaltenen (GPL-)Grafiken sind ziemlich häßlich...
de.ConvertStart=Import starten
de.ConvertWorking=Arbeite...
de.ConvertDone=Import fertig

[Files]
Source: "..\bin\*.dll"; DestDir: "{app}\bin"
Source: "..\bin\lumbricus.exe"; DestDir: "{app}\bin"
Source: "..\bin\extractdata.exe"; DestDir: "{app}\bin"
Source: "..\bin\lumbricus_server.exe"; DestDir: "{app}\bin"
Source: "..\share\lumbricus\*"; Excludes: "data2,.svn,Thumbs.db"; DestDir: "{app}\share\lumbricus"; Flags: ignoreversion recursesubdirs sortfilesbyextension
Source: "..\src\README"; DestDir: "{app}"; DestName: "ReadMe.txt"
#ifdef Full
Source: "..\share\lumbricus\data2\*"; Excludes: ".svn,Thumbs.db"; DestDir: "{app}\share\lumbricus\data2"; Flags: ignoreversion recursesubdirs sortfilesbyextension
#endif

[Run]
Filename: "{app}\ReadMe.txt"; Description: "{cm:ViewReadme}"; Flags: postinstall shellexec skipifsilent unchecked
Filename: "{app}\bin\lumbricus.exe"; Description: "{cm:LaunchGame}"; Flags: postinstall nowait skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\share\lumbricus\data2"

[Icons]
Name: "{group}\Lumbricus"; Filename: "{app}\bin\lumbricus.exe"; WorkingDir: "{app}\bin"
Name: "{group}\{cm:UninstallProgram,Lumbricus}"; Filename: "{uninstallexe}"

[Code]
// Code to run extractdata, not needed for full setup
#ifndef Full
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
  //Check directory
  if not FileExists(WwpDirTree.Directory + '\wwp.exe') or not FileExists(WwpDirTree.Directory + '\data\Gfx\Gfx.dir') then begin
    MsgBox(CustomMessage('ConvertInvalidDir'), mbError, MB_OK);
    Exit;
  end;
  ConvertBtn.Enabled := False;
  ConvertBtn.Caption := CustomMessage('ConvertWorking');
  Exec(ExpandConstant('{app}\bin\extractdata.exe'), '"' + WwpDirTree.Directory + '"', ExpandConstant('{app}\bin'), SW_SHOW, ewWaitUntilTerminated, res);
  ConvertBtn.Caption := CustomMessage('ConvertDone');
  ConvertDone := True;
end;

procedure InitializeWizard();
var InfoLbl: TLabel;
begin
  // Create WWP dir page
  WwpPage := CreateCustomPage(wpInstalling,
    CustomMessage('ConvertPageTitle'), CustomMessage('ConvertPageSubtitle'));

  ConvertBtn := TButton.Create(WwpPage);
  ConvertBtn.Width := ScaleX(100);
  ConvertBtn.Height := ScaleY(23);
  ConvertBtn.Left := WwpPage.SurfaceWidth / 2 - ConvertBtn.Width / 2;
  ConvertBtn.Top := WwpPage.SurfaceHeight - ConvertBtn.Height;
  ConvertBtn.Caption := CustomMessage('ConvertStart')
  ConvertBtn.OnClick := @ConvertBtnClick;
  ConvertBtn.Parent := WwpPage.Surface;

  InfoLbl := TLabel.Create(WwpPage);
  InfoLbl.Width := WwpPage.SurfaceWidth;
  //xxx fixed height (autosize didn't really work)
  InfoLbl.Height := ScaleY(65);
  //InfoLbl.Align := alTop;
  InfoLbl.AutoSize := False;
  InfoLbl.WordWrap := True;
  InfoLbl.Caption := CustomMessage('ConvertInfoText');
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
    if MsgBox(CustomMessage('ConvertSkipWarning'),
      mbConfirmation, MB_YESNO) = IDNO then Result := False
  end;
end;
#endif  ; ifndef full

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
