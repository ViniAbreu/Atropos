unit Atropos.Tests.EffectGraph;

interface

uses DUnitX.TestFramework, Atropos.Core.Ports, Atropos.Core.Domain;

type
  [TestFixture]
  TEffectGraphTests = class
  private
    FRoot: string;
    FParser: IASTParser;
    function WriteSource(const AName, AText: string): string;
    function CreateContext(ATargetResolver: Boolean = True): TProjectContext;
    function Analyze(AContext: TProjectContext; const AImport: string): TUnitAnalysisResult;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [TestCase('Target', 'True')]
    [TestCase('Legacy', 'False')]
    procedure BothImportSectionsCarryEffects(ATargetResolver: Boolean);
    [Test] procedure CycleReachesEffectFromEitherRoot;
    [Test] procedure PureCycleTerminatesAndAllowsRemoval;
    [Test] procedure MissingTransitiveSourcePreservesUnknown;
    [Test] procedure KnownEffectWinsOverUnknownSibling;
    [Test] procedure AliasAndNamespaceImportsCarryEffects;
    [Test] procedure ResolverWithoutDependencyFactsIsUnknown;
    [Test] procedure IncompleteDependencyMetadataIsUnknown;
    [Test] procedure ManualExportsNeedExplicitImportFacts;
  end;

implementation

uses System.SysUtils, System.IOUtils, Atropos.Core.Effects, Atropos.Core.Analysis,
  Atropos.Core.Compilation, Atropos.Adapters.DelphiAST, Atropos.Adapters.TargetResolver,
  Atropos.Adapters.ExternalUnitResolver, Atropos.Tests.ExternalResolver;

procedure TEffectGraphTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'Atropos-Effects-' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
  FParser := TDelphiASTAdapter.Create;
end;

procedure TEffectGraphTests.TearDown;
begin
  FParser := nil;
  if not TPath.GetFullPath(FRoot).StartsWith(
    TPath.Combine(TPath.GetTempPath, 'Atropos-Effects-'), True) then
    raise Exception.Create('Refusing cleanup outside effect test directory');
  TDirectory.Delete(FRoot, True);
end;

function TEffectGraphTests.WriteSource(const AName, AText: string): string;
begin
  Result := TPath.Combine(FRoot, AName + '.pas');
  TFile.WriteAllText(Result, AText, TEncoding.UTF8);
end;

function TEffectGraphTests.CreateContext(ATargetResolver: Boolean): TProjectContext;
var LResolver: IExternalUnitResolver; LCompilation: TProjectCompilationContext;
begin
  LCompilation := Default(TProjectCompilationContext);
  LCompilation.ProjectPath := TPath.Combine(FRoot, 'Test.dproj');
  LCompilation.SearchPaths := [FRoot];
  LCompilation.Namespaces := ['Scope'];
  LCompilation.Aliases := ['Alias=Scope.Bridge'];
  if ATargetResolver then
    LResolver := TTargetUnitResolver.Create(FParser, LCompilation, '');
  if not Assigned(LResolver) then
  begin
    LResolver := TExternalUnitResolverAdapter.Create(FParser);
    LResolver.Initialize([FRoot], '', FRoot);
  end;
  Result := TProjectContext.Create(LResolver);
end;

function TEffectGraphTests.Analyze(AContext: TProjectContext;
  const AImport: string): TUnitAnalysisResult;
var LAnalyzer: TAnalyzeUnitUses;
begin
  LAnalyzer := TAnalyzeUnitUses.Create;
  try
    Result := LAnalyzer.Execute(FParser.ParseFile(WriteSource('Consumer',
      'unit Consumer; interface uses ' + AImport + '; implementation end.')), AContext);
  finally
    LAnalyzer.Free;
  end;
end;

procedure TEffectGraphTests.BothImportSectionsCarryEffects(ATargetResolver: Boolean);
var LContext: TProjectContext; LResult: TUnitAnalysisResult;
begin
  WriteSource('Leaf', 'unit Leaf; interface implementation initialization end.');
  WriteSource('Bridge', 'unit Bridge; interface uses Leaf; implementation end.');
  WriteSource('Root', 'unit Root; interface implementation uses Bridge; end.');
  LContext := CreateContext(ATargetResolver);
  try
    LResult := Analyze(LContext, 'Root');
    Assert.AreEqual<NativeInt>(0, Length(LResult.UnusedUnits));
    Assert.AreEqual<NativeInt>(0, Length(LResult.UnitsToMoveToImpl));
    Assert.AreEqual(Ord(dsUsed), Ord(LResult.Decisions[0].State));
    Assert.IsTrue(LResult.Decisions[0].Reason.Contains('Root -> Bridge -> Leaf'));
  finally LContext.Free end;
end;

