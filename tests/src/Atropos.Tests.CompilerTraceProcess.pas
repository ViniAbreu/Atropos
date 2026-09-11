unit Atropos.Tests.CompilerTraceProcess;

interface

uses DUnitX.TestFramework, Atropos.Core.Ports, Atropos.Core.Compilation,
  Atropos.Adapters.BuildService;

type
  TObservingCompilerRunner = class(TInterfacedObject, IBuildProcessRunner)
  public
    Calls, MutateAfter: Integer;
    PathToMutate: string;
    function Execute(const ACommand: string; ATimeoutMs: Cardinal;
      const AShouldCancel: TCancellationCheck; out AOutput: string;
      out AExitCode: Cardinal; out ATimedOut, ACancelled: Boolean): Boolean;
  end;

  TTraceProcessStub = class(TInterfacedObject, IBuildProcessRunner)
  public
    Kind, Calls: Integer;
    DirectoryName, ScriptText: string;
    function Execute(const ACommand: string; ATimeoutMs: Cardinal;
      const AShouldCancel: TCancellationCheck; out AOutput: string;
      out AExitCode: Cardinal; out ATimedOut, ACancelled: Boolean): Boolean;
  end;

  [TestFixture]
  TCompilerTraceProcessTests = class
  private
    FRoot, FSource: string;
    FStub: TTraceProcessStub;
    FRunner: IBuildProcessRunner;
    FContext: TProjectCompilationContext;
    function Compile: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure SuccessRequiresArtifactAndCleansScript;
    [TestCase('NotStarted', '1')]
    [TestCase('ExitCode', '2')]
    [TestCase('Timeout', '3')]
    [TestCase('NoArtifact', '5')]
    procedure ProcessFailuresRejectPreparation(AKind: Integer);
    [Test] procedure ProcessCancellationPropagates;
    [Test] procedure PendingCancellationDoesNotStartProcess;
    [Test] procedure ExistingArtifactDoesNotStartProcess;
    [Test] procedure InvalidTargetDoesNotStartProcess;
    [TestCase('Empty', '0')]
    [TestCase('Header', '1')]
    [TestCase('Relative', '2')]
    [TestCase('Missing', '3')]
    procedure InvalidDependencyListsAreRejected(AKind: Integer);
    [Test] procedure ExistingDependencyListDoesNotStartProcess;
    [Test] procedure GeneratedDependencyTakesPrecedenceOverOldSourceDirectoryCopy;
  end;

  [TestFixture]
  TNativeCompilerTraceTests = class
  private
    FRoot, FSource, FProject, FOutput, FDelphi: string;
    function Context(const AConfig, APlatform: string): TProjectCompilationContext;
    function Compile(const AContext: TProjectCompilationContext): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [TestCase('Debug32', 'Debug,Win32')]
    [TestCase('Debug64', 'Debug,Win64')]
    [TestCase('Release32', 'Release,Win32')]
    [TestCase('Release64', 'Release,Win64')]
    procedure NativeCompilerRespectsTarget(const AConfig, APlatform: string);
    [Test] procedure ChangedProjectIsRejectedBeforeCompilation;
    [Test] procedure ProjectHookIsNotExecuted;
    [Test] procedure CompilerErrorDoesNotSucceed;
    [Test] procedure EnvironmentSettingChangeIsRejected;
    [TestCase('Win32', 'Win32')]
    [TestCase('Win64', 'Win64')]
    procedure NativeDependencyListIncludesTransitiveUnits(const APlatform: string);
    [TestCase('Win32', 'Win32')]
    [TestCase('Win64', 'Win64')]
    procedure NativePreparationReachesParser(const APlatform: string);
    [Test] procedure NativePreparationPreservesRepeatedIncludes;
    [TestCase('Windows32', 'Win32,rtl\win\Winapi.Windows.pas')]
    [TestCase('Windows64', 'Win64,rtl\win\Winapi.Windows.pas')]
    [TestCase('SysUtils32', 'Win32,rtl\sys\System.SysUtils.pas')]
    [TestCase('SysUtils64', 'Win64,rtl\sys\System.SysUtils.pas')]
    procedure NativePreparationParsesRTL(const APlatform, ARelativePath: string);
    [TestCase('RootAfterDiscovery', '1,0')]
    [TestCase('IncludeAfterValidation', '2,1')]
    procedure SourceMutationPreventsPreparation(ACall, AInclude: Integer);
  end;

