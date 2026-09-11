unit Atropos.Tests.CacheLifecycle;
interface
uses DUnitX.TestFramework, Atropos.Core.Ports, Atropos.Core.Compilation;
type
  [TestFixture]
  TCacheLifecycleTests = class
  private
    FRoot, FDelphiPath: string;
    function WriteSource(const AName, AText: string): string;
    function Context(const AConfig, APlatform: string): TProjectCompilationContext;
    procedure AssertExport(const AResolver: IExternalUnitResolver;
      const AUnit, APresent, AAbsent: string);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure NewAnalysisRefreshesAllSharedIncludeConsumers;
    [Test] procedure ReinitializeClearsCachedProviderMetadata;
    [Test] [TestCase('Win32', 'Win32')] [TestCase('Win64', 'Win64')]
    procedure FactoryIsolatesInterleavedConfigurations(const APlatform: string);
  end;
implementation
uses System.SysUtils, System.Classes, System.IOUtils,
  Atropos.Core.Domain, Atropos.Adapters.DelphiAST,
  Atropos.Adapters.TargetResolver, Atropos.Adapters.TargetAnalysisFactory, Atropos.Adapters.BuildService;

procedure TCacheLifecycleTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'Atropos-CacheLifecycle-' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
  FDelphiPath := GetEnvironmentVariable('ATROPOS_TEST_BDS_PATH');
  if FDelphiPath.IsEmpty then
    FDelphiPath := 'C:\Program Files (x86)\Embarcadero\Studio\23.0';
end;

procedure TCacheLifecycleTests.TearDown;
begin
  if not TPath.GetFullPath(FRoot).StartsWith(
    TPath.Combine(TPath.GetTempPath, 'Atropos-CacheLifecycle-'), True) then
    raise Exception.Create('Refusing cleanup outside cache test directory');
  TDirectory.Delete(FRoot, True);
end;

function TCacheLifecycleTests.WriteSource(const AName, AText: string): string;
begin
  Result := TPath.Combine(FRoot, AName);
  TFile.WriteAllText(Result, AText, TEncoding.UTF8);
end;

function TCacheLifecycleTests.Context(const AConfig, APlatform: string): TProjectCompilationContext;
begin
  Result := Default(TProjectCompilationContext);
  Result.ProjectPath := TPath.Combine(FRoot, 'Test.dproj');
  Result.Target := TBuildTarget.Create(AConfig, APlatform);
  Result.SearchPaths := [FRoot];
  Result.IncludePaths := [FRoot];
  Result.ApplicationType := 'Console';
  Result.CompilerPath := TPath.Combine(FDelphiPath, 'bin\dcc32.exe');
  if APlatform = 'Win64' then
    Result.CompilerPath := TPath.Combine(FDelphiPath, 'bin\dcc64.exe');
  if AConfig = 'Debug' then
    Result.Defines := ['DEBUG'];
end;

procedure TCacheLifecycleTests.AssertExport(const AResolver: IExternalUnitResolver;
  const AUnit, APresent, AAbsent: string);
var
  LDomain: TProjectContext;
  LMetadata: IUnitExportFactResolver;
  LFacts: TArray<TExportedSymbol>;
begin
  LDomain := TProjectContext.Create(AResolver);
  try
    Assert.IsTrue(LDomain.HasUnit(AUnit), AUnit + ': ' + string.Join('; ', AResolver.GetWarnings));
    Assert.IsTrue(LDomain.UnitExportsIdentifier(AUnit, APresent, []), APresent);
    Assert.IsFalse(LDomain.UnitExportsIdentifier(AUnit, AAbsent, []), AAbsent);
    Assert.IsTrue(Supports(AResolver, IUnitExportFactResolver, LMetadata));
    Assert.IsTrue(LMetadata.TryGetExportFacts(AUnit, LFacts));
    Assert.AreEqual<NativeInt>(1, Length(LFacts));
    Assert.AreEqual(APresent, LFacts[0].Name);
  finally
    LDomain.Free;
  end;
end;

procedure TCacheLifecycleTests.NewAnalysisRefreshesAllSharedIncludeConsumers;
var
  LParser: IASTParser;
  LSnapshot: IAnalysisSnapshot;
  LResolver: IExternalUnitResolver;
  LName: string;
