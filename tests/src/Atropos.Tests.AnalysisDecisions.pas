unit Atropos.Tests.AnalysisDecisions;

interface

uses DUnitX.TestFramework, Atropos.Core.Analysis, Atropos.Core.Domain,
  Atropos.Core.Ports, Atropos.Tests.Domain;

type
  TDiagnosticSyntaxTree = class(TMockSyntaxTree, IUnitAnalysisDiagnostics)
  public
    IncompleteReasons: TArray<string>;
    function GetIncompleteAnalysisReasons: TArray<string>;
  end;

  [TestFixture]
  TAnalysisDecisionTests = class
  private
    FDecisions: TDependencyDecisions;
    FContext: TProjectContext;
    FParser: IASTParser;
    function ScenarioPath(const ARelativePath: string): string;
    procedure RegisterProvider(const AName: string; AIsNative: Boolean = False);
    function AnalyzeScenario(const AName: string): TUnitAnalysisResult;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure UncertainDecisionCannotAuthorizeRemoval;
    [Test] procedure AmbiguousDecisionCannotAuthorizeMovement;
    [Test] procedure RetainedOccurrenceBlocksLegacyNameRemoval;
    [Test] procedure RemovalAndMovementAreSeparateActions;
    [Test] procedure PreservationMessagesIdentifySectionAndState;
    [Test] procedure RealCrossSectionAmbiguityPreservesBothImports;
    [Test] procedure RealNativeInitializationIsPreserved;
    [Test] procedure MissingProviderIsReportedAsUnknown;
    [Test] procedure QualifiedReferenceDoesNotBecomeAmbiguous;
    [Test] procedure IncompleteTreeNeverAuthorizesChanges;
    [Test] procedure CompleteDiagnosticTreeStillAnalyzesImports;
  end;

implementation

uses System.SysUtils, System.IOUtils, Atropos.Adapters.DelphiAST;

function TDiagnosticSyntaxTree.GetIncompleteAnalysisReasons: TArray<string>;
begin
  Result := IncompleteReasons;
end;

procedure TAnalysisDecisionTests.Setup;
begin
  FDecisions := TDependencyDecisions.Create;
  FContext := TProjectContext.Create;
  FParser := TDelphiASTAdapter.Create;
end;

procedure TAnalysisDecisionTests.TearDown;
begin
  FParser := nil;
  FContext.Free;
  FDecisions.Free;
end;

function TAnalysisDecisionTests.ScenarioPath(const ARelativePath: string): string;
begin
  Result := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)),
    '..\..\SemanticProbe\scenarios\' + ARelativePath));
end;

procedure TAnalysisDecisionTests.RegisterProvider(const AName: string;
  AIsNative: Boolean);
var
  LTree: IUnitSyntaxTree;
