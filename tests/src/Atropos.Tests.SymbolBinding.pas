unit Atropos.Tests.SymbolBinding;

interface

uses DUnitX.TestFramework, Atropos.Core.Ports, Atropos.Core.Domain;

type
  [TestFixture]
  TSymbolBindingTests = class
  private
    FDirectory, FSource: string;
    FParser: IASTParser;
    function Analyze(const ABody: string): TUnitAnalysisResult;
    function ReadFacts(const ABody: string): TUnitSymbolFacts;
    function FindDeclaration(const AFacts: TUnitSymbolFacts; const AName: string;
      ASection: TSymbolSection): TSymbolDeclaration;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [TestCase('LocalVariable', '0,0')]
    [TestCase('OtherRoutineStillUsesImport', '1,1')]
    [TestCase('InlineBlockDoesNotLeak', '2,1')]
    [TestCase('ReferenceBeforeInlineDeclaration', '3,1')]
    [TestCase('InitializerBeforeBinding', '4,1')]
    [TestCase('ParameterDoesNotLeak', '5,1')]
    [TestCase('GenericParameter', '6,0')]
    [TestCase('GenericArityDoesNotHidePlainType', '7,1')]
    [TestCase('ImplementationDoesNotHideInterface', '8,2')]
    [TestCase('AliasSourceStillReferencesImport', '9,2')]
    [TestCase('VariableNameDoesNotHideItsType', '10,2')]
    [TestCase('ClassFieldInImplementationMethod', '11,0')]
    [TestCase('ExternalFieldType', '12,2')]
    [TestCase('StaticReceiverType', '13,1')]
    [TestCase('QualifiedTypeMember', '14,1')]
    [TestCase('ObjectMemberIsNotGlobalRoutine', '15,0')]
    [TestCase('WithScopeIsUnknown', '16,3')]
    [TestCase('LocalOverloadIsUnknown', '17,3')]
    [TestCase('AnonymousParameterShadowsImport', '18,0')]
    [TestCase('AnonymousParameterDoesNotLeak', '19,1')]
    [TestCase('AnonymousCapturesLocal', '20,0')]
    [TestCase('AnonymousCapturesImport', '21,1')]
    [TestCase('AnonymousFunctionReturnType', '22,1')]
    [TestCase('SiblingAnonymousScopes', '23,1')]
    procedure LexicalDecisionsRespectScopes(AScenario, AAction: Integer);
    [Test] procedure FactsRetainKindsLocationsAndIndependentReads;
    [Test] procedure IncludeDeclarationsUseExpandedOrder;
    [TestCase('ImplementationRoutine', '0')]
    [TestCase('InterfaceRoutine', '1')]
    [TestCase('TypeDeclaration', '2')]
    [TestCase('ClassMethod', '3')]
    procedure DeclarationStartInIncludeKeepsSource(AScenario: Integer);
    [TestCase('Private', 'private,3')]
    [TestCase('StrictPrivate', 'strict private,4')]
    [TestCase('Protected', 'protected,5')]
    [TestCase('StrictProtected', 'strict protected,6')]
    [TestCase('Public', 'public,7')]
    [TestCase('Published', 'published,8')]
    procedure DeclarationsRetainExplicitVisibility(const AVisibility: string; AExpected: Integer);
    [Test] procedure ImplicitAndOutOfLineAccessStayUnknown;
    [TestCase('Initialization', 'initialization,3')]
    [TestCase('Finalization', 'finalization,4')]
    procedure InlineLifecycleDeclarationRetainsSection(const APhase: string; AExpected: Integer);
  end;

implementation

uses System.SysUtils, System.IOUtils, Atropos.Adapters.DelphiAST, Atropos.Core.Analysis;

