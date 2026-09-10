unit Atropos.Tests.ProjectContext;

interface

uses DUnitX.TestFramework, Atropos.Core.Compilation;

type
  [TestFixture]
  TProjectContextTests = class
  private
    FRoot, FProject: string;
    FProvider: IProjectContextProvider;
    function WriteText(const AName, AText: string): string;
    function FindOption(const AContext: TProjectCompilationContext;
      const AName: string): string;
    procedure CheckFailure(const AKind: Integer);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] [TestCase('Debug32', 'Debug,Win32')]
    [TestCase('Debug64', 'Debug,Win64')]
    [TestCase('Release32', 'Release,Win32')]
    [TestCase('Release64', 'Release,Win64')]
    procedure EvaluatesImportedPropertiesPerTarget(const AConfig, APlatform: string);
    [Test] procedure DefaultTargetComesFromProject;
    [Test] procedure RecordsImportedFileHashes;
    [Test] procedure EvaluationDoesNotExecuteBuildTargets;
    [Test] procedure MissingImportFailsExplicitly;
    [Test] procedure RepeatedEvaluationSeesChangedProperties;
    [Test] procedure MalformedResponseFailsExplicitly;
    [Test] procedure CancelledProcessFailsExplicitly;
    [Test] procedure TimedOutProcessFailsExplicitly;
    [Test] procedure InvalidTargetIsRejectedBeforeStartingProcess;
    [Test] procedure MissingEnvironmentFailsExplicitly;
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils, System.Hash,
  Atropos.Core.Ports, Atropos.Adapters.ProjectContext,
  Atropos.Adapters.BuildService;

type
  TContextProcessStub = class(TInterfacedObject, IBuildProcessRunner)
  public
    Kind: Integer;
    function Execute(const ACommand: string; ATimeoutMs: Cardinal;
      const AShouldCancel: TCancellationCheck; out AOutput: string;
      out AExitCode: Cardinal; out ATimedOut, ACancelled: Boolean): Boolean;
  end;

function TContextProcessStub.Execute(const ACommand: string; ATimeoutMs: Cardinal;
  const AShouldCancel: TCancellationCheck; out AOutput: string;
  out AExitCode: Cardinal; out ATimedOut, ACancelled: Boolean): Boolean;
begin
  Result := True;
  AExitCode := 0;
  AOutput := 'invalid output';
  ATimedOut := Kind = 1;
  ACancelled := Kind = 2;
end;

procedure TProjectContextTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'Atropos Context ação ' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(TPath.Combine(FRoot, 'bin'));
  TFile.WriteAllText(TPath.Combine(FRoot, 'bin\rsvars.bat'),
    '@set "BDS=%~dp0.."', TEncoding.ASCII);
  WriteText('shared.props', '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '<PropertyGroup><DCC_Define>IMPORTED</DCC_Define>' +
    '<DCC_UnitSearchPath>first;second</DCC_UnitSearchPath>' +
    '<IncludePath>inc;$(DCC_UnitSearchPath)</IncludePath>' +
    '<DCC_Namespace>System;Example</DCC_Namespace>' +
    '<DCC_UnitAlias>Old=New;Legacy=Modern</DCC_UnitAlias></PropertyGroup></Project>');
  FProject := WriteText('Test.dproj', '<Project ToolsVersion="4.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '<PropertyGroup><Config>Release</Config><Platform>Win32</Platform><MainSource>Test.dpr</MainSource></PropertyGroup>' +
    '<Import Project="shared.props"/>' +
    '<PropertyGroup><DCC_Define>$(DCC_Define);$([System.String]::Copy(''$(Config)'').ToUpper());$(Platform)</DCC_Define></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Config)'' == ''Debug''"><DCC_RangeChecking>true</DCC_RangeChecking></PropertyGroup>' +
    '<ItemGroup><DCCReference Include="Common.pas"/></ItemGroup>' +
    '<ItemGroup Condition="''$(Platform)'' == ''Win64''"><DCCReference Include="Only64.pas"/></ItemGroup>' +
    '<Target Name="ChangeSettings" BeforeTargets="Build"><PropertyGroup><DCC_Define>RUNTIME</DCC_Define></PropertyGroup>' +
    '<WriteLinesToFile File="built.txt" Lines="executed"/></Target></Project>');
  FProvider := TMsBuildProjectContext.Create;
end;

procedure TProjectContextTests.TearDown;
begin
  FProvider := nil;
  if not TPath.GetFullPath(FRoot).StartsWith(
    TPath.Combine(TPath.GetTempPath, 'Atropos Context ação '), True) then
    raise Exception.Create('Refusing cleanup outside project context test directory');
  TDirectory.Delete(FRoot, True);
end;

function TProjectContextTests.WriteText(const AName, AText: string): string;
begin
  Result := TPath.Combine(FRoot, AName);
  TFile.WriteAllText(Result, AText, TEncoding.UTF8);
end;

function TProjectContextTests.FindOption(const AContext: TProjectCompilationContext;
  const AName: string): string;
var LOption: TCompilerOption;
begin
  for LOption in AContext.Options do
    if LOption.Name = AName then
      Exit(LOption.Value);
  raise Exception.Create('Expected compiler option is missing: ' + AName);
end;

procedure TProjectContextTests.EvaluatesImportedPropertiesPerTarget(
  const AConfig, APlatform: string);
