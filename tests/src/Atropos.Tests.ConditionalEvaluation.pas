unit Atropos.Tests.ConditionalEvaluation;

interface

uses DUnitX.TestFramework, Atropos.Core.Ports, Atropos.Core.Compilation;

type
  [TestFixture]
  TConditionalEvaluationTests = class
  private
    FRoot: string;
    function WriteSource(const AName, AText: string): string;
    function Parse(const ASource: string; const AOptions: TArray<TCompilerOption> = nil): IUnitSyntaxTree;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [TestCase('Nested', '(DEFINED(A) AND NOT DEFINED(B)),true')]
    [TestCase('CaseAndSpacing', 'defined ( a ) OR defined(B),true')]
    [TestCase('AndBeforeOr', 'TRUE OR FALSE AND FALSE,true')]
    [TestCase('RelationLast', 'FALSE AND TRUE = FALSE,true')]
    [TestCase('Xor', 'TRUE XOR TRUE,false')]
    [TestCase('NotNot', 'NOT NOT TRUE,true')]
    [TestCase('Version', '(CompilerVersion >= 36.0) AND (CompilerVersion < 37),true')]
    [TestCase('Signed', '-2 < +1,true')]
    [TestCase('LessEqual', '2 <= 1,false')]
    [TestCase('NotEqual', '2 <> 1,true')]
    [TestCase('Greater', '2 > 1,true')]
    [TestCase('LargeIntegers', '9007199254740993 > 9007199254740992,true')]
    procedure ExpressionMatchesBooleanSemantics(const AText: string; AExpected: Boolean);
    [TestCase('Unknown', 'Declared(TMissing)')]
    [TestCase('MissingClose', '(TRUE')]
    [TestCase('Trailing', 'TRUE garbage')]
    [TestCase('NumericNot', 'NOT 1 = 0')]
    [TestCase('MixedTypes', 'TRUE = 1')]
    [TestCase('NumericBoolean', '1 AND 1')]
    [TestCase('BadDefine', 'DEFINED(12)')]
    [TestCase('MixedPrecision', '9007199254740993 = 9007199254740992.0')]
    [TestCase('DecimalPrecision', '0.123456789012345678 = 0.123456789012345679')]
    procedure UnsupportedExpressionsFailExplicitly(const AText: string);
    [Test] procedure NestedExpressionsSelectTheCorrectImport;
    [Test] procedure ElseIfSelectsOnlyTheFirstMatchingBranch;
    [Test] procedure IncludesShareDefinesAndSwitchesInSourceOrder;
    [Test] procedure RepeatedIncludesUseTheirOwnPreparedContent;
    [Test] procedure InactiveBranchesDoNotLoadIncludesOrChangeSwitches;
    [Test] procedure ProjectSwitchIsOverriddenByLocalDirective;
    [Test] procedure SwitchListsUpdateEachOption;
    [Test] procedure UnknownSwitchAndMalformedBranchesFail;
    [Test] procedure PreparationRetainsParentLinesAndIncludedPath;
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils,
  Atropos.Adapters.ConditionalExpression, Atropos.Adapters.DelphiAST;

procedure TConditionalEvaluationTests.Setup;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'Atropos-Conditions-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FRoot);
end;

procedure TConditionalEvaluationTests.TearDown;
begin
  if not TPath.GetFullPath(FRoot).StartsWith(
    TPath.Combine(TPath.GetTempPath, 'Atropos-Conditions-'), True) then
    raise Exception.Create('Unexpected conditional test path.');
  TDirectory.Delete(FRoot, True);
end;

function TConditionalEvaluationTests.WriteSource(const AName, AText: string): string;
begin
  Result := TPath.Combine(FRoot, AName);
  TFile.WriteAllText(Result, AText, TEncoding.UTF8);
end;

function TConditionalEvaluationTests.Parse(const ASource: string;
  const AOptions: TArray<TCompilerOption>): IUnitSyntaxTree;
