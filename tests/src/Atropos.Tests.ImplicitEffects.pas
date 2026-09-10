unit Atropos.Tests.ImplicitEffects;

interface

uses DUnitX.TestFramework, Atropos.Core.Ports;

type
  [TestFixture]
  TImplicitEffectTests = class
  private
    FDirectory, FSource: string;
    FParser: IASTParser;
    function Parse(const ABody: string): IUnitSyntaxTree;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [TestCase('GlobalManagedRecord', '0,1')]
    [TestCase('LocalManagedRecord', '1,0')]
    [TestCase('UninstantiatedRecord', '2,0')]
    [TestCase('GlobalString', '3,2')]
    [TestCase('ForeignType', '4,2')]
    [TestCase('ClassConstructor', '5,2')]
    [TestCase('SystemScalar', '6,0')]
    [TestCase('LocalAlias', '7,1')]
    [TestCase('NestedRecord', '8,1')]
    [TestCase('PureRecord', '9,0')]
    [TestCase('OrdinaryInitializeMethod', '10,0')]
    [TestCase('GlobalInterface', '11,2')]
    [TestCase('DynamicArray', '12,2')]
    [TestCase('TypedStringConstant', '13,2')]
    [TestCase('ImportedScalarName', '14,2')]
    [TestCase('OrdinaryConstructor', '15,0')]
    [TestCase('ClassStorage', '16,2')]
    [TestCase('StaticRecordArray', '17,2')]
    procedure StorageClassification(AScenario, AState: Integer);
    [Test] procedure UncertainEffectsPropagateWithoutLosingImports;
    [TestCase('DirectRecord', '0,0')]
    [TestCase('DirectUncertainty', '1,0')]
    [TestCase('FallbackUncertainty', '1,1')]
    procedure ResolverPreservesEffectsThroughAlias(AUncertain, AFallback: Integer);
    [Test] procedure MissingEffectMetadataCannotProveAbsence;
  end;

implementation

uses System.SysUtils, System.IOUtils, Atropos.Adapters.DelphiAST,
  Atropos.Core.Domain, Atropos.Core.Effects, Atropos.Core.Compilation,
  Atropos.Adapters.TargetResolver;

const ManagedRecord = 'type TManaged = record ' +
  'class operator Initialize(out Dest: TManaged); ' +
  'class operator Finalize(var Dest: TManaged); end; ';