procedure TSymbolBindingTests.Setup;
begin
  FDirectory := TPath.Combine(TPath.GetTempPath, 'AtroposSymbols-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FDirectory);
  FSource := TPath.Combine(FDirectory, 'Consumer.pas');
  FParser := TDelphiASTAdapter.Create;
end;

procedure TSymbolBindingTests.TearDown;
begin
  FParser := nil;
  TDirectory.Delete(FDirectory, True);
end;

function TSymbolBindingTests.Analyze(const ABody: string): TUnitAnalysisResult;
var LContext: TProjectContext; LAnalyzer: TAnalyzeUnitUses; LTree: IUnitSyntaxTree;
begin
  TFile.WriteAllText(FSource, 'unit Consumer; interface uses Dependency; ' + ABody + ' end.', TEncoding.UTF8);
  LContext := TProjectContext.Create;
  LAnalyzer := TAnalyzeUnitUses.Create;
  try
    LContext.RegisterUnitExports('Dependency', ['Clash', 'CallMe', 'TItem', 'TBase', 'Limit']);
    LContext.RegisterUnitDependencies('Dependency', []);
    LTree := FParser.ParseFile(FSource);
    Result := LAnalyzer.Execute(LTree, LContext);
  finally
    LAnalyzer.Free;
    LContext.Free;
  end;
end;

procedure TSymbolBindingTests.LexicalDecisionsRespectScopes(AScenario, AAction: Integer);
const Sources: array[0..23] of string = (
  'implementation procedure Run; var Clash: Integer; begin Clash := 1; end;',
  'implementation procedure A; var Clash: Integer; begin Clash := 1; end; ' +
    'procedure B; begin Clash := 2; end;',
  'implementation procedure Run; begin begin var Clash := 1; Inc(Clash); end; Inc(Clash); end;',
  'implementation procedure Run; begin Inc(Clash); var Clash := 1; Inc(Clash); end;',
  'implementation procedure Run; begin var Clash := Clash; Inc(Clash); end;',
  'implementation procedure A(Clash: Integer); begin Inc(Clash); end; procedure B; begin Inc(Clash); end;',
  'type TLocal<TItem> = class Value: TItem; end; implementation',
  'implementation type TItem<T> = class end; var Value: TItem;',
  'const Saved = Limit; implementation const Limit = 2;',
  'type TItem = TItem; implementation',
  'var TItem: TItem; implementation',
  'type TLocal = class Clash: Integer; procedure Run; end; ' +
    'implementation procedure TLocal.Run; begin Inc(Clash); end;',
  'type TLocal = class Value: TItem; end; implementation',
  'implementation procedure Run; begin TBase.Create; end;',
  'implementation procedure Run; begin Dependency.TBase.Create; end;',
  'type TLocal = class procedure CallMe; end; implementation ' +
    'procedure Run(Value: TLocal); begin Value.CallMe; end;',
  'implementation procedure Run(Value: TObject); var Clash: Integer; begin with Value do Inc(Clash); end;',
  'procedure CallMe; overload; implementation procedure CallMe; begin end; ' +
    'procedure Run; begin CallMe(1); end;',
  'implementation type TWork = reference to procedure(Clash: Integer); ' +
    'procedure Run; var Work: TWork; begin Work := procedure(Clash: Integer) begin Inc(Clash); end; end;',
  'implementation type TWork = reference to procedure(Clash: Integer); ' +
    'procedure Run; var Work: TWork; begin Work := procedure(Clash: Integer) begin Inc(Clash); end; Inc(Clash); end;',
  'implementation type TWork = reference to procedure; ' +
    'procedure Run; var Work: TWork; Clash: Integer; begin Clash := 1; Work := procedure begin Inc(Clash); end; end;',
  'implementation type TWork = reference to procedure; ' +
    'procedure Run; var Work: TWork; begin Work := procedure begin Inc(Clash); end; end;',
  'implementation type TWork = reference to function: TItem; ' +
    'procedure Run; var Work: TWork; begin Work := function: TItem begin Result := nil; end; end;',
  'implementation type TParam = reference to procedure(Clash: Integer); TWork = reference to procedure; ' +
    'procedure Run; var First: TParam; Second: TWork; begin ' +
    'First := procedure(Clash: Integer) begin Inc(Clash); end; Second := procedure begin Inc(Clash); end; end;');
var LResult: TUnitAnalysisResult;
begin
  LResult := Analyze(Sources[AScenario]);
  Assert.AreEqual<NativeInt>(1, Length(LResult.Decisions));
  case AAction of
    0: Assert.AreEqual(Ord(daRemove), Ord(LResult.Decisions[0].Action));
    1: Assert.AreEqual(Ord(daMoveToImplementation), Ord(LResult.Decisions[0].Action));
    2: Assert.AreEqual(Ord(daPreserve), Ord(LResult.Decisions[0].Action));
    3: begin
      Assert.AreEqual(Ord(daPreserve), Ord(LResult.Decisions[0].Action));
      Assert.AreEqual(Ord(dsUnknown), Ord(LResult.Decisions[0].State));
    end;
  end;
end;

procedure TSymbolBindingTests.FactsRetainKindsLocationsAndIndependentReads;
var LTree: IUnitSyntaxTree; LPort: IUnitSymbolFacts; LFacts: TUnitSymbolFacts;
  LDeclaration: TSymbolDeclaration; LFound: Boolean;
begin
  TFile.WriteAllText(FSource, 'unit Consumer; interface' + sLineBreak +
    'procedure Run(Value: Integer); implementation procedure Run(Value: Integer); ' +
    'begin Inc(Value); end; end.', TEncoding.UTF8);
  LTree := FParser.ParseFile(FSource);
  Assert.IsTrue(Supports(LTree, IUnitSymbolFacts, LPort));
  LFacts := LPort.GetSymbolFacts;
  LFound := False;
  for LDeclaration in LFacts.Declarations do
    if LDeclaration.Name = 'Value' then
    begin
      Assert.AreEqual(Ord(skParameter), Ord(LDeclaration.Kind));
      Assert.AreEqual(FSource, LDeclaration.SourcePath);
      Assert.AreEqual(2, LDeclaration.NormalizedLine);
      Assert.IsTrue(LDeclaration.NormalizedColumn > 0);
      LFound := True;
    end;
  Assert.IsTrue(LFound);
  Assert.IsTrue(Length(LFacts.References) > 0);
  LFacts.Declarations[0].Name := 'changed';
  Assert.AreEqual('Run', LPort.GetSymbolFacts.Declarations[0].Name);
end;

procedure TSymbolBindingTests.IncludeDeclarationsUseExpandedOrder;
var LResult: TUnitAnalysisResult;
begin
  TFile.WriteAllText(TPath.Combine(FDirectory, 'Local.inc'), 'var Clash: Integer;', TEncoding.UTF8);
  LResult := Analyze('implementation procedure Run; {$I Local.inc} begin Inc(Clash); end;');
  Assert.AreEqual<NativeInt>(1, Length(LResult.UnusedUnits));
  Assert.AreEqual('Dependency', LResult.UnusedUnits[0]);
end;

procedure TSymbolBindingTests.DeclarationStartInIncludeKeepsSource(AScenario: Integer);
const
  Prefixes: array[0..3] of string = (
    'unit Consumer; interface implementation ', 'unit Consumer; interface ',
    'unit Consumer; interface ', 'unit Consumer; interface type TLocal = class public ');
  Includes: array[0..3] of string = ('procedure Run;', 'procedure Run',
    'type TLocal = class', 'procedure Run');
  Suffixes: array[0..3] of string = (' begin end; end.', '; implementation end.',
    ' end; implementation end.', '; end; implementation end.');
var LInclude, LExpectedName: string; LTree: IUnitSyntaxTree; LPort: IUnitSymbolFacts;
  LDeclaration: TSymbolDeclaration; LFound: Boolean;
begin
  LInclude := TPath.Combine(FDirectory, 'Start.inc');
  TFile.WriteAllText(LInclude, Includes[AScenario], TEncoding.UTF8);
  TFile.WriteAllText(FSource, Prefixes[AScenario] + '{$I Start.inc}' + Suffixes[AScenario], TEncoding.UTF8);
  LTree := FParser.ParseFile(FSource);
  Assert.IsTrue(Supports(LTree, IUnitSymbolFacts, LPort));
  LExpectedName := 'Run';
  if AScenario = 2 then
    LExpectedName := 'TLocal';
  LFound := False;
  for LDeclaration in LPort.GetSymbolFacts.Declarations do
    if LDeclaration.Name = LExpectedName then
    begin
      Assert.AreEqual(LInclude, LDeclaration.SourcePath);
      Assert.AreEqual(1, LDeclaration.NormalizedLine);
      LFound := True;
    end;
  Assert.IsTrue(LFound);
end;

function TSymbolBindingTests.ReadFacts(const ABody: string): TUnitSymbolFacts;
var LTree: IUnitSyntaxTree; LPort: IUnitSymbolFacts;
begin
  TFile.WriteAllText(FSource, 'unit Consumer; interface ' + ABody + ' end.', TEncoding.UTF8);
  LTree := FParser.ParseFile(FSource);
  Assert.IsTrue(Supports(LTree, IUnitSymbolFacts, LPort));
  Result := LPort.GetSymbolFacts;
end;

function TSymbolBindingTests.FindDeclaration(const AFacts: TUnitSymbolFacts;
  const AName: string; ASection: TSymbolSection): TSymbolDeclaration;
var LDeclaration: TSymbolDeclaration;
begin
  for LDeclaration in AFacts.Declarations do
    if (LDeclaration.Name = AName) and (LDeclaration.Section = ASection) then
      Exit(LDeclaration);
  Result := Default(TSymbolDeclaration);
  Assert.Fail('Missing declaration: ' + AName);
end;

procedure TSymbolBindingTests.DeclarationsRetainExplicitVisibility(
  const AVisibility: string; AExpected: Integer);
var LFacts: TUnitSymbolFacts; LDeclaration: TSymbolDeclaration;
begin
  LFacts := ReadFacts('{$M+} type TContainer = class ' + AVisibility +
    ' procedure Visible(Input: Integer); end; implementation ' +
    'procedure TContainer.Visible(Input: Integer); var Local: Integer; begin end;');
  LDeclaration := FindDeclaration(LFacts, 'Visible', ssInterface);
  Assert.AreEqual<Integer>(AExpected, Ord(LDeclaration.Visibility));
  Assert.AreEqual(FSource, LDeclaration.SourcePath);
  Assert.IsTrue(LDeclaration.NormalizedColumn > 0);
  Assert.AreEqual(Ord(svUnit), Ord(FindDeclaration(LFacts, 'TContainer', ssInterface).Visibility));
  Assert.AreEqual(Ord(svLocal), Ord(FindDeclaration(LFacts, 'Input', ssInterface).Visibility));
  Assert.AreEqual(Ord(svLocal), Ord(FindDeclaration(LFacts, 'Input', ssImplementation).Visibility));
  Assert.AreEqual(Ord(svLocal), Ord(FindDeclaration(LFacts, 'Local', ssImplementation).Visibility));
  Assert.AreEqual(Ord(svUnknown), Ord(FindDeclaration(LFacts, 'TContainer.Visible', ssImplementation).Visibility));
end;

procedure TSymbolBindingTests.ImplicitAndOutOfLineAccessStayUnknown;
var LFacts: TUnitSymbolFacts;
begin
  LFacts := ReadFacts('type TContainer = class procedure Implicit; end; ' +
    'implementation procedure TContainer.Implicit; begin end; const InternalValue = 1;');
  Assert.AreEqual(Ord(svUnknown), Ord(FindDeclaration(LFacts, 'Implicit', ssInterface).Visibility));
  Assert.AreEqual(Ord(svUnknown), Ord(FindDeclaration(LFacts, 'TContainer.Implicit', ssImplementation).Visibility));
  Assert.AreEqual(Ord(svUnit), Ord(FindDeclaration(LFacts, 'InternalValue', ssImplementation).Visibility));
end;

procedure TSymbolBindingTests.InlineLifecycleDeclarationRetainsSection(
  const APhase: string; AExpected: Integer);
var LFacts: TUnitSymbolFacts; LDeclaration: TSymbolDeclaration; LPrefix: string;
begin
  LPrefix := 'implementation ';
  if APhase = 'finalization' then
    LPrefix := LPrefix + 'initialization ';
  LFacts := ReadFacts(LPrefix + APhase + ' begin var LocalValue := 1; end;');
  LDeclaration := FindDeclaration(LFacts, 'LocalValue', TSymbolSection(AExpected));
  Assert.AreEqual(Ord(svLocal), Ord(LDeclaration.Visibility));
end;

initialization
  TDUnitX.RegisterTestFixture(TSymbolBindingTests);
end.