begin
  WriteSource('shared.inc', 'type TBefore = Integer;');
  for LName in ['First', 'Second'] do
    WriteSource(LName + '.pas', 'unit ' + LName + '; interface {$I shared.inc} implementation end.');
  LParser := TDelphiASTAdapter.Create;
  Assert.IsTrue(Supports(LParser, IAnalysisSnapshot, LSnapshot));
  LSnapshot.BeginAnalysis;
  LResolver := TTargetUnitResolver.Create(LParser, Context('Debug', 'Win32'), '');
  for LName in ['First', 'Second'] do
    AssertExport(LResolver, LName, 'TBefore', 'TAfter');
  LSnapshot.ValidateAnalysis;
  WriteSource('shared.inc', 'type TAfter = Integer;');
  Assert.WillRaise(procedure begin LSnapshot.ValidateAnalysis end, EInvalidOperation);
  LSnapshot.BeginAnalysis;
  LResolver.Initialize([FRoot], '', FRoot);
  for LName in ['Second', 'First'] do
    AssertExport(LResolver, LName, 'TAfter', 'TBefore');
  LSnapshot.ValidateAnalysis;
end;

procedure TCacheLifecycleTests.ReinitializeClearsCachedProviderMetadata;
var
  LParser: IASTParser;
  LResolver: IExternalUnitResolver;
  LSnapshot: IAnalysisSnapshot;
  LMetadata: IUnitExportFactResolver;
  LDependencies: IUnitDependencyResolver;
  LFacts: TArray<TExportedSymbol>;
  LImports, LExports: TArray<string>;
  LHasInit, LNative: Boolean;
begin
  WriteSource('Provider.pas', 'unit Provider; interface uses OldDependency; ' +
    'type TBefore = Integer; implementation initialization end.');
  LParser := TDelphiASTAdapter.Create;
  Assert.IsTrue(Supports(LParser, IAnalysisSnapshot, LSnapshot));
  LSnapshot.BeginAnalysis;
  LResolver := TTargetUnitResolver.Create(LParser, Context('Debug', 'Win32'), '');
  AssertExport(LResolver, 'Provider', 'TBefore', 'TAfter');
  Assert.IsTrue(LResolver.TryResolveUnit('Provider', LExports, LHasInit, LNative));
  Assert.IsTrue(LHasInit);
  Assert.IsTrue(Supports(LResolver, IUnitDependencyResolver, LDependencies));
  Assert.IsTrue(LDependencies.TryGetUnitImports('Provider', LImports));
  Assert.AreEqual('OldDependency', string.Join(',', LImports));
  WriteSource('Provider.pas', 'unit Provider; interface uses NewDependency; ' +
    'type TAfter = Integer; implementation end.');
  Assert.WillRaise(procedure begin LSnapshot.ValidateAnalysis end, EInvalidOperation);
  LSnapshot.BeginAnalysis;
  LResolver.Initialize([FRoot], '', FRoot);
  Assert.IsTrue(Supports(LResolver, IUnitExportFactResolver, LMetadata));
  Assert.IsFalse(LMetadata.TryGetExportFacts('Provider', LFacts));
  Assert.IsFalse(LDependencies.TryGetUnitImports('Provider', LImports));
  AssertExport(LResolver, 'Provider', 'TAfter', 'TBefore');
  Assert.IsTrue(LResolver.TryResolveUnit('Provider', LExports, LHasInit, LNative));
  Assert.IsFalse(LHasInit);
  Assert.IsTrue(LDependencies.TryGetUnitImports('Provider', LImports));
  Assert.AreEqual('NewDependency', string.Join(',', LImports));
  LSnapshot.ValidateAnalysis;
end;

procedure TCacheLifecycleTests.FactoryIsolatesInterleavedConfigurations(const APlatform: string);
var
  LFactory: ITargetAnalysisFactory;
  LDebug, LRelease: TTargetAnalysisServices;
  LSnapshot: IAnalysisSnapshot;
begin
  WriteSource('conditional.inc', '{$IFDEF DEBUG}type TDebug = Integer;{$ELSE}' +
    'type TRelease = Integer;{$ENDIF}');
  WriteSource('Provider.pas', 'unit Provider; interface {$I conditional.inc} implementation end.');
  LFactory := TTargetAnalysisFactory.Create(TWin32BuildProcessRunner.Create, nil);
  LDebug := LFactory.CreateForTarget(Context('Debug', APlatform), FDelphiPath);
  LRelease := LFactory.CreateForTarget(Context('Release', APlatform), FDelphiPath);
  AssertExport(LDebug.Resolver, 'Provider', 'TDebug', 'TRelease');
  AssertExport(LRelease.Resolver, 'Provider', 'TRelease', 'TDebug');
  AssertExport(LDebug.Resolver, 'Provider', 'TDebug', 'TRelease');
  AssertExport(LRelease.Resolver, 'Provider', 'TRelease', 'TDebug');
  Assert.IsTrue(Supports(LDebug.Parser, IAnalysisSnapshot, LSnapshot));
  LSnapshot.ValidateAnalysis;
  Assert.IsTrue(Supports(LRelease.Parser, IAnalysisSnapshot, LSnapshot));
  LSnapshot.ValidateAnalysis;
end;

initialization
  TDUnitX.RegisterTestFixture(TCacheLifecycleTests);
end.
