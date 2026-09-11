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
    function ParseNumeric(const ASource: string): IUnitSyntaxTree;
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
    [TestCase('EmptyProjectOption', '0')]
    [TestCase('ProjectOverride', '1')]
    procedure CompilerDefaultsRespectProjectAndLocalOptions(AOverride: Integer);
    [Test] procedure SwitchListsUpdateEachOption;
    [Test] procedure UnknownSwitchAndMalformedBranchesFail;
    [Test] procedure InvalidProjectSwitchDoesNotSilentlyUseDefault;
    [Test] procedure ResourceDirectiveDoesNotChangeRangeChecking;
    [TestCase('LocalType', '0')]
    [TestCase('ImportedType', '1')]
    [TestCase('LocalVersion', '2')]
    [TestCase('SystemQualifier', '3')]
    [TestCase('IncludeType', '4')]
    procedure NumericNamesRequiringBindingRemainUnknown(AScenario: Integer);
    [Test] procedure QualifiedNumericFactsIgnoreUnrelatedLocalType;
    [Test] procedure PreparationRetainsParentLinesAndIncludedPath;
    [TestCase('Active', 'TRUE')]
    [TestCase('Inactive', 'FALSE')]
    procedure AssemblyQuotesDoNotConsumeConditionalEnd(const ACondition: string);
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils,
  Atropos.Adapters.ConditionalExpression, Atropos.Adapters.DelphiAST, Atropos.Core.UnitSymbols;

procedure TConditionalEvaluationTests.AssemblyQuotesDoNotConsumeConditionalEnd(const ACondition: string);
var LTree: IUnitSyntaxTree; LFacts: IUnitSymbolFacts; LDeclaration: TSymbolDeclaration; LFound: Boolean;
begin
  LTree := Parse('unit Consumer; interface implementation ' +
    '{$IF ' + ACondition + '} procedure Run; asm CMP AL,"''" end; {$ENDIF}' +
    ' {$IF TRUE} type TAfterAssembly = Integer; {$ENDIF} end.');
  Assert.AreEqual('Consumer', LTree.GetUnitName);
  Assert.IsTrue(Supports(LTree, IUnitSymbolFacts, LFacts));
  LFound := False;
  for LDeclaration in LFacts.GetSymbolFacts.Declarations do
    if SameText(LDeclaration.Name, 'TAfterAssembly') then LFound := True;
  Assert.IsTrue(LFound, 'Declaration after the assembler block must remain visible.');
end;

function TConditionalEvaluationTests.ParseNumeric(const ASource: string): IUnitSyntaxTree;
var LContext: TProjectCompilationContext; LSymbols: TCompilerSymbols; LParser: IASTParser;
begin
  LContext := Default(TProjectCompilationContext);
  LSymbols := Default(TCompilerSymbols);
  LSymbols.CompilerVersion := '36.0';
  SetLength(LSymbols.NumericValues, 2);
  LSymbols.NumericValues[0].Name := 'SIZEOF.EXTENDED';
  LSymbols.NumericValues[0].Value := '10';
  LSymbols.NumericValues[1].Name := 'RTLVERSION';
  LSymbols.NumericValues[1].Value := '36.0';
  LParser := TDelphiASTAdapter.Create(LContext, LSymbols);
  Result := LParser.ParseFile(WriteSource('Consumer.pas', ASource));
end;

procedure TConditionalEvaluationTests.NumericNamesRequiringBindingRemainUnknown(AScenario: Integer);
const Sources: array[0..4] of string = (
  'type Extended = Integer; {$IF SizeOf(Extended) = 10}',
  'uses Provider; {$IF SizeOf(Extended) = 10}',
  'const RTLVersion = 1; {$IF RTLVersion = 36}',
  'type System = class end; {$IF SizeOf(System.Extended) = 10}',
  '{$I shadow.inc} {$IF SizeOf(Extended) = 10}');
