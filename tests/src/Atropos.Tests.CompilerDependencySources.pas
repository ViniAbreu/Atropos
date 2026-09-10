unit Atropos.Tests.CompilerDependencySources;

interface

uses DUnitX.TestFramework, Atropos.Core.Compilation;

type
  [TestFixture]
  TCompilerDependencySourceTests = class
  private
    FRoot, FSource, FDependency, FInclude, FProject, FDelphi: string;
    function Context(const APlatform: string): TProjectCompilationContext;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [TestCase('Win32', 'Win32')]
    [TestCase('Win64', 'Win64')]
    procedure NativePreparationTracksRecompiledSource(const APlatform: string);
    [TestCase('Source', '0')]
    [TestCase('Include', '1')]
    procedure MutationAfterValidationIsRejected(AInclude: Integer);
    [Test] procedure DependencyIncludeChangeInvalidatesCache;
    [TestCase('Source', '0')]
    [TestCase('Include', '1')]
    [TestCase('Resource', '2')]
    [TestCase('Object', '3')]
    procedure CapturedSourceClosureRejectsMutation(AKind: Integer);
    [Test] procedure MissingResourceCreationInvalidatesSnapshot;
    [Test] procedure RecursiveIncludesAreCapturedOnce;
    [Test] procedure DependencyReaderRetainsReportedPath;
    [Test] procedure ContextIncludesResourceAndObjectPaths;
    [Test] procedure SourceCaptureHonorsCancellation;
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils,
  Atropos.Core.Ports, Atropos.Adapters.ProjectContext,
  Atropos.Adapters.NativeSourcePreparer, Atropos.Adapters.CompilerPreparation,
  Atropos.Adapters.DelphiSource, Atropos.Adapters.SourceSnapshot,
  Atropos.Adapters.SourceIncludes, Atropos.Adapters.CompilerSourceInputs,
  Atropos.Adapters.CompilerDependencies, Atropos.Tests.CompilerTraceProcess;

procedure TCompilerDependencySourceTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'Atropos-DependencySources-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
  FSource := TPath.Combine(FRoot, 'NativeProbe.pas');
  FDependency := TPath.Combine(FRoot, 'Dependency.pas');
  FInclude := TPath.Combine(FRoot, 'shape.inc');
  FProject := TPath.Combine(FRoot, 'NativeProbe.dproj');
  FDelphi := GetEnvironmentVariable('ATROPOS_TEST_BDS_PATH');
  if FDelphi.IsEmpty then FDelphi := 'C:\Program Files (x86)\Embarcadero\Studio\23.0';
  TFile.WriteAllText(FSource, 'unit NativeProbe; interface uses Dependency;' +
    '{$IF SizeOf(TPayload)=1}type SmallSelected=Integer;{$ELSE}type LargeSelected=Integer;{$ENDIF}' +
    ' implementation end.', TEncoding.UTF8);
  TFile.WriteAllText(FDependency, 'unit Dependency; interface {$I shape.inc} implementation end.', TEncoding.UTF8);
  TFile.WriteAllText(FInclude, 'type TPayload=record Value:Byte; end;', TEncoding.UTF8);
  TFile.WriteAllText(FProject, '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '<PropertyGroup><MainSource>NativeProbe.pas</MainSource><AppType>Console</AppType>' +
    '<DCC_ConsoleTarget>true</DCC_ConsoleTarget><DCC_UnitSearchPath>' + FRoot +
    '</DCC_UnitSearchPath></PropertyGroup><Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets"/></Project>', TEncoding.UTF8);
end;

procedure TCompilerDependencySourceTests.TearDown;
begin
  TDirectory.Delete(FRoot, True);
end;

function TCompilerDependencySourceTests.Context(const APlatform: string): TProjectCompilationContext;
var LProvider: IProjectContextProvider;
begin
  LProvider := TMsBuildProjectContext.Create;
  Result := LProvider.EvaluateProject(FProject, FDelphi, TBuildTarget.Create('Debug', APlatform));
end;

procedure TCompilerDependencySourceTests.NativePreparationTracksRecompiledSource(const APlatform: string);
var LPreparer: ICompilerSourcePreparer; LPrepared: TCompilerPreparedSource;
  LRunner: TObservingCompilerRunner; LInput: TSourceDependency; LFoundSource, LFoundInclude: Boolean;