var
  LContext: TProjectCompilationContext;
begin
  LContext := FProvider.EvaluateProject(FProject, FRoot, TBuildTarget.Create(AConfig, APlatform));
  Assert.AreEqual(AConfig, LContext.Target.Configuration);
  Assert.AreEqual(APlatform, LContext.Target.Platform);
  Assert.Contains<string>(LContext.Defines, 'IMPORTED');
  Assert.Contains<string>(LContext.Defines, AConfig.ToUpper);
  Assert.Contains<string>(LContext.Defines, APlatform);
  Assert.AreEqual(TPath.Combine(FRoot, 'first'), LContext.SearchPaths[0]);
  Assert.AreEqual(TPath.Combine(FRoot, 'inc'), LContext.IncludePaths[0]);
  Assert.AreEqual('System', LContext.Namespaces[0]);
  Assert.AreEqual('Old=New', LContext.Aliases[0]);
  Assert.AreEqual(TPath.Combine(FRoot, 'Common.pas'), LContext.UnitPaths[0]);
  Assert.AreEqual(TPath.Combine(FRoot, 'Test.dpr'), LContext.MainSource);
  if AConfig = 'Debug' then
    Assert.AreEqual('true', FindOption(LContext, 'RangeChecking'));
  if AConfig = 'Release' then
    Assert.AreEqual('', FindOption(LContext, 'RangeChecking'));
  if APlatform = 'Win64' then
    Assert.Contains<string>(LContext.UnitPaths, TPath.Combine(FRoot, 'Only64.pas'));
  if APlatform = 'Win32' then
    Assert.AreEqual<NativeInt>(1, Length(LContext.UnitPaths));
end;

procedure TProjectContextTests.DefaultTargetComesFromProject;
var LContext: TProjectCompilationContext;
begin
  LContext := FProvider.EvaluateProject(FProject, FRoot, Default(TBuildTarget));
  Assert.AreEqual('Release', LContext.Target.Configuration);
  Assert.AreEqual('Win32', LContext.Target.Platform);
end;

procedure TProjectContextTests.RecordsImportedFileHashes;
var LContext: TProjectCompilationContext; LFile: TSourceDependency;
begin
  LContext := FProvider.EvaluateProject(FProject, FRoot, Default(TBuildTarget));
  Assert.AreEqual<NativeInt>(2, Length(LContext.ProjectFiles));
  for LFile in LContext.ProjectFiles do
    Assert.AreEqual(THashSHA2.GetHashStringFromFile(LFile.FilePath).ToUpper, LFile.ContentHash);
end;

procedure TProjectContextTests.EvaluationDoesNotExecuteBuildTargets;
var LContext: TProjectCompilationContext;
begin
  LContext := FProvider.EvaluateProject(FProject, FRoot, Default(TBuildTarget));
  Assert.Contains<string>(LContext.DeferredProperties, 'DCC_Define');
  Assert.Contains<string>(LContext.Defines, 'IMPORTED');
  Assert.IsFalse(TFile.Exists(TPath.Combine(FRoot, 'built.txt')));
end;

procedure TProjectContextTests.MissingImportFailsExplicitly;
begin
  TFile.Delete(TPath.Combine(FRoot, 'shared.props'));
  Assert.WillRaise(procedure begin
    FProvider.EvaluateProject(FProject, FRoot, Default(TBuildTarget));
  end, EInvalidOperation);
end;

procedure TProjectContextTests.RepeatedEvaluationSeesChangedProperties;
var LContext: TProjectCompilationContext;
begin
  FProvider.EvaluateProject(FProject, FRoot, Default(TBuildTarget));
  WriteText('shared.props', '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><PropertyGroup>' +
    '<DCC_Define>CHANGED</DCC_Define></PropertyGroup></Project>');
  LContext := FProvider.EvaluateProject(FProject, FRoot, Default(TBuildTarget));
  Assert.Contains<string>(LContext.Defines, 'CHANGED');
end;

procedure TProjectContextTests.CheckFailure(const AKind: Integer);
var LRunner: TContextProcessStub;
begin
  LRunner := TContextProcessStub.Create;
  LRunner.Kind := AKind;
  FProvider := TMsBuildProjectContext.Create(LRunner);
  Assert.WillRaise(procedure begin
    FProvider.EvaluateProject(FProject, FRoot, Default(TBuildTarget));
  end);
end;

procedure TProjectContextTests.MalformedResponseFailsExplicitly;
begin CheckFailure(0) end;
procedure TProjectContextTests.TimedOutProcessFailsExplicitly;
begin CheckFailure(1) end;
procedure TProjectContextTests.CancelledProcessFailsExplicitly;
begin CheckFailure(2) end;

procedure TProjectContextTests.InvalidTargetIsRejectedBeforeStartingProcess;
begin
  Assert.WillRaise(procedure begin
    FProvider.EvaluateProject(FProject, FRoot, TBuildTarget.Create('Debug&bad', 'Win32'));
  end, EArgumentException);
end;

procedure TProjectContextTests.MissingEnvironmentFailsExplicitly;
begin
  Assert.WillRaise(procedure begin
    FProvider.EvaluateProject(FProject, TPath.Combine(FRoot, 'missing'), Default(TBuildTarget));
  end, EFileNotFoundException);
end;

initialization
  TDUnitX.RegisterTestFixture(TProjectContextTests);

end.
