unit Atropos.Tests.TargetAnalysis;

interface

uses DUnitX.TestFramework, Atropos.Core.Ports, Atropos.Core.Compilation;

type
  [TestFixture]
  TTargetAnalysisTests = class
  private
    FRoot, FDelphiPath: string;
    function WriteSource(const AName, AText: string): string;
    function Context(const APlatform: string): TProjectCompilationContext;
    function Parser(const ADefines: TArray<string>): IASTParser;
    procedure CheckIncomplete(const ASource: string);
    procedure CheckConditionalImport(const ASource: string);
    procedure RunMatrix(const ADryRun: Boolean; const AMutateProperties: Boolean = False);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ExplicitSymbolsDoNotInheritHostPlatform;
    [Test] procedure DefinesReachIncludes;
    [Test] procedure ConditionalReferencesAfterUsesRemainAnalyzable;
    [Test] procedure ConditionalUsesArePreserved;
    [Test] procedure EntireConditionalUsesArePreserved;
    [Test] procedure InactiveImportsAlsoConstrainEditing;
    [Test] procedure IfOptIsExplicitlyIncomplete;
    [Test] procedure IfAndElseIfAreExplicitlyIncomplete;
    [Test] procedure AliasesAndNamespacesResolveTargetSources;
    [Test] procedure IncompleteProviderIsNotAccepted;
    [Test] [TestCase('Compiler32', 'Win32')]
    [TestCase('Compiler64', 'Win64')]
    procedure CompilerSymbolsComeFromSelectedCompiler(const APlatform: string);
    [Test] procedure ExplicitGuiOptionDoesNotLeakConsoleSymbol;
    [Test] procedure TargetDisagreementPreservesImport;
    [Test] procedure CommonActionsSurviveIntersection;
    [Test] procedure UnknownTargetVetoesEdits;
    [Test] procedure ApplicationCombinesFourEvaluatedTargets;
    [Test] procedure DryRunUsesFourEvaluatedTargetsWithoutWrites;
    [Test] procedure ProjectMetadataMutationPreventsApplication;
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils,
  Atropos.Core.Domain, Atropos.Core.Analysis, Atropos.Core.AnalysisIntersection,
  Atropos.Core.Config, Atropos.Adapters.DelphiAST, Atropos.Adapters.TargetResolver,
  Atropos.Adapters.CompilerSymbols, Atropos.Adapters.BuildService,
  Atropos.Adapters.ProjectContext, Atropos.Adapters.TargetAnalysisFactory,
  Atropos.Adapters.FileSystem, Atropos.Application.AppService,
  Atropos.Tests.BuildReliability;

procedure TTargetAnalysisTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'Atropos-Targets-' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
  FDelphiPath := GetEnvironmentVariable('ATROPOS_TEST_BDS_PATH');
  if FDelphiPath.IsEmpty then
    FDelphiPath := 'C:\Program Files (x86)\Embarcadero\Studio\23.0';
end;

procedure TTargetAnalysisTests.TearDown;
begin
  if not TPath.GetFullPath(FRoot).StartsWith(
    TPath.Combine(TPath.GetTempPath, 'Atropos-Targets-'), True) then
    raise Exception.Create('Refusing cleanup outside target test directory');
  TDirectory.Delete(FRoot, True);
end;

function TTargetAnalysisTests.WriteSource(const AName, AText: string): string;
begin
  Result := TPath.Combine(FRoot, AName);
  TFile.WriteAllText(Result, AText, TEncoding.UTF8);
end;