begin
  LRunner := TObservingCompilerRunner.Create;
  LPreparer := TNativeSourcePreparer.Create(Context(APlatform), FDelphi, LRunner);
  LPrepared := LPreparer.Prepare(FSource, TDelphiSourceReader.ReadRaw(FSource).ContentHash);
  Assert.AreEqual(2, LRunner.Calls);
  Assert.Contains(LPrepared.Text, 'SmallSelected');
  Assert.IsFalse(LPrepared.Text.Contains('LargeSelected'));
  LFoundSource := False;
  LFoundInclude := False;
  for LInput in LPrepared.Dependencies do
  begin
    if SameText(LInput.FilePath, FDependency) then LFoundSource := True;
    if SameText(LInput.FilePath, FInclude) then LFoundInclude := True;
    Assert.IsFalse(LInput.FilePath.Contains('Atropos-Prepared-'));
  end;
  Assert.IsTrue(LFoundSource);
  Assert.IsTrue(LFoundInclude);
end;

procedure TCompilerDependencySourceTests.MutationAfterValidationIsRejected(AInclude: Integer);
var LPreparer: ICompilerSourcePreparer; LRunner: TObservingCompilerRunner; LHash: string;
begin
  LRunner := TObservingCompilerRunner.Create;
  LRunner.MutateAfter := 2;
  LRunner.PathToMutate := FDependency;
  if AInclude = 1 then LRunner.PathToMutate := FInclude;
  LPreparer := TNativeSourcePreparer.Create(Context('Win64'), FDelphi, LRunner);
  LHash := TDelphiSourceReader.ReadRaw(FSource).ContentHash;
  Assert.WillRaise(procedure begin LPreparer.Prepare(FSource, LHash) end, EInvalidOperation);
  Assert.AreEqual(2, LRunner.Calls);
end;

procedure TCompilerDependencySourceTests.DependencyIncludeChangeInvalidatesCache;
var LPreparer: ICompilerSourcePreparer; LRunner: TObservingCompilerRunner;
  LPrepared: TCompilerPreparedSource; LHash: string;
begin
  LRunner := TObservingCompilerRunner.Create;
  LPreparer := TNativeSourcePreparer.Create(Context('Win32'), FDelphi, LRunner);
  LHash := TDelphiSourceReader.ReadRaw(FSource).ContentHash;
  LPrepared := LPreparer.Prepare(FSource, LHash);
  Assert.Contains(LPrepared.Text, 'SmallSelected');
  LPreparer.Prepare(FSource, LHash);
  Assert.AreEqual(2, LRunner.Calls);
  TFile.WriteAllText(FInclude, 'type TPayload=record Value:Int64; end;', TEncoding.UTF8);
  LPrepared := LPreparer.Prepare(FSource, LHash);
  Assert.Contains(LPrepared.Text, 'LargeSelected');
  Assert.IsFalse(LPrepared.Text.Contains('SmallSelected'));
  Assert.AreEqual(4, LRunner.Calls);
end;

procedure TCompilerDependencySourceTests.CapturedSourceClosureRejectsMutation(AKind: Integer);
var LSnapshot: TSourceSnapshot; LIncludes: TSourceIncludeResolver; LInputs: TCompilerSourceInputs;
  LContext: TProjectCompilationContext; LChanged: string;
begin
  LContext := Default(TProjectCompilationContext);
  LContext.ProjectPath := FProject;
  TFile.AppendAllText(FInclude, '{$R *.dfm}{$LINK "external object.obj"}');
  TFile.WriteAllText(TPath.Combine(FRoot, 'Dependency.dfm'), 'resource');
  TFile.WriteAllText(TPath.Combine(FRoot, 'external object.obj'), 'object');
  LSnapshot := TSourceSnapshot.Create;
  LIncludes := TSourceIncludeResolver.Create(FDependency, nil, LSnapshot);
  LInputs := TCompilerSourceInputs.Create(LSnapshot, LIncludes, LContext);
  try
    LSnapshot.BeginAnalysis;
    LInputs.Capture(FDependency);
    LSnapshot.ValidateAnalysis;
    LChanged := FDependency;
    if AKind = 1 then LChanged := FInclude;
    if AKind = 2 then LChanged := TPath.Combine(FRoot, 'Dependency.dfm');
    if AKind = 3 then LChanged := TPath.Combine(FRoot, 'external object.obj');
    TFile.AppendAllText(LChanged, ' ');
    Assert.WillRaise(procedure begin LSnapshot.ValidateAnalysis end, EInvalidOperation);
  finally
    LInputs.Free;
    LIncludes.Free;
    LSnapshot.Free;
  end;
end;

procedure TCompilerDependencySourceTests.MissingResourceCreationInvalidatesSnapshot;
var LSnapshot: TSourceSnapshot; LIncludes: TSourceIncludeResolver; LInputs: TCompilerSourceInputs;
  LContext: TProjectCompilationContext;
