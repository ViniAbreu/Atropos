unit Atropos.Tests.DelphiEnvironment;

interface
uses DUnitX.TestFramework, Atropos.Adapters.DelphiEnvironment,
  System.SysUtils, System.IOUtils, System.Classes, System.Win.Registry, Winapi.Windows;

type
  TDelphiEnvironmentProbe = class(TDelphiEnvironmentAdapter)
  protected
    function GetRegisteredInstallations: TArray<TDelphiInstallation>; override;
    function GetConfiguredBDSPath: string; override;
  public
    Installations: TArray<TDelphiInstallation>;
    ConfiguredPath: string;
    procedure Add(const AVersion, ARoot: string);
  end;

  TLocalDelphiProbe = class(TDelphiEnvironmentAdapter)
  protected
    function GetConfiguredBDSPath: string; override;
  public
    function Registered: TArray<TDelphiInstallation>;
  end;

  TRegistryEnvironmentProbe = class(TLocalDelphiProbe)
  protected
    function GetRegistryBaseKey: string; override;
  public
    BaseKey: string;
  end;

  [TestFixture]
  TDelphiEnvironmentTests = class
  private
    FRoot, FProject, FRegistryKey: string;
    FEnvironment: TDelphiEnvironmentProbe;
    procedure Registration(const AVersion, AValue, AData: string; AView: Cardinal = KEY_WOW64_64KEY);
    function Installation(const AName: string; const AExecutable: string = 'bin\bds.exe'): string;
    procedure ProjectVersion(const AVersion: string);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [TestCase('Athens','20.1,23.0')]
    [TestCase('AthensUpdate','20.2,23.0')]
    [TestCase('SharedFormatMinimum','20.3,23.0')]
    [TestCase('Florence','20.4,37.0')]
    [TestCase('Alexandria','19.5,22.0')]
    [TestCase('Sydney','19.2,21.0')]
    [TestCase('Rio','18.8,20.0')]
    [TestCase('Seattle','18.0,17.0')]
    procedure KnownFormatHints(const AFormat, AVersion: string);
    [Test] procedure UnknownFormatDoesNotGuess;
    [Test] procedure ExplicitBDSOverridesProjectHint;
    [Test] procedure StaleBDSDoesNotHideValidRegistryInstallation;
    [Test] procedure ExactAvailableVersionIsPreferred;
    [Test] procedure Shared203FormatSelectsNewestValidInstallation;
    [Test] procedure Delphi13FormatDoesNotDowngradeToDelphi12;
    [Test] procedure StaleExactRegistrationFallsBackToDelphi13;
    [Test] procedure StaleHighestRegistrationDoesNotHideOtherInstallations;
    [Test] procedure HighestVersionAcrossHivesWins;
    [Test] procedure EqualVersionPreservesUserPreference;
    [Test] procedure ProfilesAreNotInstallationVersions;
    [Test] procedure MissingProjectUsesNewestValidInstallation;
    [Test] procedure MalformedProjectUsesNewestValidInstallation;
    [Test] procedure NoInstallationReturnsEmpty;
    [Test] procedure IDE64OnlyInstallationIsAccepted;
    [Test] procedure CompleteHeadlessToolsAreAccepted;
    [Test] procedure EmptyOrPartialInstallationIsRejected;
    [Test] procedure RealRegistryCandidatesHaveExistingTools;
    [TestCase('InstalledSeattle','18.0,17.0')]
    [TestCase('InstalledAlexandria','19.5,22.0')]
    [TestCase('InstalledAthens','20.1,23.0')]
    [TestCase('InstalledFlorence','20.4,37.0')]
    procedure InstalledVersionMatrix(const AFormat, AVersion: string);
    [Test] procedure RegistryAppRecoversStaleRootDir;
    [Test] procedure RegistryApp64WorksWithoutRootDir;
    [Test] procedure Registry32BitViewIsRead;
    [Test] procedure RegistryMissingValuesAndProfilesAreSkipped;
  end;

implementation

function TDelphiEnvironmentProbe.GetRegisteredInstallations: TArray<TDelphiInstallation>;
begin Result := Installations; end;
function TDelphiEnvironmentProbe.GetConfiguredBDSPath: string;
begin Result := ConfiguredPath; end;
procedure TDelphiEnvironmentProbe.Add(const AVersion, ARoot: string);
var I: Integer;
begin
  I := Length(Installations); SetLength(Installations,I+1);
  Installations[I].Version := AVersion; Installations[I].RootDir := ARoot;