var LContext: TProjectCompilationContext; LSymbols: TCompilerSymbols; LParser: IASTParser;
begin
  LContext := Default(TProjectCompilationContext);
  LContext.Options := AOptions;
  LSymbols := Default(TCompilerSymbols);
  LSymbols.CompilerVersion := '36.0';
  LParser := TDelphiASTAdapter.Create(LContext, LSymbols);
  Result := LParser.ParseFile(WriteSource('Consumer.pas', ASource));
end;

procedure TConditionalEvaluationTests.ExpressionMatchesBooleanSemantics(const AText: string; AExpected: Boolean);
var LExpression: TConditionalExpression;
begin
  LExpression := TConditionalExpression.Create(
    function(AName: string): Boolean begin Result := SameText(AName, 'A'); end, '36.0');
  try
    Assert.AreEqual(AExpected, LExpression.Evaluate(AText));
  finally
    LExpression.Free;
  end;
end;

procedure TConditionalEvaluationTests.UnsupportedExpressionsFailExplicitly(const AText: string);
var LExpression: TConditionalExpression;
begin
  LExpression := TConditionalExpression.Create(
    function(AName: string): Boolean begin Result := False; end, '36.0');
  try
    Assert.WillRaise(procedure begin LExpression.Evaluate(AText); end, EInvalidOpException);
  finally
    LExpression.Free;
  end;
end;

procedure TConditionalEvaluationTests.NestedExpressionsSelectTheCorrectImport;
var LTree: IUnitSyntaxTree; LDiagnostics: IUnitAnalysisDiagnostics;
begin
  LTree := Parse('unit C; interface {$DEFINE A} uses ' +
    '{$IF (DEFINED(A) AND NOT DEFINED(B))} RightUnit {$ELSE} WrongUnit {$IFEND}; implementation end.');
  Assert.AreEqual('RightUnit', LTree.GetInterfaceUses[0]);
  Assert.IsTrue(Supports(LTree, IUnitAnalysisDiagnostics, LDiagnostics));
  Assert.AreEqual<NativeInt>(0, Length(LDiagnostics.GetIncompleteAnalysisReasons));
end;

procedure TConditionalEvaluationTests.ElseIfSelectsOnlyTheFirstMatchingBranch;
var LTree: IUnitSyntaxTree;
begin
  LTree := Parse('unit C; interface uses {$IF FALSE} FirstUnit {$ELSEIF TRUE} SecondUnit ' +
    '{$ELSEIF TRUE} ThirdUnit {$ELSE} LastUnit {$IFEND}; implementation end.');
  Assert.AreEqual('SecondUnit', LTree.GetInterfaceUses[0]);
end;

procedure TConditionalEvaluationTests.IncludesShareDefinesAndSwitchesInSourceOrder;
var LTree: IUnitSyntaxTree; LDependencies: IUnitSourceDependencies;
begin
  WriteSource('state.inc', '{$DEFINE FROM_INCLUDE}{$R+}');
  WriteSource('nested.inc', '{$I state.inc}');
  LTree := Parse('unit C; interface {$I nested.inc} {$IF DEFINED(FROM_INCLUDE)} ' +
    'uses {$IFOPT R+} RightUnit {$ELSE} WrongUnit {$ENDIF}; {$IFEND} implementation end.');
  Assert.AreEqual('RightUnit', LTree.GetInterfaceUses[0]);
  Assert.IsTrue(Supports(LTree, IUnitSourceDependencies, LDependencies));
  Assert.AreEqual<NativeInt>(2, Length(LDependencies.GetSourceDependencies));
end;

procedure TConditionalEvaluationTests.RepeatedIncludesUseTheirOwnPreparedContent;
var LTree: IUnitSyntaxTree;
begin
  WriteSource('repeat.inc', '{$IFDEF FLAG}type TOn = Integer;{$ELSE}type TOff = Integer;{$ENDIF}');
  LTree := Parse('unit C; interface {$DEFINE FLAG}{$I repeat.inc}{$UNDEF FLAG}{$I repeat.inc} implementation end.');
  Assert.Contains<string>(LTree.GetExportedIdentifiers, 'TOn');
  Assert.Contains<string>(LTree.GetExportedIdentifiers, 'TOff');
end;