procedure TEffectGraphTests.CycleReachesEffectFromEitherRoot;
var LContext: TProjectContext;
begin
  WriteSource('A', 'unit A; interface implementation uses B; end.');
  WriteSource('B', 'unit B; interface implementation uses A, Leaf; end.');
  WriteSource('Leaf', 'unit Leaf; interface implementation begin end.');
  LContext := CreateContext;
  try
    Assert.AreEqual(Ord(esPresent), Ord(LContext.AssessUnitEffects('A').State));
    Assert.AreEqual(Ord(esPresent), Ord(LContext.AssessUnitEffects('B').State));
  finally LContext.Free end;
end;

procedure TEffectGraphTests.PureCycleTerminatesAndAllowsRemoval;
var LContext: TProjectContext; LResult: TUnitAnalysisResult;
begin
  WriteSource('A', 'unit A; interface implementation uses B; end.');
  WriteSource('B', 'unit B; interface implementation uses A; end.');
  LContext := CreateContext;
  try
    Assert.AreEqual(Ord(esNone), Ord(LContext.AssessUnitEffects('A').State));
    Assert.AreEqual(Ord(esNone), Ord(LContext.AssessUnitEffects('B').State));
    LResult := Analyze(LContext, 'A');
    Assert.Contains<string>(LResult.UnusedUnits, 'A');
  finally LContext.Free end;
end;

procedure TEffectGraphTests.MissingTransitiveSourcePreservesUnknown;
var LContext: TProjectContext; LResult: TUnitAnalysisResult;
begin
  WriteSource('Bridge', 'unit Bridge; interface uses Missing; implementation end.');
  LContext := CreateContext;
  try
    LResult := Analyze(LContext, 'Bridge');
    Assert.AreEqual<NativeInt>(0, Length(LResult.UnusedUnits));
    Assert.AreEqual(Ord(dsUnknown), Ord(LResult.Decisions[0].State));
    Assert.IsTrue(LResult.Decisions[0].Reason.Contains('Bridge -> Missing'));
  finally LContext.Free end;
end;

procedure TEffectGraphTests.KnownEffectWinsOverUnknownSibling;
var LContext: TProjectContext; LAssessment: TEffectAssessment;
begin
  WriteSource('Bridge', 'unit Bridge; interface uses Missing, Leaf; implementation end.');
  WriteSource('Leaf', 'unit Leaf; interface implementation initialization end.');
  LContext := CreateContext;
  try
    LAssessment := LContext.AssessUnitEffects('Bridge');
    Assert.AreEqual(Ord(esPresent), Ord(LAssessment.State));
    Assert.IsTrue(LAssessment.Reason.Contains('Bridge -> Leaf'));
  finally LContext.Free end;
end;

procedure TEffectGraphTests.AliasAndNamespaceImportsCarryEffects;
var LContext: TProjectContext;
begin
  WriteSource('Scope.Bridge', 'unit Scope.Bridge; interface uses Leaf; implementation end.');
  WriteSource('Scope.Leaf', 'unit Scope.Leaf; interface implementation initialization end.');
  LContext := CreateContext;
  try
    Assert.AreEqual(Ord(esPresent), Ord(LContext.AssessUnitEffects('Alias').State));
    Assert.AreEqual(Ord(esPresent), Ord(LContext.AssessUnitEffects('Bridge').State));
  finally LContext.Free end;
end;

procedure TEffectGraphTests.ResolverWithoutDependencyFactsIsUnknown;
var LContext: TProjectContext;
begin
  LContext := TProjectContext.Create(TMockExternalResolver.Create);
  try
    Assert.AreEqual(Ord(esUnknown), Ord(LContext.AssessUnitEffects('SysUtils').State));
  finally LContext.Free end;
end;

procedure TEffectGraphTests.IncompleteDependencyMetadataIsUnknown;
var LContext: TProjectContext;
begin
  TFile.WriteAllText(TPath.Combine(FRoot, 'imports.inc'), 'uses Leaf;', TEncoding.UTF8);
  WriteSource('Bridge', 'unit Bridge; interface {$I imports.inc} implementation end.');
  WriteSource('Leaf', 'unit Leaf; interface implementation end.');
  LContext := CreateContext(False);
  try
    Assert.AreEqual(Ord(esUnknown), Ord(LContext.AssessUnitEffects('Bridge').State));
  finally LContext.Free end;
end;
procedure TEffectGraphTests.ManualExportsNeedExplicitImportFacts;
var LContext: TProjectContext;
begin
  LContext := TProjectContext.Create;
  try
    LContext.RegisterUnitExports('Pure', []);
    Assert.AreEqual(Ord(esUnknown), Ord(LContext.AssessUnitEffects('Pure').State));
    LContext.RegisterUnitDependencies('Pure', []);
    Assert.AreEqual(Ord(esNone), Ord(LContext.AssessUnitEffects('Pure').State));
  finally LContext.Free end;
end;
initialization
  TDUnitX.RegisterTestFixture(TEffectGraphTests);
end.
