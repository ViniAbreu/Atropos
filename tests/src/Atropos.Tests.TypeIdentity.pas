unit Atropos.Tests.TypeIdentity;

interface

uses DUnitX.TestFramework, Atropos.Core.Ports, Atropos.Core.Domain;

type
  [TestFixture]
  TTypeIdentityTests = class
  private
    FDirectory: string;
    FParser: IASTParser;
    function Parse(const AName, ABody: string): IUnitSyntaxTree;
    function Analyze(const AProvider, AConsumer: string): TUnitAnalysisResult;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [TestCase('PlainDoesNotSupplyGeneric', '0,0')]
    [TestCase('OneDoesNotSupplyTwo', '1,0')]
    [TestCase('TwoParameters', '2,1')]
    [TestCase('LocalGenericShadows', '3,0')]
    [TestCase('LocalPlainDoesNotShadowGeneric', '4,1')]
    [TestCase('InferredRoutineArguments', '5,2')]
    [TestCase('ExplicitRoutineArguments', '6,2')]
    [TestCase('WrongExplicitRoutineArity', '7,0')]
    [TestCase('QualifiedGeneric', '8,1')]
    [TestCase('QualifiedGenericRoutine', '9,2')]
    [TestCase('AbbreviatedAttribute', '10,3')]
    [TestCase('QualifiedAttribute', '11,3')]
    [TestCase('OrdinaryNameHasNoAttributeSuffix', '12,0')]
    [TestCase('ScopedEnumMember', '13,1')]
    [TestCase('ScopedMemberIsNotGlobal', '14,0')]
    [TestCase('LocalUnscopedEnumShadows', '15,0')]
    [TestCase('LocalScopedEnumDoesNotShadow', '16,2')]
    procedure DependencyIdentity(AScenario, AAction: Integer);
    [Test] procedure ExportIndexMatchesLinearContract;
    [Test] procedure ReplacingExportFactsDropsOldCandidates;
    [Test] procedure ExportIndexKeepsLegacyFallbackSeparate;
    [Test] procedure ExportsRetainKindArityAndEnumVisibility;
    [Test] procedure FactsSurviveResolverAliasesAndReset;
    [Test] procedure QualifiedNamesRespectNestedArguments;
    [Test] procedure AttributeAlternativesPreserveBothCandidates;
    [Test] procedure QualifiedArgumentsAndAttributeNamesSurviveFlattening;
  end;

implementation

uses System.SysUtils, System.IOUtils, Atropos.Adapters.DelphiAST,
  Atropos.Adapters.TargetResolver, Atropos.Adapters.UnitDependencies,
  Atropos.Core.Compilation, Atropos.Core.Analysis, Atropos.Core.TypeNames,
  Atropos.Core.UnitSymbols;