end;
function TLocalDelphiProbe.GetConfiguredBDSPath: string;
begin Result := ''; end;
function TLocalDelphiProbe.Registered: TArray<TDelphiInstallation>;
begin Result := GetRegisteredInstallations; end;

function TRegistryEnvironmentProbe.GetRegistryBaseKey: string;
begin Result := BaseKey; end;

procedure TDelphiEnvironmentTests.Registration(const AVersion, AValue, AData: string; AView: Cardinal);
var R: TRegistry;
begin
  R := TRegistry.Create(KEY_ALL_ACCESS or AView);
  try
    R.RootKey := HKEY_CURRENT_USER;
    Assert.IsTrue(R.OpenKey(FRegistryKey+'\'+AVersion,True));
    R.WriteString(AValue,AData);
  finally R.Free; end;
end;

procedure TDelphiEnvironmentTests.Setup;
begin
  FRegistryKey := 'Software\Atropos.Tests\Environment\'+TGuid.NewGuid.ToString;
  FRoot := TPath.Combine(TPath.GetTempPath,'Atropos-environment-'+TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
  FProject := TPath.Combine(FRoot,'sample.dproj');
  FEnvironment := TDelphiEnvironmentProbe.Create;
end;
procedure TDelphiEnvironmentTests.TearDown;
var R: TRegistry; V: Cardinal;
begin
  Assert.IsTrue(FRegistryKey.StartsWith('Software\Atropos.Tests\Environment\'));
  for V in [KEY_WOW64_64KEY,KEY_WOW64_32KEY] do
  begin
    R := TRegistry.Create(KEY_ALL_ACCESS or V);
    try R.RootKey := HKEY_CURRENT_USER; R.DeleteKey(FRegistryKey); finally R.Free; end;
  end;
  FEnvironment.Free;
  if TDirectory.Exists(FRoot) then TDirectory.Delete(FRoot,True);
end;
function TDelphiEnvironmentTests.Installation(const AName, AExecutable: string): string;
var LFile: string;
begin
  Result := TPath.Combine(FRoot,AName);
  LFile := TPath.Combine(Result,AExecutable);
  TDirectory.CreateDirectory(ExtractFileDir(LFile));
  TFile.WriteAllText(LFile,'');
end;
procedure TDelphiEnvironmentTests.ProjectVersion(const AVersion: string);
begin
  TFile.WriteAllText(FProject,'<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'+
    '<PropertyGroup><ProjectVersion>'+AVersion+'</ProjectVersion></PropertyGroup></Project>');
end;
procedure TDelphiEnvironmentTests.KnownFormatHints(const AFormat, AVersion: string);
begin Assert.AreEqual(AVersion,TDelphiVersionMap.FromProjectVersion(AFormat)); end;
procedure TDelphiEnvironmentTests.UnknownFormatDoesNotGuess;
begin
  Assert.AreEqual('',TDelphiVersionMap.FromProjectVersion('99.9'));
  Assert.AreEqual('',TDelphiVersionMap.FromProjectVersion('20.99'));
  Assert.IsTrue(TDelphiVersionMap.IsAmbiguous('20.3'));
end;
procedure TDelphiEnvironmentTests.ExplicitBDSOverridesProjectHint;
var LExplicit: string;
begin
  ProjectVersion('20.1');
  FEnvironment.Add('23.0',Installation('Athens'));
  LExplicit := Installation('Custom Florence');
  FEnvironment.ConfiguredPath := '"'+LExplicit+'\"';
  Assert.AreEqual(LExplicit,FEnvironment.ResolveDelphiPath(FProject));
end;
procedure TDelphiEnvironmentTests.StaleBDSDoesNotHideValidRegistryInstallation;
var LRoot: string;
begin
  LRoot := Installation('Athens'); ProjectVersion('20.1');
  FEnvironment.Add('23.0',LRoot); FEnvironment.ConfiguredPath := TPath.Combine(FRoot,'Removed');
  Assert.AreEqual(LRoot,FEnvironment.ResolveDelphiPath(FProject));
end;
procedure TDelphiEnvironmentTests.ExactAvailableVersionIsPreferred;
var LRoot: string;
begin
  ProjectVersion('20.1'); LRoot := Installation('Athens');
  FEnvironment.Add('23.0',LRoot); FEnvironment.Add('37.0',Installation('Florence'));
  Assert.AreEqual(LRoot,FEnvironment.ResolveDelphiPath(FProject));
end;
procedure TDelphiEnvironmentTests.Shared203FormatSelectsNewestValidInstallation;
var LRoot: string;
begin
  ProjectVersion('20.3'); LRoot := Installation('Florence');
  FEnvironment.Add('23.0',Installation('Athens')); FEnvironment.Add('37.0',LRoot);
  Assert.AreEqual(LRoot,FEnvironment.ResolveDelphiPath(FProject));
end;
procedure TDelphiEnvironmentTests.Delphi13FormatDoesNotDowngradeToDelphi12;
begin
  ProjectVersion('20.4'); FEnvironment.Add('23.0',Installation('Athens'));
  Assert.AreEqual('',FEnvironment.ResolveDelphiPath(FProject));
end;
procedure TDelphiEnvironmentTests.StaleExactRegistrationFallsBackToDelphi13;
var LRoot: string;
begin
  ProjectVersion('20.1'); LRoot := Installation('Florence');
  FEnvironment.Add('23.0',TPath.Combine(FRoot,'Removed Athens')); FEnvironment.Add('37.0',LRoot);
  Assert.AreEqual(LRoot,FEnvironment.ResolveDelphiPath(FProject));
end;
procedure TDelphiEnvironmentTests.StaleHighestRegistrationDoesNotHideOtherInstallations;
var LRoot: string;
begin
  ProjectVersion('20.1'); LRoot := Installation('Florence');
  FEnvironment.Add('99.0',TPath.Combine(FRoot,'Removed')); FEnvironment.Add('37.0',LRoot);
  Assert.AreEqual(LRoot,FEnvironment.ResolveDelphiPath(FProject));
end;
procedure TDelphiEnvironmentTests.HighestVersionAcrossHivesWins;
var LRoot: string;
begin
  LRoot := Installation('Machine Florence');
  FEnvironment.Add('22.0',Installation('User Alexandria')); FEnvironment.Add('37.0',LRoot);
  Assert.AreEqual(LRoot,FEnvironment.ResolveDelphiPath(FProject));
end;
procedure TDelphiEnvironmentTests.EqualVersionPreservesUserPreference;
var LRoot: string;
begin
  LRoot := Installation('User Florence');
  FEnvironment.Add('37.0',LRoot); FEnvironment.Add('37.0',Installation('Machine Florence'));
  Assert.AreEqual(LRoot,FEnvironment.ResolveDelphiPath(FProject));
end;
procedure TDelphiEnvironmentTests.ProfilesAreNotInstallationVersions;
var LRoot: string;
begin
  LRoot := Installation('Florence');
  FEnvironment.Add('99.0_x64',Installation('Profile')); FEnvironment.Add('37.0',LRoot);
  Assert.AreEqual(LRoot,FEnvironment.ResolveDelphiPath(FProject));
end;
procedure TDelphiEnvironmentTests.MissingProjectUsesNewestValidInstallation;
var LRoot: string;
begin
  LRoot := Installation('Florence'); FEnvironment.Add('37.0',LRoot);
  Assert.AreEqual(LRoot,FEnvironment.ResolveDelphiPath(FProject));
end;
procedure TDelphiEnvironmentTests.MalformedProjectUsesNewestValidInstallation;
var LRoot: string;
begin
  TFile.WriteAllText(FProject,'<invalid'); LRoot := Installation('Florence'); FEnvironment.Add('37.0',LRoot);
  Assert.AreEqual(LRoot,FEnvironment.ResolveDelphiPath(FProject));
end;
procedure TDelphiEnvironmentTests.NoInstallationReturnsEmpty;
begin Assert.AreEqual('',FEnvironment.ResolveDelphiPath(FProject)); end;
procedure TDelphiEnvironmentTests.IDE64OnlyInstallationIsAccepted;
var LRoot: string;
begin
  LRoot := Installation('Florence64','bin64\bds.exe'); FEnvironment.Add('37.0',LRoot);
  Assert.AreEqual(LRoot,FEnvironment.ResolveDelphiPath(FProject));
end;
procedure TDelphiEnvironmentTests.CompleteHeadlessToolsAreAccepted;
var LRoot: string;
begin
  LRoot := Installation('BuildTools','bin\dcc32.exe');
  Installation('BuildTools','bin\rsvars.bat'); Installation('BuildTools','bin\CodeGear.Delphi.Targets');
  FEnvironment.Add('37.0',LRoot);
  Assert.AreEqual(LRoot,FEnvironment.ResolveDelphiPath(FProject));
end;
procedure TDelphiEnvironmentTests.EmptyOrPartialInstallationIsRejected;
begin
  FEnvironment.Add('37.0',Installation('Partial','bin\rsvars.bat'));
  Assert.AreEqual('',FEnvironment.ResolveDelphiPath(FProject));
end;
procedure TDelphiEnvironmentTests.RealRegistryCandidatesHaveExistingTools;
var LProbe: TLocalDelphiProbe; I: TDelphiInstallation; LSelected: string; LHighest,V: Double;
begin
  LProbe := TLocalDelphiProbe.Create;
  try
    LHighest := 0; LSelected := '';
    for I in LProbe.Registered do
    begin
      Assert.IsNotEmpty(TDelphiEnvironmentAdapter.UsableRoot(I.RootDir));
      Assert.IsTrue(TryStrToFloat(I.Version,V,TFormatSettings.Invariant));
      if V>LHighest then begin LHighest := V; LSelected := I.RootDir; end;
    end;
    Assert.AreEqual(LSelected,LProbe.ResolveDelphiPath(FProject));
  finally LProbe.Free; end;
end;

procedure TDelphiEnvironmentTests.RegistryAppRecoversStaleRootDir;
var P: TRegistryEnvironmentProbe; LRoot: string;
begin
  LRoot := Installation('Custom Folder');
  Registration('23.0','RootDir',TPath.Combine(FRoot,'Removed'));
  Registration('23.0','App',TPath.Combine(LRoot,'bin\bds.exe'));
  P := TRegistryEnvironmentProbe.Create;
  try P.BaseKey := FRegistryKey; Assert.AreEqual(LRoot,P.ResolveDelphiPath(FProject));
  finally P.Free; end;
end;
procedure TDelphiEnvironmentTests.RegistryApp64WorksWithoutRootDir;
var P: TRegistryEnvironmentProbe; LRoot: string;
begin
  LRoot := Installation('Florence64','bin64\bds.exe');
  Registration('37.0','App x64',TPath.Combine(LRoot,'bin64\bds.exe'));
  P := TRegistryEnvironmentProbe.Create;
  try P.BaseKey := FRegistryKey; Assert.AreEqual(LRoot,P.ResolveDelphiPath(FProject));
  finally P.Free; end;
end;
procedure TDelphiEnvironmentTests.Registry32BitViewIsRead;
var P: TRegistryEnvironmentProbe; LRoot: string;
begin
  LRoot := Installation('Athens');
  Registration('23.0','RootDir',LRoot,KEY_WOW64_32KEY);
  P := TRegistryEnvironmentProbe.Create;
  try P.BaseKey := FRegistryKey; Assert.AreEqual(LRoot,P.ResolveDelphiPath(FProject));
  finally P.Free; end;
end;
procedure TDelphiEnvironmentTests.RegistryMissingValuesAndProfilesAreSkipped;
var P: TRegistryEnvironmentProbe; LRoot: string;
begin
  LRoot := Installation('Florence');
  Registration('99.0','UnrelatedValue','unused');
  Registration('99.0_x64','RootDir',Installation('Profile'));
  Registration('37.0','RootDir',LRoot);
  P := TRegistryEnvironmentProbe.Create;
  try P.BaseKey := FRegistryKey; Assert.AreEqual(LRoot,P.ResolveDelphiPath(FProject));
  finally P.Free; end;
end;

procedure TDelphiEnvironmentTests.InstalledVersionMatrix(const AFormat, AVersion: string);
var P: TLocalDelphiProbe; I: TDelphiInstallation; Expected: string;
begin
  ProjectVersion(AFormat); Expected := '';
  P := TLocalDelphiProbe.Create;
  try
    for I in P.Registered do
      if I.Version=AVersion then begin Expected := I.RootDir; Break; end;
    if Expected.IsEmpty then
    begin
      Assert.Pass('Optional local Delphi installation unavailable: '+AVersion);
      Exit;
    end;
    Writeln('Installed BDS '+AVersion+': '+Expected);
    Assert.AreEqual(Expected,P.ResolveDelphiPath(FProject));
  finally P.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDelphiEnvironmentTests);
end.