implementation

uses System.SysUtils, System.IOUtils, System.Classes, System.JSON, System.NetEncoding,
  System.RegularExpressions,
  Winapi.Windows,
  Atropos.Adapters.CompilerTraceProcess, Atropos.Adapters.ProjectContext,
  Atropos.Adapters.CompilerDependencies, Atropos.Adapters.CompilerPreparation,
  Atropos.Adapters.NativeSourcePreparer, Atropos.Adapters.DelphiAST,
  Atropos.Adapters.CompilerSymbols, Atropos.Adapters.DelphiSource;

function TObservingCompilerRunner.Execute(const ACommand: string; ATimeoutMs: Cardinal;
  const AShouldCancel: TCancellationCheck; out AOutput: string;
  out AExitCode: Cardinal; out ATimedOut, ACancelled: Boolean): Boolean;
var LRunner: IBuildProcessRunner;
begin
  LRunner := TWin32BuildProcessRunner.Create;
  Result := LRunner.Execute(ACommand, ATimeoutMs, AShouldCancel, AOutput,
    AExitCode, ATimedOut, ACancelled);
  Inc(Calls);
  if Result and (AExitCode = 0) and (Calls = MutateAfter) and not PathToMutate.IsEmpty then
    TFile.AppendAllText(PathToMutate, sLineBreak);
end;

function TTraceProcessStub.Execute(const ACommand: string; ATimeoutMs: Cardinal;
  const AShouldCancel: TCancellationCheck; out AOutput: string;
  out AExitCode: Cardinal; out ATimedOut, ACancelled: Boolean): Boolean;
var LPaths: TArray<string>;
begin
  Inc(Calls);
  LPaths := TDirectory.GetFiles(DirectoryName, 'AtroposTrace-*.ps1');
  Assert.AreEqual<NativeInt>(1, Length(LPaths));
  ScriptText := TFile.ReadAllText(LPaths[0]);
  AOutput := 'compiler output';
  AExitCode := 0;
  if Kind = 2 then AExitCode := 1;
  ATimedOut := Kind = 3;
  ACancelled := Kind = 4;
  Result := Kind <> 1;
  if Kind = 0 then TFile.WriteAllText(TPath.Combine(DirectoryName, 'Trial.dcu'), 'artifact');
end;

procedure TCompilerTraceProcessTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'Atropos-TraceProcess-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(TPath.Combine(FRoot, 'bin'));
  TFile.WriteAllText(TPath.Combine(FRoot, 'bin\rsvars.bat'), '');
  FSource := TPath.Combine(FRoot, 'Trial.pas');
  TFile.WriteAllText(FSource, 'unit Trial; interface implementation end.');
  FStub := TTraceProcessStub.Create;
  FStub.DirectoryName := FRoot;
  FRunner := FStub;
  FContext := Default(TProjectCompilationContext);
  FContext.ProjectPath := TPath.Combine(FRoot, 'project ''quoted''.dproj');
  FContext.Target := TBuildTarget.Create('Debug', 'Win64');
end;

procedure TCompilerTraceProcessTests.TearDown;
begin
  FRunner := nil;
  TDirectory.Delete(FRoot, True);
end;

function TCompilerTraceProcessTests.Compile: string;
var LProcess: TCompilerTraceProcess;
begin
  LProcess := TCompilerTraceProcess.Create(FRunner, nil);
  try
    Result := LProcess.Compile(FContext, FRoot, FSource, FRoot);
  finally
    LProcess.Free;
  end;
end;