procedure TTypeIdentityTests.Setup;
begin
  FDirectory := TPath.Combine(TPath.GetTempPath, 'AtroposTypes-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FDirectory);
  FParser := TDelphiASTAdapter.Create;
end;

procedure TTypeIdentityTests.TearDown;
begin
  FParser := nil;
  TDirectory.Delete(FDirectory, True);
end;

function TTypeIdentityTests.Parse(const AName, ABody: string): IUnitSyntaxTree;
var LPath: string;
begin
  LPath := TPath.Combine(FDirectory, AName + '.pas');
  TFile.WriteAllText(LPath, 'unit ' + AName + '; interface ' + ABody + ' end.', TEncoding.UTF8);
  Result := FParser.ParseFile(LPath);
end;

function TTypeIdentityTests.Analyze(const AProvider, AConsumer: string): TUnitAnalysisResult;
var LTree: IUnitSyntaxTree; LResolver: IExternalUnitResolver;
  LContext: TProjectContext; LAnalyzer: TAnalyzeUnitUses; LTarget: TProjectCompilationContext;
begin
  Parse('Dependency', AProvider);
  LTree := Parse('Consumer', 'uses Dependency; ' + AConsumer);
  LTarget := Default(TProjectCompilationContext);
  LTarget.ProjectPath := TPath.Combine(FDirectory, 'App.dproj');
  LResolver := TTargetUnitResolver.Create(FParser, LTarget, '');
  LContext := TProjectContext.Create(LResolver);
  LAnalyzer := TAnalyzeUnitUses.Create;
  try
    Result := LAnalyzer.Execute(LTree, LContext);
  finally
    LAnalyzer.Free;
    LContext.Free;
  end;
end;

procedure TTypeIdentityTests.DependencyIdentity(AScenario, AAction: Integer);
const Providers: array[0..16] of string = (
  'type TBag = class end;', 'type TBag<T> = class end;', 'type TBag<A,B> = class end;',
  'type TBag<T> = class end;', 'type TBag<T> = class end;',
  'procedure Run<T>(Value: T);', 'procedure Run<T>(Value: T);', 'procedure Run<T>(Value: T);',
  'type TBag<A,B> = class end;', 'procedure Run<T>(Value: T);',
  'type TMarkerAttribute = class(TCustomAttribute) end;',
  'type TMarkerAttribute = class(TCustomAttribute) end;',
  'type TMarkerAttribute = class(TCustomAttribute) end;',
  '{$SCOPEDENUMS ON} type TColor = (Red, Blue);',
  '{$SCOPEDENUMS ON} type TColor = (Red, Blue);',
  'const Red = 1;', 'const Red = 1;');
const Consumers: array[0..16] of string = (
  'var Value: TBag<Integer>; implementation',
  'var Value: TBag<Integer,string>; implementation',
  'var Value: TBag<Integer,string>; implementation',
  'type TBag<T> = class end; var Value: TBag<Integer>; implementation',
  'type TBag = class end; var Value: TBag<Integer>; implementation',
  'implementation procedure Use; begin Run(1); end;',
  'implementation procedure Use; begin Run<Integer>(1); end;',
  'implementation procedure Use; begin Run<Integer,string>(1); end;',
  'var Value: Dependency.TBag<System.Integer,string>; implementation',
  'implementation procedure Use; begin Dependency.Run<Integer>(1); end;',
  'type [TMarker] TLocal = class end; implementation',
  'type [Dependency.TMarker] TLocal = class end; implementation',
  'type TLocal = TMarker; implementation',
  'const Value = TColor.Red; implementation',
  'const Value = Red; implementation',
  'type TLocal = (Red, Blue); implementation procedure Use; begin Ord(Red); end;',
  '{$SCOPEDENUMS ON} type TLocal = (Red, Blue); implementation procedure Use; begin Ord(Red); end;');
var LResult: TUnitAnalysisResult;
begin
  LResult := Analyze(Providers[AScenario] + ' implementation', Consumers[AScenario]);
  Assert.AreEqual<NativeInt>(1, Length(LResult.Decisions));
  case AAction of
    0: Assert.AreEqual(Ord(daRemove), Ord(LResult.Decisions[0].Action));
    1: Assert.AreEqual(Ord(daPreserve), Ord(LResult.Decisions[0].Action));
    2: Assert.AreEqual(Ord(daMoveToImplementation), Ord(LResult.Decisions[0].Action));
    3: begin
      Assert.AreEqual(Ord(daPreserve), Ord(LResult.Decisions[0].Action));
      Assert.AreEqual(Ord(dsUnknown), Ord(LResult.Decisions[0].State));
    end;
  end;
end;

procedure TTypeIdentityTests.ExportsRetainKindArityAndEnumVisibility;
var LTree: IUnitSyntaxTree; LPort: IUnitExportFacts; LFacts: TArray<TExportedSymbol>;
  LNames: TArray<string>; LName: string;
begin
  LTree := Parse('Provider', 'type TBag<A,B> = class end; ' +
    '{$SCOPEDENUMS ON} type TColor = (Red = 2, Blue = 5); var Flag: (Yes, No); ' +
    '{$SCOPEDENUMS OFF} type TPlain = (Green = 7, Black = 9); ' +
    'const Value = 1; resourcestring Text = ''text''; procedure Run<T>(Value: T); implementation');
  Assert.IsTrue(Supports(LTree, IUnitExportFacts, LPort));
  LFacts := LPort.GetExportFacts;
  Assert.AreEqual('TBag', LFacts[0].Name);
  Assert.AreEqual(2, LFacts[0].GenericArity);
  Assert.AreEqual(Ord(ekType), Ord(LFacts[0].Kind));
  Assert.AreEqual('Run', LFacts[High(LFacts)].Name);
  Assert.AreEqual(Ord(ekRoutine), Ord(LFacts[High(LFacts)].Kind));
  Assert.AreEqual(1, LFacts[High(LFacts)].GenericArity);
  LFacts[0].Name := 'changed';
  Assert.AreEqual('TBag', LPort.GetExportFacts[0].Name);
  LNames := LTree.GetExportedIdentifiers;
  for LName in LNames do
    Assert.IsFalse(SameText(LName, 'Red'));
  Assert.Contains<string>(LNames, 'Yes');
  Assert.Contains<string>(LNames, 'Green');
  Assert.Contains<string>(LNames, 'Black');
  Assert.Contains<string>(LNames, 'Text');
end;

procedure TTypeIdentityTests.FactsSurviveResolverAliasesAndReset;
var LTree: IUnitSyntaxTree; LResolver: IExternalUnitResolver; LPort: IUnitExportFactResolver;
  LTarget: TProjectCompilationContext; LFacts: TArray<TExportedSymbol>;
  LNames: TArray<string>; LInit, LNative: Boolean; LCache: TUnitDependencyCache;
begin
  LTree := Parse('Provider', 'type TBag<A,B> = class end; implementation');
  LTarget := Default(TProjectCompilationContext);
  LTarget.ProjectPath := TPath.Combine(FDirectory, 'App.dproj');
  LTarget.Aliases := ['Alias=Provider'];
  LResolver := TTargetUnitResolver.Create(FParser, LTarget, '');
  Assert.IsTrue(LResolver.TryResolveUnit('Alias', LNames, LInit, LNative));
  Assert.IsTrue(Supports(LResolver, IUnitExportFactResolver, LPort));
  Assert.IsTrue(LPort.TryGetExportFacts('Alias', LFacts));
  Assert.AreEqual(2, LFacts[0].GenericArity);
  LFacts[0].Name := 'changed';
  Assert.IsTrue(LPort.TryGetExportFacts('Alias', LFacts));
  Assert.AreEqual('TBag', LFacts[0].Name);
  LResolver.Initialize([FDirectory], '', FDirectory);
  Assert.IsFalse(LPort.TryGetExportFacts('Alias', LFacts));
  LCache := TUnitDependencyCache.Create;
  try
    LCache.Capture('Provider', LTree);
    LCache.CopyName('Provider', 'Alias');
    Assert.IsTrue(LCache.TryGetExports('Alias', LFacts));
    Assert.AreEqual(2, LFacts[0].GenericArity);
    LCache.Clear;
    Assert.IsFalse(LCache.TryGetExports('Alias', LFacts));
  finally
    LCache.Free;
  end;
end;

procedure TTypeIdentityTests.QualifiedNamesRespectNestedArguments;
var LName: TTypeName;
begin
  LName := TTypeName.Read('TBag<TPair<System.Integer,string>,Boolean>');
  Assert.AreEqual('tbag', LName.Name);
  Assert.AreEqual(2, LName.Arity);
  Assert.AreEqual('TBag<System.Integer>', TTypeName.FirstSegment('TBag<System.Integer>.Create'));
  Assert.AreEqual('TBag<System.Integer>', TTypeName.LastSegment('UnitName.TBag<System.Integer>'));
  Assert.AreEqual('<T,,>', TTypeName.Parameters(3));
end;

procedure TTypeIdentityTests.AttributeAlternativesPreserveBothCandidates;
var LTree: IUnitSyntaxTree; LContext: TProjectContext; LAnalyzer: TAnalyzeUnitUses;
  LResult: TUnitAnalysisResult; LDecision: TDependencyDecision;
begin
  LTree := Parse('Consumer', 'uses Short, Suffixed; type [TMarker] TLocal = class end; implementation');
  LContext := TProjectContext.Create;
  LAnalyzer := TAnalyzeUnitUses.Create;
  try
    LContext.RegisterUnitExports('Short', ['TMarker']);
    LContext.RegisterUnitExports('Suffixed', ['TMarkerAttribute']);
    LContext.RegisterUnitDependencies('Short', []);
    LContext.RegisterUnitDependencies('Suffixed', []);
    LResult := LAnalyzer.Execute(LTree, LContext);
    Assert.AreEqual<NativeInt>(2, Length(LResult.Decisions));
    for LDecision in LResult.Decisions do
    begin
      Assert.AreEqual(Ord(daPreserve), Ord(LDecision.Action));
      Assert.AreEqual(Ord(dsUnknown), Ord(LDecision.State));
    end;
  finally
    LAnalyzer.Free;
    LContext.Free;
  end;
end;

procedure TTypeIdentityTests.QualifiedArgumentsAndAttributeNamesSurviveFlattening;
var LTree: IUnitSyntaxTree; LPort: IUnitSymbolFacts; LFacts: TUnitSymbolFacts;
  LReference: TSymbolReference; LGeneric, LAttribute: Boolean; LNames: TArray<string>;
begin
  LTree := Parse('Consumer', 'var Value: Containers.TBag<Other.TItem,Lists.TList<System.Integer>>; ' +
    'type [Markers.TMarkerAttribute] TTagged = class end; implementation');
  LNames := LTree.GetIdentifiersUsedInInterface;
  Assert.Contains<string>(LNames, 'Other.TItem');
  Assert.Contains<string>(LNames, 'Lists.TList<T>');
  Assert.Contains<string>(LNames, 'System.Integer');
  Assert.IsTrue(Supports(LTree, IUnitSymbolFacts, LPort));
  LFacts := LPort.GetSymbolFacts;
  LGeneric := False;
  LAttribute := False;
  for LReference in LFacts.References do
  begin
    if LReference.Name = 'Containers.TBag<T,>' then
    begin
      Assert.AreEqual(2, LReference.GenericArity);
      LGeneric := True;
    end;
    if LReference.Name = 'Markers.TMarkerAttribute' then
    begin
      Assert.IsTrue(LReference.IsAttribute);
      LAttribute := True;
    end;
  end;
  Assert.IsTrue(LGeneric);
  Assert.IsTrue(LAttribute);
end;

procedure TTypeIdentityTests.ExportIndexMatchesLinearContract;
var LExports: TUnitExports; LFacts: TArray<TExportedSymbol>; LFact: TExportedSymbol;
  LNames: TArray<string>; LName, LQuery: string; LParsed: TTypeName;
  I, LArity: Integer; LExpected: Boolean;
begin
  LNames := ['TBag', 'TBAG', 'Owner.Item', 'Other.Item', 'Run',
    'Type' + Char($00C7), 'Type' + Char($00E7)];
  SetLength(LFacts, Length(LNames));
  for I := 0 to High(LFacts) do
  begin
    LFacts[I].Name := LNames[I];
    LFacts[I].Kind := ekType;
    LFacts[I].GenericArity := I mod 3;
  end;
  LFacts[4].Kind := ekRoutine;
  LExports := TUnitExports.Create('Dependency');
  try
    LExports.SetExportFacts(LFacts + LFacts);
    for LName in LNames + ['Missing', 'Item'] do
      for LArity := 0 to 4 do
      begin
        LQuery := LName + TTypeName.Parameters(LArity);
        LParsed := TTypeName.Read(LQuery);
        LExpected := False;
        for LFact in LFacts do
          if SameText(LFact.Name, LParsed.Name) then
            if (LFact.GenericArity = LParsed.Arity) or
              ((LFact.Kind = ekRoutine) and (LParsed.Arity = 0)) then
              LExpected := True;
        Assert.AreEqual(LExpected, LExports.MatchesIdentifier(LQuery, True), LQuery);
      end;
  finally
    LExports.Free;
  end;
end;

procedure TTypeIdentityTests.ReplacingExportFactsDropsOldCandidates;
var LExports: TUnitExports; LFacts: TArray<TExportedSymbol>;
begin
  LExports := TUnitExports.Create('Dependency');
  try
    SetLength(LFacts, 1);
    LFacts[0].Name := 'Before';
    LFacts[0].Kind := ekRoutine;
    LFacts[0].GenericArity := 2;
    LExports.SetExportFacts(LFacts);
    LFacts[0].Name := 'After';
    LFacts[0].Kind := ekType;
    LFacts[0].GenericArity := 1;
    Assert.IsTrue(LExports.MatchesIdentifier('Before', True));
    Assert.IsFalse(LExports.MatchesIdentifier('After<T>', True));
    LExports.SetExportFacts(LFacts);
    Assert.IsFalse(LExports.MatchesIdentifier('Before', True));
    Assert.IsFalse(LExports.MatchesIdentifier('Before<T,U>', True));
    Assert.IsTrue(LExports.MatchesIdentifier('After<T>', True));
    Assert.IsFalse(LExports.MatchesIdentifier('After', True));
    LExports.SetExportFacts(nil);
    Assert.IsFalse(LExports.MatchesIdentifier('After<T>', True));
  finally
    LExports.Free;
  end;
end;

procedure TTypeIdentityTests.ExportIndexKeepsLegacyFallbackSeparate;
var LExports: TUnitExports;
begin
  LExports := TUnitExports.Create('Dependency');
  try
    LExports.AddIdentifiers(['Legacy']);
    Assert.IsTrue(LExports.MatchesIdentifier('LEGACY<T>', True));
    LExports.SetExportFacts(nil);
    Assert.IsFalse(LExports.MatchesIdentifier('Legacy', True));
    Assert.IsTrue(LExports.MatchesIdentifier('Legacy', False));
  finally
    LExports.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTypeIdentityTests);
end.