begin
  LContext := Default(TProjectCompilationContext);
  LContext.ProjectPath := FProject;
  TFile.AppendAllText(FInclude, '(*$RESOURCE ''not present.res''*)');
  LSnapshot := TSourceSnapshot.Create;
  LIncludes := TSourceIncludeResolver.Create(FDependency, nil, LSnapshot);
  LInputs := TCompilerSourceInputs.Create(LSnapshot, LIncludes, LContext);
  try
    LSnapshot.BeginAnalysis;
    LInputs.Capture(FDependency);
    LSnapshot.ValidateAnalysis;
    TFile.WriteAllText(TPath.Combine(FRoot, 'not present.res'), 'new resource');
    Assert.WillRaise(procedure begin LSnapshot.ValidateAnalysis end, EInvalidOperation);
  finally
    LInputs.Free;
    LIncludes.Free;
    LSnapshot.Free;
  end;
end;

procedure TCompilerDependencySourceTests.RecursiveIncludesAreCapturedOnce;
var LSnapshot: TSourceSnapshot; LIncludes: TSourceIncludeResolver; LInputs: TCompilerSourceInputs;
  LContext: TProjectCompilationContext;
begin
  LContext := Default(TProjectCompilationContext);
  LContext.ProjectPath := FProject;
  TFile.AppendAllText(FInclude, '{$IFNDEF SEEN}{$DEFINE SEEN}{$I shape.inc}{$ENDIF}');
  LSnapshot := TSourceSnapshot.Create;
  LIncludes := TSourceIncludeResolver.Create(FDependency, nil, LSnapshot);
  LInputs := TCompilerSourceInputs.Create(LSnapshot, LIncludes, LContext);
  try
    LSnapshot.BeginAnalysis;
    LInputs.Capture(FDependency);
    LSnapshot.ValidateAnalysis;
    Assert.AreEqual<NativeInt>(2, Length(LSnapshot.Dependencies));
  finally
    LInputs.Free;
    LIncludes.Free;
    LSnapshot.Free;
  end;
end;

procedure TCompilerDependencySourceTests.DependencyReaderRetainsReportedPath;
var LOutput, LReported, LList: string; LEntries: TArray<TCompilerDependency>;
begin
  LOutput := TPath.Combine(FRoot, 'output');
  TDirectory.CreateDirectory(LOutput);
  LReported := TPath.Combine(FRoot, 'Dependency.dcu');
  LList := TPath.Combine(FRoot, 'host.d');
  TFile.WriteAllText(TPath.Combine(LOutput, 'Dependency.dcu'), 'fresh binary');
  TFile.WriteAllText(LList, 'host.exe: host.dpr \' + sLineBreak + LReported);
  LEntries := TCompilerDependencies.ReadEntries(LList, LOutput);
  Assert.AreEqual<NativeInt>(1, Length(LEntries));
  Assert.AreEqual(LReported, LEntries[0].ReportedPath);
  Assert.AreEqual(TPath.Combine(LOutput, 'Dependency.dcu'), LEntries[0].FilePath);
end;

procedure TCompilerDependencySourceTests.ContextIncludesResourceAndObjectPaths;
var LProject: string; LContext: TProjectCompilationContext;
begin
  LProject := TFile.ReadAllText(FProject).Replace('</PropertyGroup>',
    '<DCC_ResourcePath>resource folder</DCC_ResourcePath><DCC_ObjPath>object folder</DCC_ObjPath></PropertyGroup>');
  TFile.WriteAllText(FProject, LProject, TEncoding.UTF8);
  LContext := Context('Win64');
  Assert.Contains<string>(LContext.ResourcePaths, TPath.Combine(FRoot, 'resource folder'));
  Assert.Contains<string>(LContext.ObjectPaths, TPath.Combine(FRoot, 'object folder'));
end;

procedure TCompilerDependencySourceTests.SourceCaptureHonorsCancellation;
var LSnapshot: TSourceSnapshot; LIncludes: TSourceIncludeResolver; LInputs: TCompilerSourceInputs;
  LContext: TProjectCompilationContext; LChecks: Integer;
begin
  LContext := Default(TProjectCompilationContext);
  LContext.ProjectPath := FProject;
  LChecks := 0;
  LSnapshot := TSourceSnapshot.Create;
  LIncludes := TSourceIncludeResolver.Create(FDependency, nil, LSnapshot);
  LInputs := TCompilerSourceInputs.Create(LSnapshot, LIncludes, LContext,
    function: Boolean begin Inc(LChecks); Result := LChecks = 2 end);
  try
    LSnapshot.BeginAnalysis;
    Assert.WillRaise(procedure begin LInputs.Capture(FDependency) end, EAbort);
    Assert.AreEqual(2, LChecks);
  finally
    LInputs.Free;
    LIncludes.Free;
    LSnapshot.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCompilerDependencySourceTests);

end.