procedure TCompilerTraceProcessTests.SuccessRequiresArtifactAndCleansScript;
var LEncoded: string; LRequest: TJSONObject;
begin
  Assert.AreEqual('compiler output', Compile);
  Assert.AreEqual(1, FStub.Calls);
  Assert.AreEqual<NativeInt>(0, Length(TDirectory.GetFiles(FRoot, '*.ps1')));
  LEncoded := FStub.ScriptText.Split([''''])[1];
  LRequest := TJSONObject.ParseJSONValue(TNetEncoding.Base64.Decode(LEncoded)) as TJSONObject;
  try
    Assert.AreEqual(FContext.ProjectPath, LRequest.GetValue<string>('projectPath'));
    Assert.AreEqual('Win64', LRequest.GetValue<string>('platform'));
    Assert.AreEqual(FRoot, LRequest.GetValue<string>('outputPath'));
  finally
    LRequest.Free;
  end;
end;

procedure TCompilerTraceProcessTests.ProcessFailuresRejectPreparation(AKind: Integer);
begin
  FStub.Kind := AKind;
  Assert.WillRaise(procedure begin Compile end, EInvalidOperation);
  Assert.AreEqual<NativeInt>(0, Length(TDirectory.GetFiles(FRoot, '*.ps1')));
end;

procedure TCompilerTraceProcessTests.ProcessCancellationPropagates;
begin
  FStub.Kind := 4;
  Assert.WillRaise(procedure begin Compile end, EAbort);
  Assert.AreEqual<NativeInt>(0, Length(TDirectory.GetFiles(FRoot, '*.ps1')));
end;

procedure TCompilerTraceProcessTests.PendingCancellationDoesNotStartProcess;
var LProcess: TCompilerTraceProcess;
begin
  LProcess := TCompilerTraceProcess.Create(FRunner, function: Boolean begin Result := True end);
  try
    Assert.WillRaise(procedure begin LProcess.Compile(FContext, FRoot, FSource, FRoot) end, EAbort);
    Assert.AreEqual(0, FStub.Calls);
  finally
    LProcess.Free;
  end;
end;

procedure TCompilerTraceProcessTests.ExistingArtifactDoesNotStartProcess;
begin
  TFile.WriteAllText(TPath.Combine(FRoot, 'Trial.dcu'), 'stale');
  Assert.WillRaise(procedure begin Compile end, EInvalidOperation);
  Assert.AreEqual(0, FStub.Calls);
end;

procedure TCompilerTraceProcessTests.InvalidTargetDoesNotStartProcess;
begin
  FContext.Target := Default(TBuildTarget);
  Assert.WillRaise(procedure begin Compile end, EArgumentException);
  Assert.AreEqual(0, FStub.Calls);
end;

procedure TNativeCompilerTraceTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'Atropos-NativeTrace-' + TGUID.NewGuid.ToString);
  FOutput := TPath.Combine(FRoot, 'isolated');
  TDirectory.CreateDirectory(FOutput);
  FDelphi := GetEnvironmentVariable('ATROPOS_TEST_BDS_PATH');
  if FDelphi.IsEmpty then FDelphi := 'C:\Program Files (x86)\Embarcadero\Studio\23.0';
  FSource := TPath.Combine(FRoot, 'NativeProbe.pas');
  FProject := TPath.Combine(FRoot, 'NativeProbe.dproj');
  TFile.WriteAllText(FSource, 'unit NativeProbe; interface ' +
    '{$IFDEF DEBUG}{$MESSAGE HINT ''TRACE_DEBUG''}{$ENDIF}' + sLineBreak +
    '{$IF SizeOf(Pointer)=8}{$MESSAGE HINT ''TRACE_64''}{$ELSE}{$MESSAGE HINT ''TRACE_32''}{$ENDIF}' +
    sLineBreak + 'implementation end.', TEncoding.UTF8);
  TFile.WriteAllText(FProject, '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '<PropertyGroup><MainSource>NativeProbe.pas</MainSource><AppType>Console</AppType>' +
    '<DCC_DcuOutput>original-output</DCC_DcuOutput><DCC_ExeOutput>original-output</DCC_ExeOutput>' +
    '<DCC_ConsoleTarget>true</DCC_ConsoleTarget></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Config)''==''Debug''"><DCC_Define>DEBUG</DCC_Define></PropertyGroup>' +
    '<Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets"/></Project>', TEncoding.UTF8);
end;

procedure TNativeCompilerTraceTests.TearDown;
begin
  TDirectory.Delete(FRoot, True);
end;

function TNativeCompilerTraceTests.Context(const AConfig, APlatform: string): TProjectCompilationContext;
var LProvider: IProjectContextProvider;
begin
  LProvider := TMsBuildProjectContext.Create;
  Result := LProvider.EvaluateProject(FProject, FDelphi, TBuildTarget.Create(AConfig, APlatform));
end;

function TNativeCompilerTraceTests.Compile(const AContext: TProjectCompilationContext): string;
var LProcess: TCompilerTraceProcess;
begin
  LProcess := TCompilerTraceProcess.Create(nil, nil);
  try
    Result := LProcess.Compile(AContext, FDelphi, FSource, FOutput);
  finally
    LProcess.Free;
  end;
end;

procedure TNativeCompilerTraceTests.NativeCompilerRespectsTarget(const AConfig, APlatform: string);
var LOutput: string;
begin
  LOutput := Compile(Context(AConfig, APlatform));
  Assert.AreEqual(AConfig = 'Debug', LOutput.Contains('TRACE_DEBUG'));
  Assert.AreEqual(APlatform = 'Win64', LOutput.Contains('TRACE_64'));
  Assert.AreEqual(APlatform = 'Win32', LOutput.Contains('TRACE_32'));
  Assert.AreEqual<NativeInt>(Ord(AConfig = 'Debug'), TRegEx.Matches(LOutput, '\bTRACE_DEBUG\b').Count);
  Assert.AreEqual<NativeInt>(Ord(APlatform = 'Win64'), TRegEx.Matches(LOutput, '\bTRACE_64\b').Count);
  Assert.AreEqual<NativeInt>(Ord(APlatform = 'Win32'), TRegEx.Matches(LOutput, '\bTRACE_32\b').Count);
  Assert.IsTrue(TFile.Exists(TPath.Combine(FOutput, 'NativeProbe.dcu')));
  Assert.IsFalse(TDirectory.Exists(TPath.Combine(FRoot, 'original-output')));
  Assert.IsFalse(TFile.Exists(TPath.Combine(FRoot, 'NativeProbe.dcu')));
  Assert.AreEqual<NativeInt>(0, Length(TDirectory.GetFiles(FOutput, '*.ps1')));
end;

procedure TNativeCompilerTraceTests.ChangedProjectIsRejectedBeforeCompilation;
var LContext: TProjectCompilationContext;
begin
  LContext := Context('Debug', 'Win32');
  TFile.AppendAllText(FProject, ' ');
  try
    Compile(LContext);
    Assert.Fail('Changed project was accepted.');
  except
    on E: EInvalidOperation do Assert.Contains(E.Message, 'Project input changed');
  end;
  Assert.IsFalse(TFile.Exists(TPath.Combine(FOutput, 'NativeProbe.dcu')));
end;

procedure TNativeCompilerTraceTests.ProjectHookIsNotExecuted;
var LText: string;
begin
  LText := TFile.ReadAllText(FProject).Replace('</Project>',
    '<Target Name="UnexpectedHook" BeforeTargets="_PasCoreCompile">' +
    '<WriteLinesToFile File="hook-ran.txt" Lines="ran"/></Target></Project>');
  TFile.WriteAllText(FProject, LText, TEncoding.UTF8);
  try
    Compile(Context('Debug', 'Win32'));
    Assert.Fail('Compiler hook was accepted.');
  except
    on E: EInvalidOperation do Assert.Contains(E.Message, 'Compiler target has a project hook');
  end;
  Assert.IsFalse(TFile.Exists(TPath.Combine(FRoot, 'hook-ran.txt')));
end;

procedure TNativeCompilerTraceTests.CompilerErrorDoesNotSucceed;
begin
  TFile.WriteAllText(FSource, 'unit NativeProbe; interface type TBroken=MissingType; implementation end.');
  try
    Compile(Context('Debug', 'Win32'));
    Assert.Fail('Compiler error was accepted.');
  except
    on E: EInvalidOperation do Assert.Contains(E.Message, 'MissingType');
  end;
  Assert.IsFalse(TFile.Exists(TPath.Combine(FOutput, 'NativeProbe.dcu')));
end;

procedure TCompilerTraceProcessTests.InvalidDependencyListsAreRejected(AKind: Integer);
var LText, LPath: string;
begin
  LText := '';
  if AKind = 1 then LText := 'not a dependency list';
  if AKind = 2 then LText := FRoot + '\Trial.exe: Trial.dpr \' + sLineBreak + 'relative.dcu';
  if AKind = 3 then LText := FRoot + '\Trial.exe: Trial.dpr \' + sLineBreak + FRoot + '\missing.dcu';
  LPath := TPath.Combine(FRoot, 'Trial.d');
  TFile.WriteAllText(LPath, LText, TEncoding.UTF8);
  Assert.WillRaise(procedure begin TCompilerDependencies.Read(LPath) end, EInvalidOperation);
end;

procedure TCompilerTraceProcessTests.ExistingDependencyListDoesNotStartProcess;
var LProcess: TCompilerTraceProcess; LProgram: string;
begin
  LProgram := TPath.Combine(FRoot, 'Trial.dpr');
  TFile.WriteAllText(LProgram, 'program Trial; begin end.');
  TFile.WriteAllText(TPath.Combine(FRoot, 'Trial.d'), 'stale');
  LProcess := TCompilerTraceProcess.Create(FRunner, nil);
  try
    Assert.WillRaise(procedure begin
      LProcess.DiscoverDependencies(FContext, FRoot, LProgram, FRoot)
    end, EInvalidOperation);
    Assert.AreEqual(0, FStub.Calls);
  finally
    LProcess.Free;
  end;
end;

procedure TNativeCompilerTraceTests.EnvironmentSettingChangeIsRejected;
var LName, LText: string; LContext: TProjectCompilationContext;
begin
  LName := 'ATROPOS_TRACE_SETTING_' + TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '').Replace('-', '');
  LText := TFile.ReadAllText(FProject).Replace('<DCC_Define>DEBUG</DCC_Define>',
    '<DCC_Define>DEBUG;$(' + LName + ')</DCC_Define>');
  TFile.WriteAllText(FProject, LText, TEncoding.UTF8);
  Winapi.Windows.SetEnvironmentVariable(PChar(LName), 'FIRST');
  try
    LContext := Context('Debug', 'Win32');
    Assert.AreEqual(64, Length(LContext.CompilerContextHash));
    Winapi.Windows.SetEnvironmentVariable(PChar(LName), 'SECOND');
    try
      Compile(LContext);
      Assert.Fail('Changed compiler context was accepted.');
    except
      on E: EInvalidOperation do Assert.Contains(E.Message, 'Compiler context changed since project evaluation');
    end;
    Assert.IsFalse(TFile.Exists(TPath.Combine(FOutput, 'NativeProbe.dcu')));
  finally
    Winapi.Windows.SetEnvironmentVariable(PChar(LName), nil);
  end;
end;

procedure TNativeCompilerTraceTests.NativeDependencyListIncludesTransitiveUnits(const APlatform: string);
var LProcess: TCompilerTraceProcess; LProgram, LDependency: string;
  LDependencies: TArray<string>; LHasSystem, LHasSysUtils: Boolean;
begin
  LProgram := TPath.Combine(FRoot, 'DependencyMain.dpr');
  TFile.WriteAllText(LProgram, 'program DependencyMain; uses System.SysUtils; begin end.', TEncoding.UTF8);
  LProcess := TCompilerTraceProcess.Create(nil, nil);
  try
    LDependencies := LProcess.DiscoverDependencies(Context('Debug', APlatform), FDelphi, LProgram, FOutput);
    LHasSystem := False;
    LHasSysUtils := False;
    for LDependency in LDependencies do
    begin
      Assert.IsTrue(TFile.Exists(LDependency));
      LHasSystem := LHasSystem or SameText(TPath.GetFileName(LDependency), 'System.dcu');
      LHasSysUtils := LHasSysUtils or SameText(TPath.GetFileName(LDependency), 'System.SysUtils.dcu');
    end;
    Assert.IsTrue(LHasSystem);
    Assert.IsTrue(LHasSysUtils);
    Assert.IsFalse(TDirectory.Exists(TPath.Combine(FRoot, 'original-output')));
  finally
    LProcess.Free;
  end;
end;

procedure TCompilerTraceProcessTests.GeneratedDependencyTakesPrecedenceOverOldSourceDirectoryCopy;
var LOld, LNew, LList, LOutput: string; LPaths: TArray<string>;
begin
  LOld := TPath.Combine(FRoot, 'Trial.dcu');
  LOutput := TPath.Combine(FRoot, 'new-output');
  TDirectory.CreateDirectory(LOutput);
  LNew := TPath.Combine(LOutput, 'Trial.dcu');
  TFile.WriteAllText(LOld, 'old');
  TFile.WriteAllText(LNew, 'new');
  LList := TPath.Combine(FRoot, 'Host.d');
  TFile.WriteAllText(LList, FRoot + '\Host.exe: Host.dpr \' + sLineBreak + LOld, TEncoding.UTF8);
  LPaths := TCompilerDependencies.Read(LList, LOutput);
  Assert.AreEqual<NativeInt>(1, Length(LPaths));
  Assert.AreEqual(LNew, LPaths[0]);
end;

procedure TNativeCompilerTraceTests.NativePreparationReachesParser(const APlatform: string);
var LContext: TProjectCompilationContext; LSymbols: TCompilerSymbols;
  LPreparer: ICompilerSourcePreparer; LParser: IASTParser; LTree: IUnitSyntaxTree;
  LSnapshot: IAnalysisSnapshot;
  LConstraints: IUnitImportConstraints;
  LRunner: TObservingCompilerRunner;
begin
  TFile.WriteAllText(FSource, 'unit NativeProbe; interface uses System.SysUtils; type Extended=record Value:Byte; end;' +
    '{$IF SizeOf(Extended)=1}type TSized=Integer;{$ELSE}type Wrong=MissingType;{$ENDIF}' +
    '{$IF Declared(Exception)}type TDeclared=Integer;{$ENDIF} implementation end.', TEncoding.UTF8);
  LContext := Context('Debug', APlatform);
  LRunner := TObservingCompilerRunner.Create;
  LPreparer := TNativeSourcePreparer.Create(LContext, FDelphi, LRunner);
  LSymbols := Default(TCompilerSymbols);
  LSymbols.CompilerVersion := '36.0';
  LParser := TDelphiASTAdapter.Create(LContext, LSymbols, LPreparer);
  Assert.IsTrue(Supports(LParser, IAnalysisSnapshot, LSnapshot));
  LSnapshot.BeginAnalysis;
  LTree := LParser.ParseFile(FSource);
  Assert.Contains<string>(LTree.GetExportedIdentifiers, 'TSized');
  Assert.Contains<string>(LTree.GetExportedIdentifiers, 'TDeclared');
  Assert.IsFalse(string.Join(',', LTree.GetExportedIdentifiers).Contains('Wrong'));
  Assert.IsTrue(Supports(LTree, IUnitImportConstraints, LConstraints));
  Assert.Contains<string>(LConstraints.GetPreservedImportNames, 'System.SysUtils');
  LParser.ParseFile(FSource);
  Assert.AreEqual(2, LRunner.Calls);
  LSnapshot.ValidateAnalysis;
end;

procedure TNativeCompilerTraceTests.NativePreparationPreservesRepeatedIncludes;
var LContext: TProjectCompilationContext; LSymbols: TCompilerSymbols;
  LPreparer: ICompilerSourcePreparer; LParser: IASTParser; LTree: IUnitSyntaxTree;
begin
  TFile.WriteAllText(TPath.Combine(FRoot, 'shared.inc'),
    '{$IFDEF FIRST}type TFirst=Integer;{$ELSE}type TSecond=Integer;{$ENDIF}', TEncoding.UTF8);
  TFile.WriteAllText(FSource, 'unit NativeProbe; interface {$IF Declared(TObject)}' +
    '{$DEFINE FIRST}{$I shared.inc}{$UNDEF FIRST}{$I shared.inc}{$ENDIF} implementation end.', TEncoding.UTF8);
  LContext := Context('Debug', 'Win64');
  LPreparer := TNativeSourcePreparer.Create(LContext, FDelphi);
  LSymbols := Default(TCompilerSymbols);
  LSymbols.CompilerVersion := '36.0';
  LParser := TDelphiASTAdapter.Create(LContext, LSymbols, LPreparer);
  LTree := LParser.ParseFile(FSource);
  Assert.Contains<string>(LTree.GetExportedIdentifiers, 'TFirst');
  Assert.Contains<string>(LTree.GetExportedIdentifiers, 'TSecond');
end;

procedure TNativeCompilerTraceTests.NativePreparationParsesRTL(const APlatform, ARelativePath: string);
var LContext: TProjectCompilationContext; LSymbols: TCompilerSymbols;
  LReader: TCompilerSymbolReader; LPreparer: ICompilerSourcePreparer;
  LParser: IASTParser; LTree: IUnitSyntaxTree; LRunner: TObservingCompilerRunner;
  LSourcePath: string; LSnapshot: IAnalysisSnapshot;
begin
  LSourcePath := TPath.Combine(TPath.Combine(FDelphi, 'source'), ARelativePath);
  LContext := Context('Debug', APlatform);
  LReader := TCompilerSymbolReader.Create(TWin32BuildProcessRunner.Create, nil);
  try
    LSymbols := LReader.Read(LContext, FDelphi);
  finally
    LReader.Free;
  end;
  LRunner := TObservingCompilerRunner.Create;
  LPreparer := TNativeSourcePreparer.Create(LContext, FDelphi, LRunner);
  LParser := TDelphiASTAdapter.Create(LContext, LSymbols, LPreparer);
  Assert.IsTrue(Supports(LParser, IAnalysisSnapshot, LSnapshot));
  LSnapshot.BeginAnalysis;
  LTree := LParser.ParseFile(LSourcePath);
  Assert.AreEqual(2, LRunner.Calls);
  Assert.IsTrue(Length(LTree.GetExportedIdentifiers) > 100);
  LSnapshot.ValidateAnalysis;
end;

procedure TNativeCompilerTraceTests.SourceMutationPreventsPreparation(ACall, AInclude: Integer);
var LContext: TProjectCompilationContext; LPreparer: ICompilerSourcePreparer;
  LRunner: TObservingCompilerRunner; LSource: TDelphiSourceContent; LInclude: string;
begin
  LInclude := TPath.Combine(FRoot, 'shared.inc');
  TFile.WriteAllText(LInclude, 'type Selected=Integer;', TEncoding.UTF8);
  TFile.WriteAllText(FSource, 'unit NativeProbe; interface ' +
    '{$IF Declared(TObject)}{$I shared.inc}{$ENDIF} implementation end.', TEncoding.UTF8);
  LSource := TDelphiSourceReader.ReadRaw(FSource);
  LContext := Context('Debug', 'Win32');
  LRunner := TObservingCompilerRunner.Create;
  LRunner.MutateAfter := ACall;
  LRunner.PathToMutate := FSource;
  if AInclude = 1 then LRunner.PathToMutate := LInclude;
  LPreparer := TNativeSourcePreparer.Create(LContext, FDelphi, LRunner);
  Assert.WillRaise(procedure begin LPreparer.Prepare(FSource, LSource.ContentHash) end, EInvalidOperation);
  Assert.AreEqual(ACall, LRunner.Calls);
end;

initialization
  TDUnitX.RegisterTestFixture(TCompilerTraceProcessTests);
  TDUnitX.RegisterTestFixture(TNativeCompilerTraceTests);

end.