function TTargetAnalysisTests.Context(const APlatform: string): TProjectCompilationContext;
var LCompiler: string;
begin
  Result := Default(TProjectCompilationContext);
  Result.ProjectPath := TPath.Combine(FRoot, 'Test.dproj');
  Result.Target := TBuildTarget.Create('Debug', APlatform);
  Result.ApplicationType := 'Console';
  LCompiler := 'dcc32.exe';
  if APlatform = 'Win64' then
    LCompiler := 'dcc64.exe';
  Result.CompilerPath := TPath.Combine(FDelphiPath, 'bin\' + LCompiler);
  Result.SearchPaths := [FRoot];
  Result.IncludePaths := [FRoot];
end;

function TTargetAnalysisTests.Parser(const ADefines: TArray<string>): IASTParser;
var LSymbols: TCompilerSymbols;
begin
  LSymbols.Defines := ADefines;
  LSymbols.CompilerVersion := '36.0';
  Result := TDelphiASTAdapter.Create(Context('Win64'), LSymbols);
end;

procedure TTargetAnalysisTests.ExplicitSymbolsDoNotInheritHostPlatform;
var LParser: IASTParser; LTree: IUnitSyntaxTree;
begin
  LParser := Parser(['WIN64']);
  LTree := LParser.ParseFile(WriteSource('Consumer.pas',
    'unit Consumer; interface {$IFDEF WIN32}type THostLeak = Integer;{$ENDIF}' +
    '{$IFDEF WIN64}type TTarget = Integer;{$ENDIF} implementation end.'));
  Assert.AreEqual<NativeInt>(1, Length(LTree.GetExportedIdentifiers));
  Assert.AreEqual('TTarget', LTree.GetExportedIdentifiers[0]);
end;

procedure TTargetAnalysisTests.DefinesReachIncludes;
var LParser: IASTParser; LTree: IUnitSyntaxTree;
begin
  WriteSource('selected.inc', '{$IFDEF SELECTED}type TSelected = Integer;{$ENDIF}');
  LParser := Parser(['SELECTED']);
  LTree := LParser.ParseFile(WriteSource('Consumer.pas',
    'unit Consumer; interface {$I selected.inc} implementation end.'));
  Assert.Contains<string>(LTree.GetExportedIdentifiers, 'TSelected');
end;

procedure TTargetAnalysisTests.ConditionalReferencesAfterUsesRemainAnalyzable;
var LParser: IASTParser; LTree: IUnitSyntaxTree; LDiagnostics: IUnitAnalysisDiagnostics;
begin
  LParser := Parser(['SELECTED']);
  LTree := LParser.ParseFile(WriteSource('Consumer.pas',
    'unit Consumer; interface uses Provider; {$IFDEF SELECTED}type TUsed = TToken;{$ENDIF} implementation end.'));
  Assert.IsTrue(Supports(LTree, IUnitAnalysisDiagnostics, LDiagnostics));
  Assert.AreEqual<NativeInt>(0, Length(LDiagnostics.GetIncompleteAnalysisReasons));
end;

procedure TTargetAnalysisTests.CheckIncomplete(const ASource: string);
var LParser: IASTParser; LTree: IUnitSyntaxTree; LDiagnostics: IUnitAnalysisDiagnostics;
begin
  LParser := Parser(['SELECTED']);
  LTree := LParser.ParseFile(WriteSource('Consumer.pas', ASource));
  Assert.IsTrue(Supports(LTree, IUnitAnalysisDiagnostics, LDiagnostics));
  Assert.IsTrue(Length(LDiagnostics.GetIncompleteAnalysisReasons) > 0);
end;

procedure TTargetAnalysisTests.ConditionalUsesArePreserved;
begin
  CheckConditionalImport('unit Consumer; interface uses {$IFDEF SELECTED}Provider,{$ENDIF} Other; implementation end.');
end;

procedure TTargetAnalysisTests.EntireConditionalUsesArePreserved;
begin
  CheckConditionalImport('unit Consumer; interface {$IFDEF SELECTED}uses Provider;{$ENDIF} implementation end.');
end;

procedure TTargetAnalysisTests.CheckConditionalImport(const ASource: string);
var
  LParser: IASTParser;
  LTree: IUnitSyntaxTree;
  LConstraints: IUnitImportConstraints;
  LNames: TArray<string>;
begin
  LParser := Parser(['SELECTED']);
  LTree := LParser.ParseFile(WriteSource('Consumer.pas', ASource));
  Assert.IsTrue(Supports(LTree, IUnitImportConstraints, LConstraints));
  LNames := LConstraints.GetPreservedImportNames;
  Assert.AreEqual<NativeInt>(1, Length(LNames));
  Assert.AreEqual('Provider', LNames[0]);
end;

procedure TTargetAnalysisTests.InactiveImportsAlsoConstrainEditing;
begin
  CheckConditionalImport('unit Consumer; interface uses {$IFDEF NEVER_SELECTED}Provider,{$ENDIF} Other;' +
    ' implementation uses Provider; end.');
end;

procedure TTargetAnalysisTests.IfOptIsExplicitlyIncomplete;
begin
  CheckIncomplete('unit Consumer; interface {$IFOPT R+}type TChecked = Integer;{$ENDIF} implementation end.');
end;

procedure TTargetAnalysisTests.IfAndElseIfAreExplicitlyIncomplete;
begin
  CheckIncomplete('unit Consumer; interface {$IF Defined(ABSENT)}type TOne = Integer;' +
    '{$ELSEIF Defined(SELECTED)}type TTwo = Integer;{$IFEND} implementation end.');
end;

procedure TTargetAnalysisTests.AliasesAndNamespacesResolveTargetSources;
var LContext: TProjectCompilationContext; LResolver: IExternalUnitResolver;
  LExports: TArray<string>; LInit, LNative: Boolean;
begin
  LContext := Context('Win64');
  LContext.UnitPaths := [WriteSource('Scope.Provider.pas',
    'unit Scope.Provider; interface type TToken = Integer; implementation end.')];
  LContext.Namespaces := ['Scope'];
  LContext.Aliases := ['Legacy=Provider'];
  LResolver := TTargetUnitResolver.Create(Parser([]), LContext, '');
  Assert.IsTrue(LResolver.TryResolveUnit('Legacy', LExports, LInit, LNative));
  Assert.Contains<string>(LExports, 'TToken');
end;

procedure TTargetAnalysisTests.IncompleteProviderIsNotAccepted;
var LContext: TProjectCompilationContext; LResolver: IExternalUnitResolver;
  LExports: TArray<string>; LInit, LNative: Boolean;
begin
  LContext := Context('Win64');
  LContext.UnitPaths := [WriteSource('Provider.pas',
    'unit Provider; interface {$IFOPT R+}type TToken = Integer;{$ENDIF} implementation end.')];
  LResolver := TTargetUnitResolver.Create(Parser([]), LContext, '');
  Assert.IsFalse(LResolver.TryResolveUnit('Provider', LExports, LInit, LNative));
  Assert.IsTrue(Length(LResolver.GetWarnings) > 0);
end;

procedure TTargetAnalysisTests.CompilerSymbolsComeFromSelectedCompiler(const APlatform: string);
var LReader: TCompilerSymbolReader; LSymbols: TCompilerSymbols;
begin
  LReader := TCompilerSymbolReader.Create(TWin32BuildProcessRunner.Create, nil);
  try
    LSymbols := LReader.Read(Context(APlatform), FDelphiPath);
    Assert.Contains<string>(LSymbols.Defines, APlatform.ToUpper);
    Assert.Contains<string>(LSymbols.Defines, 'CONSOLE');
    Assert.Contains<string>(LSymbols.Defines, 'VER' + LSymbols.CompilerVersion.Replace('.', ''));
  finally
    LReader.Free;
  end;
end;

procedure TTargetAnalysisTests.ExplicitGuiOptionDoesNotLeakConsoleSymbol;
var
  LReader: TCompilerSymbolReader;
  LContext: TProjectCompilationContext;
  LSymbols: TCompilerSymbols;
  LName: string;
begin
  LContext := Context('Win32');
  SetLength(LContext.Options, 1);
  LContext.Options[0].Name := 'ConsoleTarget';
  LContext.Options[0].Value := 'false';
  LReader := TCompilerSymbolReader.Create(TWin32BuildProcessRunner.Create, nil);
  try
    LSymbols := LReader.Read(LContext, FDelphiPath);
    for LName in LSymbols.Defines do
      Assert.AreNotEqual('CONSOLE', LName);
  finally LReader.Free end;
end;

procedure TTargetAnalysisTests.TargetDisagreementPreservesImport;
var LMerge: TAnalysisIntersection; LA, LB, LCombined: TUnitAnalysisResult;
begin
  LA := Default(TUnitAnalysisResult);
  LB := Default(TUnitAnalysisResult);
  LA.UnusedUnits := ['Provider'];
  LA.Decisions := [TDependencyDecision.Create('Provider', usInterface, dsUnused, daRemove, 'unused')];
  LB.Decisions := [TDependencyDecision.Create('Provider', usInterface, dsUsed, daPreserve, 'used')];
  LMerge := TAnalysisIntersection.Create;
  try
    LMerge.Include('Release|Win32', LA);
    LMerge.Include('Debug|Win32', LB);
    LCombined := LMerge.Combined;
    Assert.AreEqual<NativeInt>(0, Length(LCombined.UnusedUnits));
    Assert.AreEqual(Ord(daPreserve), Ord(LCombined.Decisions[0].Action));
    Assert.IsTrue(LCombined.PreservationReasons[0].Contains('Release|Win32'));
  finally LMerge.Free end;
end;

procedure TTargetAnalysisTests.CommonActionsSurviveIntersection;
var LMerge: TAnalysisIntersection; LA, LB, LCombined: TUnitAnalysisResult;
begin
  LA := Default(TUnitAnalysisResult);
  LB := Default(TUnitAnalysisResult);
  LA.UnusedUnits := ['Common', 'OnlyA'];
  LB.UnusedUnits := ['common'];
  LA.UnitsToMoveToImpl := ['SharedMove'];
  LB.UnitsToMoveToImpl := ['SharedMove'];
  LMerge := TAnalysisIntersection.Create;
  try
    LMerge.Include('A', LA);
    LMerge.Include('B', LB);
    LCombined := LMerge.Combined;
    Assert.AreEqual<NativeInt>(1, Length(LCombined.UnusedUnits));
    Assert.AreEqual('Common', LCombined.UnusedUnits[0]);
    Assert.AreEqual('SharedMove', LCombined.UnitsToMoveToImpl[0]);
  finally LMerge.Free end;
end;

procedure TTargetAnalysisTests.UnknownTargetVetoesEdits;
var LMerge: TAnalysisIntersection; LA, LCombined: TUnitAnalysisResult;
begin
  LA := Default(TUnitAnalysisResult);
  LA.UnusedUnits := ['Provider'];
  LMerge := TAnalysisIntersection.Create;
  try
    LMerge.Include('A', LA);
    LMerge.Include('Unknown', Default(TUnitAnalysisResult));
    LCombined := LMerge.Combined;
    Assert.AreEqual<NativeInt>(0, Length(LCombined.UnusedUnits));
  finally LMerge.Free end;
end;

procedure TTargetAnalysisTests.RunMatrix(const ADryRun, AMutateProperties: Boolean);
var
  LProjectPath, LConsumer, LOriginal, LLog: string;
  LConfig: TToolConfig;
  LService: TProjectCleanerAppService;
  LEnvironment: TDelphiEnvironmentStub;
  LRunner: IBuildProcessRunner;
  LReports: TReportGeneratorStub;
  LBuild: TSuccessfulBuildService;
  LVerification: IASTParser;
  LUses: TArray<string>;
begin
  LOriginal := 'unit Consumer;' + sLineBreak + 'interface' + sLineBreak +
    'uses Provider, Unused;' + sLineBreak +
    '{$IFDEF NEED_PROVIDER}type TUsed = TToken;{$ENDIF} implementation end.';
  LConsumer := WriteSource('Consumer.pas', LOriginal);
  WriteSource('Provider.pas', 'unit Provider; interface type TToken = Integer; implementation end.');
  WriteSource('Unused.pas', 'unit Unused; interface implementation end.');
  WriteSource('Only64.pas', 'unit Only64;' + sLineBreak + 'interface' + sLineBreak +
    'uses Unused;' + sLineBreak + 'implementation' + sLineBreak + 'end.');
  WriteSource('shared.props', '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '<PropertyGroup Condition="''$(Config)'' == ''Debug''"><DCC_Define>NEED_PROVIDER</DCC_Define></PropertyGroup></Project>');
  LProjectPath := WriteSource('Test.dproj', '<Project ToolsVersion="4.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '<PropertyGroup><Config>Debug</Config><Platform>Win32</Platform><AppType>Console</AppType></PropertyGroup>' +
    '<Import Project="shared.props"/><ItemGroup><DCCReference Include="Consumer.pas"/>' +
    '<DCCReference Include="Provider.pas"/><DCCReference Include="Unused.pas"/></ItemGroup>' +
    '<ItemGroup Condition="''$(Platform)'' == ''Win64''"><DCCReference Include="Only64.pas"/></ItemGroup></Project>');
  LConfig := TToolConfig.Default;
  LConfig.RemoveUnused := True;
  LConfig.EnableDebug := True;
  LConfig.DryRun := ADryRun;
  LConfig.AddBuildTarget(TBuildTarget.Create('Debug', 'Win32'));
  LConfig.AddBuildTarget(TBuildTarget.Create('Release', 'Win32'));
  LConfig.AddBuildTarget(TBuildTarget.Create('Debug', 'Win64'));
  LConfig.AddBuildTarget(TBuildTarget.Create('Release', 'Win64'));
  LEnvironment := TDelphiEnvironmentStub.Create;
  LEnvironment.DelphiPath := FDelphiPath;
  LRunner := TWin32BuildProcessRunner.Create;
  LReports := TReportGeneratorStub.Create;
  LBuild := TSuccessfulBuildService.Create;
  LService := TProjectCleanerAppService.Create(TProjectParserSpy.Create,
    Parser([]), TFileSystemAdapter.Create, LReports, LEnvironment,
    TExternalResolverStub.Create, LBuild, LConfig, nil,
    TMsBuildProjectContext.Create(LRunner), TTargetAnalysisFactory.Create(LRunner, nil));
  try
    LService.OnLog := procedure(const AMessage: string)
      begin LLog := LLog + AMessage + sLineBreak end;
    if AMutateProperties then
    begin
      LService.OnLog := procedure(const AMessage: string)
        begin
          if AMessage.Contains('Analyzing target Release|Win64') then
            WriteSource('shared.props', 'changed externally');
        end;
      Assert.WillRaise(procedure begin LService.Execute(LProjectPath) end, EInvalidOperation);
      Assert.AreEqual(LOriginal, TFile.ReadAllText(LConsumer));
      Assert.AreEqual('changed externally', TFile.ReadAllText(TPath.Combine(FRoot, 'shared.props')));
      Assert.IsFalse(TFile.Exists(TPath.Combine(FRoot, '.atropos-transaction.json')));
      Exit;
    end;
    Assert.IsTrue(LService.Execute(LProjectPath), 'Matrix execution failed');
    Assert.IsTrue(LReports.WarningCallCount > 0, 'Expected target disagreement warning');
    Assert.IsTrue(LLog.Contains('DEBUG-MATCH:'), 'Target analysis must forward debug diagnostics');
    if ADryRun then
    begin
      Assert.AreEqual(LOriginal, TFile.ReadAllText(LConsumer));
      Assert.AreEqual(4, LBuild.CallCount);
      Exit;
    end;
    LVerification := Parser(['NEED_PROVIDER']);
    LUses := LVerification.ParseFile(LConsumer).GetInterfaceUses;
    Assert.AreEqual<NativeInt>(1, Length(LUses));
    Assert.AreEqual('Provider', LUses[0]);
    LUses := LVerification.ParseFile(TPath.Combine(FRoot, 'Only64.pas')).GetInterfaceUses;
    Assert.AreEqual<NativeInt>(0, Length(LUses));
    Assert.AreEqual(8, LBuild.CallCount);
  finally LService.Free end;
end;

procedure TTargetAnalysisTests.ApplicationCombinesFourEvaluatedTargets;
begin RunMatrix(False) end;
procedure TTargetAnalysisTests.DryRunUsesFourEvaluatedTargetsWithoutWrites;
begin RunMatrix(True) end;
procedure TTargetAnalysisTests.ProjectMetadataMutationPreventsApplication;
begin RunMatrix(False, True) end;

initialization
  TDUnitX.RegisterTestFixture(TTargetAnalysisTests);

end.