begin
  WriteSource('shadow.inc', 'type Extended = Integer;');
  Assert.WillRaise(procedure begin
    ParseNumeric('unit Consumer; interface ' + Sources[AScenario] +
      'type TWrong = Integer;{$ENDIF} implementation end.');
  end, EASTParserException);
end;

procedure TConditionalEvaluationTests.QualifiedNumericFactsIgnoreUnrelatedLocalType;
var LTree: IUnitSyntaxTree;
begin
  LTree := ParseNumeric('unit Consumer; interface type Extended = Integer; ' +
    '{$IF SizeOf(System.Extended) = 10}type TCorrect = Integer;{$ENDIF} implementation end.');
  Assert.Contains<string>(LTree.GetExportedIdentifiers, 'TCorrect');
end;

procedure TConditionalEvaluationTests.ResourceDirectiveDoesNotChangeRangeChecking;
var LTree: IUnitSyntaxTree; LOption: TCompilerOption;
begin
  LOption.Name := 'RangeChecking';
  LOption.Value := 'true';
  LTree := Parse('unit C; {$R *.dfm} {$L external.obj} interface ' +
    '{$IFOPT R+}type TStillOn = Integer;{$ELSE}type TWrong = Integer;{$ENDIF} implementation end.', [LOption]);
  Assert.AreEqual('TStillOn', LTree.GetExportedIdentifiers[0]);
end;
procedure TConditionalEvaluationTests.InvalidProjectSwitchDoesNotSilentlyUseDefault;
var LContext: TProjectCompilationContext; LSymbols: TCompilerSymbols; LParser: IASTParser;
begin
  LContext := Default(TProjectCompilationContext);
  LSymbols := Default(TCompilerSymbols);
  SetLength(LSymbols.DefaultSwitches, 1);
  LSymbols.DefaultSwitches[0].Name := 'R';
  LSymbols.DefaultSwitches[0].Value := 'OFF';
  SetLength(LContext.Options, 1);
  LContext.Options[0].Name := 'RangeChecking';
  LContext.Options[0].Value := 'invalid';
  LParser := TDelphiASTAdapter.Create(LContext, LSymbols);
  Assert.WillRaise(procedure begin
    LParser.ParseFile(WriteSource('Consumer.pas', 'unit Consumer; interface implementation end.'));
  end, EASTParserException);
end;

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

procedure TConditionalEvaluationTests.CompilerDefaultsRespectProjectAndLocalOptions(AOverride: Integer);
var LContext: TProjectCompilationContext; LSymbols: TCompilerSymbols;
  LParser: IASTParser; LTree: IUnitSyntaxTree; LExpected: string;
begin
  LContext := Default(TProjectCompilationContext);
  LSymbols := Default(TCompilerSymbols);
  LSymbols.CompilerVersion := '36.0';
  SetLength(LSymbols.DefaultSwitches, 1);
  LSymbols.DefaultSwitches[0].Name := 'R';
  LSymbols.DefaultSwitches[0].Value := 'OFF';
  SetLength(LContext.Options, 1);
  LContext.Options[0].Name := 'RangeChecking';
  LContext.Options[0].Value := '';
  LExpected := 'DefaultOff';
  if AOverride = 1 then
  begin
    LContext.Options[0].Value := 'true';
    LExpected := 'ProjectOn';
  end;
  LParser := TDelphiASTAdapter.Create(LContext, LSymbols);
  LTree := LParser.ParseFile(WriteSource('Consumer.pas',
    'unit Consumer; interface uses {$IFOPT R+}ProjectOn{$ELSE}DefaultOff{$ENDIF}; ' +
    'implementation {$R-} uses {$IFOPT R-}LocalOff{$ELSE}WrongUnit{$ENDIF}; end.'));
  Assert.AreEqual(LExpected, LTree.GetInterfaceUses[0]);
  Assert.AreEqual('LocalOff', LTree.GetImplementationUses[0]);
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