begin
  LTree := FParser.ParseFile(ScenarioPath('providers\' + AName + '.pas'));
  FContext.RegisterUnitExports(LTree.GetUnitName, LTree.GetExportedIdentifiers,
    LTree.HasInitializationSection, AIsNative);
  FContext.RegisterUnitDependencies(LTree.GetUnitName,
    LTree.GetInterfaceUses + LTree.GetImplementationUses);
end;

function TAnalysisDecisionTests.AnalyzeScenario(
  const AName: string): TUnitAnalysisResult;
var
  LAnalyzer: TAnalyzeUnitUses;
begin
  LAnalyzer := TAnalyzeUnitUses.Create;
  try
    Result := LAnalyzer.Execute(FParser.ParseFile(
      ScenarioPath(AName + '\Consumer.pas')), FContext);
  finally
    LAnalyzer.Free;
  end;
end;

procedure TAnalysisDecisionTests.UncertainDecisionCannotAuthorizeRemoval;
begin
  Assert.WillRaise(
    procedure
    begin
      TDependencyDecision.Create('Missing', usInterface, dsUnknown,
        daRemove, 'Missing source');
    end, EArgumentException);
end;

procedure TAnalysisDecisionTests.AmbiguousDecisionCannotAuthorizeMovement;
begin
  Assert.WillRaise(
    procedure
    begin
      TDependencyDecision.Create('Collision', usInterface, dsAmbiguous,
        daMoveToImplementation, 'Multiple candidates');
    end, EArgumentException);
end;

procedure TAnalysisDecisionTests.RetainedOccurrenceBlocksLegacyNameRemoval;
begin
  FDecisions.Add(TDependencyDecision.Create('Shared', usInterface,
    dsUsed, daPreserve, 'Interface reference'));
  FDecisions.Add(TDependencyDecision.Create('shared', usImplementation,
    dsUnused, daRemove, 'No implementation reference'));
  Assert.AreEqual<NativeInt>(0, Length(FDecisions.UnitsForAction(daRemove)));
  Assert.AreEqual<NativeInt>(2, Length(FDecisions.ToArray));
end;

procedure TAnalysisDecisionTests.RemovalAndMovementAreSeparateActions;
begin
  FDecisions.Add(TDependencyDecision.Create('Unused', usInterface,
    dsUnused, daRemove, 'No reference'));
  FDecisions.Add(TDependencyDecision.Create('Unused', usImplementation,
    dsUnused, daRemove, 'No reference'));
  FDecisions.Add(TDependencyDecision.Create('Body', usInterface,
    dsUsed, daMoveToImplementation, 'Implementation reference'));
  Assert.AreEqual<NativeInt>(1, Length(FDecisions.UnitsForAction(daRemove)));
  Assert.AreEqual('Body', FDecisions.UnitsForAction(daMoveToImplementation)[0]);
  Assert.AreEqual<NativeInt>(0, Length(FDecisions.PreservationMessages));
end;

procedure TAnalysisDecisionTests.PreservationMessagesIdentifySectionAndState;
var
  LMessages: TArray<string>;
begin
  FDecisions.Add(TDependencyDecision.Create('Missing', usImplementation,
    dsUnknown, daPreserve, 'No source'));
  LMessages := FDecisions.PreservationMessages;
  Assert.AreEqual<NativeInt>(1, Length(LMessages));
  Assert.AreEqual('Missing [implementation, unknown]: No source', LMessages[0]);
end;

procedure TAnalysisDecisionTests.RealCrossSectionAmbiguityPreservesBothImports;
var
  LResult: TUnitAnalysisResult;
begin
  RegisterProvider('ProbeDep');
  RegisterProvider('ProbeCollision');
  LResult := AnalyzeScenario('ambiguity-across-sections');
  Assert.AreEqual<NativeInt>(0, Length(LResult.UnusedUnits));
  Assert.AreEqual<NativeInt>(0, Length(LResult.UnitsToMoveToImpl));
  Assert.AreEqual<NativeInt>(2, Length(LResult.Decisions));
  Assert.AreEqual(Integer(dsAmbiguous), Integer(LResult.Decisions[0].State));
  Assert.AreEqual(Integer(dsAmbiguous), Integer(LResult.Decisions[1].State));
  Assert.AreEqual<NativeInt>(2, Length(LResult.PreservationReasons));
end;

procedure TAnalysisDecisionTests.RealNativeInitializationIsPreserved;
var
  LResult: TUnitAnalysisResult;
begin
  RegisterProvider('ProbeInit', True);
  LResult := AnalyzeScenario('keep-native-effects');
  Assert.AreEqual<NativeInt>(0, Length(LResult.UnusedUnits));
  Assert.AreEqual<NativeInt>(0, Length(LResult.UnitsToMoveToImpl));
  Assert.AreEqual(Integer(dsUsed), Integer(LResult.Decisions[0].State));
  Assert.IsTrue(LResult.Decisions[0].Reason.Contains('Known lifecycle effects via '));
end;

procedure TAnalysisDecisionTests.MissingProviderIsReportedAsUnknown;
var
  LResult: TUnitAnalysisResult;
begin
  LResult := AnalyzeScenario('unknown-unit');
  Assert.AreEqual<NativeInt>(0, Length(LResult.UnusedUnits));
  Assert.AreEqual(Integer(dsUnknown), Integer(LResult.Decisions[0].State));
  Assert.AreEqual<NativeInt>(1, Length(LResult.PreservationReasons));
end;

procedure TAnalysisDecisionTests.QualifiedReferenceDoesNotBecomeAmbiguous;
var
  LResult: TUnitAnalysisResult;
begin
  RegisterProvider('ProbeDep');
  RegisterProvider('ProbeCollision');
  LResult := AnalyzeScenario('qualified-type');
  Assert.AreEqual<NativeInt>(0, Length(LResult.PreservedAmbiguities));
  Assert.AreEqual<NativeInt>(0, Length(LResult.PreservationReasons));
end;

procedure TAnalysisDecisionTests.IncompleteTreeNeverAuthorizesChanges;
var
  LTree: TDiagnosticSyntaxTree;
  LTreeReference: IUnitSyntaxTree;
  LAnalyzer: TAnalyzeUnitUses;
  LResult: TUnitAnalysisResult;
begin
  LTree := TDiagnosticSyntaxTree.Create;
  LTreeReference := LTree;
  LTree.UnitName := 'Incomplete';
  LTree.IntfUses := ['ProbeDep'];
  LTree.ImplUses := ['Other'];
  LTree.IncompleteReasons := ['Unresolved include: symbols.inc'];
  RegisterProvider('ProbeDep');
  LAnalyzer := TAnalyzeUnitUses.Create;
  try
    LResult := LAnalyzer.Execute(LTreeReference, FContext);
    Assert.AreEqual<NativeInt>(0, Length(LResult.UnusedUnits));
    Assert.AreEqual<NativeInt>(0, Length(LResult.UnitsToMoveToImpl));
    Assert.AreEqual<NativeInt>(2, Length(LResult.Decisions));
    Assert.AreEqual(Integer(dsUnknown), Integer(LResult.Decisions[0].State));
    Assert.IsTrue(LResult.PreservationReasons[0].Contains('symbols.inc'));
  finally
    LAnalyzer.Free;
  end;
end;

procedure TAnalysisDecisionTests.CompleteDiagnosticTreeStillAnalyzesImports;
var
  LTree: TDiagnosticSyntaxTree;
  LTreeReference: IUnitSyntaxTree;
  LAnalyzer: TAnalyzeUnitUses;
  LResult: TUnitAnalysisResult;
begin
  LTree := TDiagnosticSyntaxTree.Create;
  LTreeReference := LTree;
  LTree.UnitName := 'Complete';
  LTree.IntfUses := ['ProbeDep'];
  RegisterProvider('ProbeDep');
  LAnalyzer := TAnalyzeUnitUses.Create;
  try
    LResult := LAnalyzer.Execute(LTreeReference, FContext);
    Assert.AreEqual<NativeInt>(1, Length(LResult.UnusedUnits));
    Assert.AreEqual<NativeInt>(0, Length(LResult.PreservationReasons));
  finally
    LAnalyzer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAnalysisDecisionTests);

end.