procedure TConditionalEvaluationTests.InactiveBranchesDoNotLoadIncludesOrChangeSwitches;
var LTree: IUnitSyntaxTree;
begin
  LTree := Parse('unit C; interface {$R+}{$IF FALSE}{$R-}{$DEFINE BAD}' +
    '{$I absent.inc}{$IF Unsupported(Thing)}invalid{$IFEND}{$ENDIF}' +
    'uses {$IFOPT R+}RightUnit{$ELSE}WrongUnit{$ENDIF}; implementation end.');
  Assert.AreEqual('RightUnit', LTree.GetInterfaceUses[0]);
end;

procedure TConditionalEvaluationTests.ProjectSwitchIsOverriddenByLocalDirective;
var LTree: IUnitSyntaxTree; LOption: TCompilerOption;
begin
  LOption.Name := 'RangeChecking';
  LOption.Value := 'true';
  LTree := Parse('unit C; interface uses {$IFOPT R+}RightUnit{$ELSE}WrongUnit{$ENDIF}; ' +
    'implementation {$RANGECHECKS OFF} uses {$IFOPT R-}LocalUnit{$ELSE}WrongUnit{$ENDIF}; end.', [LOption]);
  Assert.AreEqual('RightUnit', LTree.GetInterfaceUses[0]);
  Assert.AreEqual('LocalUnit', LTree.GetImplementationUses[0]);
end;

procedure TConditionalEvaluationTests.SwitchListsUpdateEachOption;
var LTree: IUnitSyntaxTree;
begin
  LTree := Parse('unit C; interface {$R-,Q+}{$R+,Q-}' +
    'uses {$IFOPT R+}RightUnit{$ELSE}WrongUnit{$ENDIF}; implementation ' +
    'uses {$IFOPT Q-}LocalUnit{$ELSE}WrongUnit{$ENDIF}; end.');
  Assert.AreEqual('RightUnit', LTree.GetInterfaceUses[0]);
  Assert.AreEqual('LocalUnit', LTree.GetImplementationUses[0]);
end;

procedure TConditionalEvaluationTests.UnknownSwitchAndMalformedBranchesFail;
begin
  Assert.WillRaise(procedure begin Parse('unit C; interface {$IFOPT R+}uses X;{$ENDIF} implementation end.'); end,
    EASTParserException);
  Assert.WillRaise(procedure begin Parse('unit C; interface {$ELSE} implementation end.'); end,
    EASTParserException);
  Assert.WillRaise(procedure begin Parse('unit C; interface {$IF TRUE} implementation end.'); end,
    EASTParserException);
  Assert.WillRaise(procedure begin Parse('unit C; interface {$IF FALSE}{$ELSE}{$ELSE} implementation end.'); end,
    EASTParserException);
end;

procedure TConditionalEvaluationTests.PreparationRetainsParentLinesAndIncludedPath;
var LTree: IUnitSyntaxTree; LFacts: IUnitSymbolFacts; LDeclaration: TSymbolDeclaration;
  LFoundParent, LFoundInclude: Boolean; LPath: string;
begin
  LPath := WriteSource('types.inc', 'type TIncluded = Integer;');
  LTree := Parse('unit C;' + #10 + 'interface' + #10 + '{$I types.inc}' + #10 +
    '{$IF FALSE} inactive text' + #10 + '{$ENDIF}' + #10 +
    'type TAfter = Integer;' + #10 + 'implementation end.');
  Assert.IsTrue(Supports(LTree, IUnitSymbolFacts, LFacts));
  LFoundParent := False;
  LFoundInclude := False;
  for LDeclaration in LFacts.GetSymbolFacts.Declarations do
  begin
    if SameText(LDeclaration.Name, 'TAfter') then
    begin
      Assert.AreEqual(6, LDeclaration.NormalizedLine);
      LFoundParent := True;
    end;
    if SameText(LDeclaration.Name, 'TIncluded') then
    begin
      Assert.AreEqual(LPath, LDeclaration.SourcePath);
      LFoundInclude := True;
    end;
  end;
  Assert.IsTrue(LFoundParent and LFoundInclude);
end;

initialization
  TDUnitX.RegisterTestFixture(TConditionalEvaluationTests);
end.