procedure TImplicitEffectTests.Setup;
begin
  FDirectory := TPath.Combine(TPath.GetTempPath, 'AtroposImplicit-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FDirectory);
  FSource := TPath.Combine(FDirectory, 'Provider.pas');
  FParser := TDelphiASTAdapter.Create;
end;

procedure TImplicitEffectTests.TearDown;
begin
  FParser := nil;
  TDirectory.Delete(FDirectory, True);
end;

function TImplicitEffectTests.Parse(const ABody: string): IUnitSyntaxTree;
begin
  TFile.WriteAllText(FSource, 'unit Provider; interface ' + ABody + ' end.', TEncoding.UTF8);
  Result := FParser.ParseFile(FSource);
end;

procedure TImplicitEffectTests.StorageClassification(AScenario, AState: Integer);
var LBody: string; LTree: IUnitSyntaxTree; LPort: IUnitImplicitEffects;
  LItems: TArray<TImplicitEffect>; LContext: TProjectContext;
begin
  case AScenario of
    0: LBody := ManagedRecord + 'var State: TManaged; implementation';
    1: LBody := ManagedRecord + 'implementation procedure Run; var State: TManaged; begin end;';
    2: LBody := ManagedRecord + 'implementation';
    3: LBody := 'var State: string; implementation';
    4: LBody := 'var State: TForeign; implementation';
    5: LBody := 'type TAuto = class class constructor Create; end; implementation';
    6: LBody := 'uses Foreign; var State: System.Integer; implementation';
    7: LBody := ManagedRecord + 'type TAlias = TManaged; var State: TAlias; implementation';
    8: LBody := ManagedRecord + 'type TOuter = record Value: TManaged; end; var State: TOuter; implementation';
    9: LBody := 'type TPlain = record Value: Integer; end; var State: TPlain; implementation';
    10: LBody := 'type TPlain = record class procedure Initialize; static; end; var State: TPlain; implementation';
    11: LBody := 'var State: IInterface; implementation';
    12: LBody := 'var State: array of Integer; implementation';
    13: LBody := 'const State: string = ''value''; implementation';
    14: LBody := 'uses Foreign; var State: Integer; implementation';
    15: LBody := 'type TAuto = class constructor Create; end; implementation';
    16: LBody := ManagedRecord + 'type TAuto = class class var State: TManaged; end; implementation';
    17: LBody := ManagedRecord + 'var State: array[0..1] of TManaged; implementation';
  end;
  LTree := Parse(LBody);
  Assert.IsTrue(Supports(LTree, IUnitImplicitEffects, LPort));
  LItems := LPort.GetImplicitEffects;
  Assert.AreEqual(AState = 1, LTree.HasInitializationSection);
  if AState = 0 then
    Assert.AreEqual<NativeInt>(0, Length(LItems));
  if AState <> 0 then
  begin
    Assert.IsTrue(Length(LItems) > 0);
    Assert.AreEqual(AState = 1, LItems[0].Definite);
    Assert.AreEqual(FSource, LItems[0].SourcePath);
    Assert.IsTrue(LItems[0].NormalizedLine > 0);
  end;
  LContext := TProjectContext.Create;
  try
    LContext.RegisterUnitExports('Provider', LTree.GetExportedIdentifiers, LTree.HasInitializationSection);
    LContext.RegisterUnitDependencies('Provider', []);
    LContext.RegisterImplicitEffects('Provider', LItems);
    Assert.AreEqual<Integer>(AState, Ord(LContext.AssessUnitEffects('Provider').State));
  finally
    LContext.Free;
  end;
end;

procedure TImplicitEffectTests.UncertainEffectsPropagateWithoutLosingImports;
var LTree: IUnitSyntaxTree; LPort: IUnitImplicitEffects; LContext: TProjectContext;
  LAssessment: TEffectAssessment;
begin
  LTree := Parse('var State: string; implementation');
  Assert.IsTrue(Supports(LTree, IUnitImplicitEffects, LPort));
  LContext := TProjectContext.Create;
  try
    LContext.RegisterUnitExports('Provider', []);
    LContext.RegisterUnitDependencies('Provider', []);
    LContext.RegisterImplicitEffects('Provider', LPort.GetImplicitEffects);
    LContext.RegisterUnitExports('Bridge', []);
    LContext.RegisterUnitDependencies('Bridge', ['Provider']);
    LAssessment := LContext.AssessUnitEffects('Bridge');
    Assert.AreEqual(Ord(esUnknown), Ord(LAssessment.State));
    Assert.IsTrue(LAssessment.Reason.Contains('Bridge -> Provider'));
    LContext.RegisterUnitExports('Effect', [], True);
    LContext.RegisterUnitDependencies('Effect', []);
    LContext.RegisterUnitDependencies('Provider', ['Effect']);
    Assert.AreEqual(Ord(esPresent), Ord(LContext.AssessUnitEffects('Bridge').State));
  finally
    LContext.Free;
  end;
end;

procedure TImplicitEffectTests.ResolverPreservesEffectsThroughAlias(AUncertain, AFallback: Integer);
var LTree: IUnitSyntaxTree; LConfig: TProjectCompilationContext;
  LResolver: IExternalUnitResolver; LContext: TProjectContext; LAssessment: TEffectAssessment;
  LEffects: IUnitImplicitEffectResolver; LItems: TArray<TImplicitEffect>;
begin
  LTree := Parse(ManagedRecord + 'var State: TManaged; implementation');
  if AUncertain = 1 then
    LTree := Parse('var State: string; implementation');
  LConfig := Default(TProjectCompilationContext);
  LConfig.ProjectPath := TPath.Combine(FDirectory, 'Fixture.dproj');
  LConfig.UnitPaths := [FSource];
  if AFallback = 1 then
    LConfig.UnitPaths := [];
  LConfig.Aliases := ['Alias=Provider'];
  LResolver := TTargetUnitResolver.Create(FParser, LConfig, '');
  LContext := TProjectContext.Create(LResolver);
  try
    LAssessment := LContext.AssessUnitEffects('Alias');
    if AUncertain = 0 then
      Assert.AreEqual(Ord(esPresent), Ord(LAssessment.State));
    if AUncertain = 1 then
    begin
      Assert.AreEqual(Ord(esUnknown), Ord(LAssessment.State));
      Assert.IsTrue(LAssessment.Reason.Contains('State'));
    end;
    Assert.IsTrue(Supports(LResolver, IUnitImplicitEffectResolver, LEffects));
    Assert.IsTrue(LEffects.TryGetImplicitEffects('Alias', LItems));
    Assert.AreEqual<NativeInt>(1, Length(LItems));
    LItems[0].Name := 'changed';
    Assert.IsTrue(LEffects.TryGetImplicitEffects('Alias', LItems));
    Assert.AreEqual('State', LItems[0].Name);
    LResolver.Initialize([], '', FDirectory);
    Assert.IsFalse(LEffects.TryGetImplicitEffects('Alias', LItems));
  finally
    LContext.Free;
  end;
end;

procedure TImplicitEffectTests.MissingEffectMetadataCannotProveAbsence;
var LContext: TProjectContext;
begin
  LContext := TProjectContext.Create;
  try
    LContext.RegisterUnitExports('Provider', []);
    LContext.RegisterUnitDependencies('Provider', []);
    LContext.RegisterImplicitEffects('Provider', [], False);
    Assert.AreEqual(Ord(esUnknown), Ord(LContext.AssessUnitEffects('Provider').State));
  finally
    LContext.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TImplicitEffectTests);
end.
