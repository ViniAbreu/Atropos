unit Atropos.Tests.DelphiASTAdapter;

interface
uses
  Atropos.Core.Domain, Atropos.Core.Analysis, Atropos.Core.Ports, Atropos.Adapters.DelphiAST, DUnitX.TestFramework, System.SysUtils, System.Classes, System.IOUtils;

type
  [TestFixture]
  TDelphiASTAdapterTests = class
  private
    FParser: IASTParser;
    FTestFile: string;
    FTestDirectory: string;
    procedure CreateMockPasFile;
    procedure WriteUtf8BomFile(const ASource: string);
    function AnalyzeHelperSource(const ASource: string; ACompeting: Boolean = False): TUnitAnalysisResult;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    
    [Test]
    [TestCase('Parse file', 'Should successfully parse a valid Delphi file')]
    procedure Test_ParseFile;
    [Test]
    [TestCase('File not found exception', 'Should throw an exception if the specified file does not exist')]
    procedure Test_FileNotFound_ThrowsException;
    [Test]
    procedure Test_ParseUtf8BomFileAtExactBufferBoundary;
    [Test]
    procedure Test_ParseModernMultilineStrings;
    [TestCase('Initialization', 'initialization,0')]
    [TestCase('Finalization', 'initialization finalization,1')]
    [TestCase('Legacy', 'begin,2')]
    procedure LifecycleReferencesAreOutsideInterface(const ASection: string; APhase: Integer);
    [Test] procedure ProcedureBodiesAreNotLifecycleSections;
    [Test] procedure LifecycleFactsKeepBothPhasesAndSource;
    [TestCase('InitInclude', 'initialization')]
    [TestCase('FinalInclude', 'initialization finalization')]
    [TestCase('LegacyInclude', 'begin')]
    procedure LifecycleIncludeRetainsSourceProvenance(const ASection: string);
    [Test] procedure ProgramBodyIsNotUnitInitialization;
    [Test] procedure HelperFactsDescribeReceiverAndVisibility;
    [Test] procedure HelperFactsExcludeOrdinaryAndImplementationTypes;
    [Test] procedure HelperFactsAreStableAcrossRepeatedReads;
    [TestCase('StringParameter', '0,1')]
    [TestCase('UnrelatedClass', '1,0')]
    [TestCase('SeparateRoutines', '2,1')]
    [TestCase('ParameterShadowsGlobal', '3,0')]
    [TestCase('ChainedReceiver', '4,2')]
    [TestCase('BareCall', '5,2')]
    [TestCase('LocalAlias', '6,2')]
    [TestCase('WithScope', '7,2')]
    [TestCase('LifecycleVariable', '8,1')]
    [TestCase('ClassFieldShadowsGlobal', '9,2')]
    procedure HelperDecisionsUseReceiverScopes(AScenario, AAction: Integer);
    [Test] procedure CompetingHelpersPreserveBothImports;
    [TestCase('SystemCodePage', '0')]
    [TestCase('Utf8NoBom', '1')]
    [TestCase('Utf8Bom', '2')]
    [TestCase('Utf16Bom', '3')]
    procedure SourceEncodingPreservesTextAndFacts(AEncoding: Integer);
    [TestCase('Constant', '0')]
    [TestCase('Type', '1')]
    [TestCase('Field', '2')]
    [TestCase('Routine', '3')]
    [TestCase('Parameter', '4')]
    [TestCase('Local', '5')]
    procedure UnsafeIdentifierRetainsDeclaration(AScenario: Integer);
    [TestCase('FieldAttribute', '0')]
    [TestCase('ParameterAttribute', '1')]
    [TestCase('ResultAttribute', '2')]
    procedure UnsafeAttributesRemainParsable(AScenario: Integer);
  end;

implementation

uses Atropos.Adapters.DelphiSource;

procedure TDelphiASTAdapterTests.UnsafeAttributesRemainParsable(AScenario: Integer);
const Sources: array[0..2] of string = (
  'type TBox = class private [Unsafe] FValue: IInterface; end; implementation',
  'procedure Run([Unsafe] Value: IInterface); implementation procedure Run([Unsafe] Value: IInterface); begin end;',
  '[Result: Unsafe] function GetValue: IInterface; implementation function GetValue: IInterface; begin Result := nil; end;');
var LTree: IUnitSyntaxTree;
begin
  TFile.WriteAllText(FTestFile, 'unit MockUnit; interface ' + Sources[AScenario] + ' end.', TEncoding.UTF8);
  LTree := FParser.ParseFile(FTestFile);
  Assert.AreEqual('MockUnit', LTree.GetUnitName);
  Assert.IsTrue(Length(LTree.GetExportedIdentifiers) > 0);
end;

procedure TDelphiASTAdapterTests.UnsafeIdentifierRetainsDeclaration(AScenario: Integer);
const Sources: array[0..5] of string = (
  'const Unsafe = 1; implementation',
  'type Unsafe = Integer; implementation',
  'type TBox = class Unsafe: Integer; end; implementation',
  'procedure Unsafe; implementation procedure Unsafe; begin end;',
  'procedure Run(Unsafe: Integer); implementation procedure Run(Unsafe: Integer); begin Inc(Unsafe); end;',
  'implementation procedure Run; var Unsafe: Integer; begin Unsafe := 1; end;');
var LTree: IUnitSyntaxTree; LPort: IUnitSymbolFacts; LDeclaration: TSymbolDeclaration; LFound: Boolean;
begin
  TFile.WriteAllText(FTestFile, 'unit MockUnit; interface ' + Sources[AScenario] + ' end.', TEncoding.UTF8);
  LTree := FParser.ParseFile(FTestFile);
  Assert.IsTrue(Supports(LTree, IUnitSymbolFacts, LPort));
  LFound := False;
  for LDeclaration in LPort.GetSymbolFacts.Declarations do
    if SameText(LDeclaration.Name, 'Unsafe') then LFound := True;
  Assert.IsTrue(LFound, 'Unsafe declaration must keep its original identity.');
  if AScenario in [0, 1, 3] then
    Assert.Contains<string>(LTree.GetExportedIdentifiers, 'Unsafe');
end;

procedure TDelphiASTAdapterTests.SourceEncodingPreservesTextAndFacts(AEncoding: Integer);
var LSource: string; LEncoding: TEncoding; LBytes, LAfter: TBytes;
  LTree: IUnitSyntaxTree; LContent: TDelphiSourceContent;
begin
  LSource := 'unit MockUnit; interface {a' + Char($E7) + Char($E3) + 'o} ' +
    'type TKept = class end; implementation end.';
  LEncoding := TEncoding.Default;
  if AEncoding in [1, 2] then
    LEncoding := TEncoding.UTF8;
  if AEncoding = 3 then
    LEncoding := TEncoding.Unicode;
  LBytes := LEncoding.GetBytes(LSource);
  if AEncoding in [2, 3] then
    LBytes := LEncoding.GetPreamble + LBytes;
  TFile.WriteAllBytes(FTestFile, LBytes);
  LContent := TDelphiSourceReader.Read(FTestFile);
  Assert.AreEqual(LSource, LContent.Text);
  LTree := FParser.ParseFile(FTestFile);
  Assert.IsTrue(Length(LTree.GetExportedIdentifiers) > 0);
  Assert.AreEqual('TKept', LTree.GetExportedIdentifiers[0]);
  LAfter := TFile.ReadAllBytes(FTestFile);
  Assert.AreEqual(Length(LBytes), Length(LAfter));
  Assert.IsTrue(CompareMem(@LBytes[0], @LAfter[0], Length(LBytes)));
end;

procedure TDelphiASTAdapterTests.CreateMockPasFile;
var
  LList: TStringList;
begin
  LList := TStringList.Create;
  try
    LList.Add('unit MockUnit;');
    LList.Add('interface');
    LList.Add('uses System.SysUtils;');
    LList.Add('type TMyClass = class end;');
    LList.Add('implementation');
    LList.Add('uses System.Classes;');
    LList.Add('var x: TStringList;');
    LList.Add('end.');
    LList.SaveToFile(FTestFile, TEncoding.UTF8);
  finally
    LList.Free;
  end;
end;

procedure TDelphiASTAdapterTests.WriteUtf8BomFile(const ASource: string);
var
  LBytes: TBytes;
  LPayload: TBytes;
  LPreamble: TBytes;
begin
  LPayload := TEncoding.UTF8.GetBytes(ASource);
  LPreamble := TEncoding.UTF8.GetPreamble;
  SetLength(LBytes, Length(LPreamble) + Length(LPayload));
  Move(LPreamble[0], LBytes[0], Length(LPreamble));
  Move(LPayload[0], LBytes[Length(LPreamble)], Length(LPayload));
  TFile.WriteAllBytes(FTestFile, LBytes);
end;

procedure TDelphiASTAdapterTests.Setup;
begin
  FParser := TDelphiASTAdapter.Create;
  FTestDirectory := TPath.Combine(TPath.GetTempPath, 'Atropos-AST-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FTestDirectory);
  FTestFile := TPath.Combine(FTestDirectory, 'MockUnit.pas');
  CreateMockPasFile;
end;

procedure TDelphiASTAdapterTests.TearDown;
begin
  FParser := nil;
  if not TPath.GetFullPath(FTestDirectory).StartsWith(
    TPath.Combine(TPath.GetTempPath, 'Atropos-AST-'), True) then
    raise Exception.Create('Unexpected parser test directory.');
  if TDirectory.Exists(FTestDirectory) then
    TDirectory.Delete(FTestDirectory, True);
end;

procedure TDelphiASTAdapterTests.Test_ParseFile;
var
  LTree: IUnitSyntaxTree;
  LIntfUses, LImplUses: TArray<string>;
begin
  LTree := FParser.ParseFile(FTestFile);
  Assert.IsNotNull(LTree, 'A árvore gerada não deveria ser nula');
  Assert.AreEqual('MockUnit', LTree.GetUnitName);
  
  LIntfUses := LTree.GetInterfaceUses;
  Assert.AreEqual(1, Integer(Length(LIntfUses)));
  Assert.AreEqual('System.SysUtils', LIntfUses[0]);

  LImplUses := LTree.GetImplementationUses;
  Assert.AreEqual(1, Integer(Length(LImplUses)));
  Assert.AreEqual('System.Classes', LImplUses[0]);
end;

procedure TDelphiASTAdapterTests.Test_FileNotFound_ThrowsException;
begin
  Assert.WillRaise(
    procedure
    begin
      FParser.ParseFile('C:\invalid_path_to_a_file_that_does_not_exist.pas');
    end,
    EASTParserException
  );
end;

procedure TDelphiASTAdapterTests.Test_ParseUtf8BomFileAtExactBufferBoundary;
const
  CFileSize = 57343;
var
  LPaddingLength: Integer;
  LSource: string;
  LTree: IUnitSyntaxTree;
begin
  LSource := 'unit Utf8BomUnit;' + sLineBreak +
    'interface' + sLineBreak +
    'implementation' + sLineBreak;
  LPaddingLength := CFileSize - Length(TEncoding.UTF8.GetPreamble) -
    Length(TEncoding.UTF8.GetBytes(LSource + '{}' + sLineBreak + 'end.'));
  LSource := LSource + '{' + StringOfChar('x', LPaddingLength) + '}' +
    sLineBreak + 'end.';
  WriteUtf8BomFile(LSource);

  Assert.AreEqual<Int64>(CFileSize, TFile.GetSize(FTestFile));
  LTree := FParser.ParseFile(FTestFile);
  Assert.AreEqual('Utf8BomUnit', LTree.GetUnitName);
end;

procedure TDelphiASTAdapterTests.Test_ParseModernMultilineStrings;
var
  LImplementationIdentifiers: TArray<string>;
  LSource: string;
  LTree: IUnitSyntaxTree;
begin
  LSource := 'unit MultilineStringUnit;' + sLineBreak +
    'interface' + sLineBreak +
    'implementation' + sLineBreak +
    'procedure Run;' + sLineBreak +
    'begin' + sLineBreak +
    '  ExecuteSQL(' + '''''''' + sLineBreak +
    '    select ''System.SysUtils'' from sample' + sLineBreak +
    '  ' + '''''''' + ', CreateParameters);' + sLineBreak +
    'end;' + sLineBreak +
    'end.';
  WriteUtf8BomFile(LSource);

  LTree := FParser.ParseFile(FTestFile);
  Assert.AreEqual('MultilineStringUnit', LTree.GetUnitName);
  LImplementationIdentifiers := LTree.GetIdentifiersUsedInImplementation;
  Assert.Contains(LImplementationIdentifiers, 'ExecuteSQL');
  Assert.Contains(LImplementationIdentifiers, 'CreateParameters');
  Assert.DoesNotContain(LImplementationIdentifiers, 'System.SysUtils');
end;

procedure TDelphiASTAdapterTests.LifecycleReferencesAreOutsideInterface(
  const ASection: string; APhase: Integer);
var LTree: IUnitSyntaxTree; LFacts: IUnitLifecycleFacts;
  LSection: TLifecycleSection; LFound: Boolean;
begin
  WriteUtf8BomFile('unit Consumer; interface uses Provider; implementation ' +
    ASection + ' Boot; end.');
  LTree := FParser.ParseFile(FTestFile);
  Assert.Contains<string>(LTree.GetIdentifiersUsedInImplementation, 'Boot');
  Assert.AreEqual<NativeInt>(0, Length(LTree.GetIdentifiersUsedInInterface));
  Assert.IsTrue(LTree.HasInitializationSection, 'Direct lifecycle effect must preserve the provider');
  Assert.IsTrue(Supports(LTree, IUnitLifecycleFacts, LFacts));
  LFound := False;
  for LSection in LFacts.GetLifecycleSections do
    if Ord(LSection.Phase) = APhase then
      LFound := True;
  Assert.IsTrue(LFound, 'Expected lifecycle phase');
end;

procedure TDelphiASTAdapterTests.ProcedureBodiesAreNotLifecycleSections;
var LTree: IUnitSyntaxTree; LFacts: IUnitLifecycleFacts;
begin
  WriteUtf8BomFile('unit Consumer; interface procedure Boot; implementation ' +
    'procedure Boot; begin end; end.');
  LTree := FParser.ParseFile(FTestFile);
  Assert.IsFalse(LTree.HasInitializationSection);
  Assert.IsTrue(Supports(LTree, IUnitLifecycleFacts, LFacts));
  Assert.AreEqual<NativeInt>(0, Length(LFacts.GetLifecycleSections));
end;

procedure TDelphiASTAdapterTests.LifecycleFactsKeepBothPhasesAndSource;
var LTree: IUnitSyntaxTree; LFacts: IUnitLifecycleFacts;
  LSections: TArray<TLifecycleSection>;
begin
  WriteUtf8BomFile('unit Consumer;' + sLineBreak + 'interface' + sLineBreak +
    'implementation' + sLineBreak + 'initialization' + sLineBreak +
    'Boot;' + sLineBreak + 'finalization' + sLineBreak + 'Shutdown;' + sLineBreak + 'end.');
  LTree := FParser.ParseFile(FTestFile);
  Assert.IsTrue(Supports(LTree, IUnitLifecycleFacts, LFacts));
  LSections := LFacts.GetLifecycleSections;
  Assert.AreEqual<NativeInt>(2, Length(LSections));
  Assert.AreEqual(Ord(lpInitialization), Ord(LSections[0].Phase));
  Assert.AreEqual(Ord(lpFinalization), Ord(LSections[1].Phase));
  Assert.AreEqual(FTestFile, LSections[0].SourcePath);
  Assert.AreEqual(4, LSections[0].NormalizedLine);
  Assert.AreEqual(6, LSections[1].NormalizedLine);
  Assert.Contains<string>(LTree.GetIdentifiersUsedInImplementation, 'Boot');
  Assert.Contains<string>(LTree.GetIdentifiersUsedInImplementation, 'Shutdown');
  LSections[0].SourcePath := 'changed copy';
  Assert.AreEqual(FTestFile, LFacts.GetLifecycleSections[0].SourcePath);
end;

procedure TDelphiASTAdapterTests.LifecycleIncludeRetainsSourceProvenance(const ASection: string);
var LTree: IUnitSyntaxTree; LFacts: IUnitLifecycleFacts; LInclude: string;
  LFact: TLifecycleSection;
begin
  LInclude := TPath.ChangeExtension(FTestFile, '.inc');
  TFile.WriteAllText(LInclude, ASection + ' Boot;', TEncoding.UTF8);
  try
    WriteUtf8BomFile('unit Consumer; interface implementation {$I MockUnit.inc} end.');
    LTree := FParser.ParseFile(FTestFile);
    Assert.IsTrue(Supports(LTree, IUnitLifecycleFacts, LFacts));
    for LFact in LFacts.GetLifecycleSections do
      Assert.AreEqual(LInclude, LFact.SourcePath);
    Assert.Contains<string>(LTree.GetIdentifiersUsedInImplementation, 'Boot');
  finally
    TFile.Delete(LInclude);
  end;
end;

procedure TDelphiASTAdapterTests.ProgramBodyIsNotUnitInitialization;
var LTree: IUnitSyntaxTree;
begin
  WriteUtf8BomFile('program Sample; begin end.');
  LTree := FParser.ParseFile(FTestFile);
  Assert.IsFalse(LTree.HasInitializationSection);
end;
procedure TDelphiASTAdapterTests.HelperFactsDescribeReceiverAndVisibility;
var LTree: IUnitSyntaxTree; LFacts: IUnitHelperFacts;
  LItems: TArray<THelperDeclaration>;
begin
  WriteUtf8BomFile('unit Sample; interface' + sLineBreak +
    'type TStringTool = record helper for string' + sLineBreak +
    'function Twist: string;' + sLineBreak +
    'private procedure Hidden;' + sLineBreak +
    'public property Size: Integer read GetSize; end;' + sLineBreak +
    'TObjectTool = class helper for TObject protected procedure Polish; end;' + sLineBreak +
    'implementation end.');
  LTree := FParser.ParseFile(FTestFile);
  Assert.IsTrue(Supports(LTree, IUnitHelperFacts, LFacts));
  LItems := LFacts.GetHelperDeclarations;
  Assert.AreEqual<NativeInt>(4, Length(LItems));
  Assert.AreEqual('TStringTool', LItems[0].HelperName);
  Assert.AreEqual('string', LItems[0].ReceiverType);
  Assert.AreEqual('Twist', LItems[0].MemberName);
  Assert.AreEqual('public', LItems[0].Visibility);
  Assert.AreEqual(Ord(hmMethod), Ord(LItems[0].Kind));
  Assert.AreEqual(FTestFile, LItems[0].SourcePath);
  Assert.AreEqual(3, LItems[0].NormalizedLine);
  Assert.IsTrue(LItems[0].NormalizedColumn > 0);
  Assert.AreEqual('private', LItems[1].Visibility);
  Assert.AreEqual('Size', LItems[2].MemberName);
  Assert.AreEqual(Ord(hmProperty), Ord(LItems[2].Kind));
  Assert.AreEqual('TObjectTool', LItems[3].HelperName);
  Assert.AreEqual('TObject', LItems[3].ReceiverType);
  Assert.AreEqual('protected', LItems[3].Visibility);
end;

procedure TDelphiASTAdapterTests.HelperFactsExcludeOrdinaryAndImplementationTypes;
var LTree: IUnitSyntaxTree; LFacts: IUnitHelperFacts;
begin
  WriteUtf8BomFile('unit Sample; interface ' +
    'type TAlias = Integer; TOrdinary = class procedure Twist; end; ' +
    'procedure Run; implementation ' +
    'type TPrivateTool = record helper for string procedure Hidden; end; ' +
    'procedure Run; begin end; end.');
  LTree := FParser.ParseFile(FTestFile);
  Assert.IsTrue(Supports(LTree, IUnitHelperFacts, LFacts));
  Assert.AreEqual<NativeInt>(0, Length(LFacts.GetHelperDeclarations));
end;

procedure TDelphiASTAdapterTests.HelperFactsAreStableAcrossRepeatedReads;
var LTree: IUnitSyntaxTree; LFacts: IUnitHelperFacts;
  LItems: TArray<THelperDeclaration>;
begin
  WriteUtf8BomFile('unit Sample; interface type TTool = class helper for TObject ' +
    'public procedure Polish; end; implementation ' +
    'procedure TTool.Polish; begin end; end.');
  LTree := FParser.ParseFile(FTestFile);
  Assert.IsTrue(Supports(LTree, IUnitHelperFacts, LFacts));
  LItems := LFacts.GetHelperDeclarations;
  Assert.AreEqual<NativeInt>(1, Length(LItems));
  LItems[0].ReceiverType := 'changed';
  LItems := LFacts.GetHelperDeclarations;
  Assert.AreEqual<NativeInt>(1, Length(LItems));
  Assert.AreEqual('TObject', LItems[0].ReceiverType);
  Assert.AreEqual('Polish', LItems[0].MemberName);
end;

function TDelphiASTAdapterTests.AnalyzeHelperSource(const ASource: string;
  ACompeting: Boolean): TUnitAnalysisResult;
var LContext: TProjectContext; LAnalyzer: TAnalyzeUnitUses; LTree: IUnitSyntaxTree;
begin
  LContext := TProjectContext.Create;
  LAnalyzer := TAnalyzeUnitUses.Create;
  try
    WriteUtf8BomFile('unit Helpers; interface type TTool = record helper for string ' +
      'function Twist: string; end; implementation end.');
    LTree := FParser.ParseFile(FTestFile);
    LContext.RegisterUnitExports('Helpers', LTree.GetExportedIdentifiers);
    LContext.RegisterUnitDependencies('Helpers', []);
    if ACompeting then
    begin
      LContext.RegisterUnitExports('OtherHelpers', LTree.GetExportedIdentifiers);
      LContext.RegisterUnitDependencies('OtherHelpers', []);
    end;
    WriteUtf8BomFile(ASource);
    LTree := FParser.ParseFile(FTestFile);
    Result := LAnalyzer.Execute(LTree, LContext);
  finally
    LAnalyzer.Free;
    LContext.Free;
  end;
end;

procedure TDelphiASTAdapterTests.HelperDecisionsUseReceiverScopes(AScenario, AAction: Integer);
const
  Sources: array[0..9] of string = (
    'implementation procedure Run(Value: string); begin Value.Twist; end;',
    'type TLocal = class function Twist: string; end; implementation ' +
      'procedure Run(Value: TLocal); begin Value.Twist; end;',
    'type TLocal = class function Twist: string; end; implementation ' +
      'procedure A(Value: TLocal); begin Value.Twist; end; ' +
      'procedure B(Value: string); begin Value.Twist; end;',
    'type TLocal = class function Twist: string; end; var Value: string; implementation ' +
      'procedure Run(Value: TLocal); begin Value.Twist; end;',
    'implementation procedure Run(Value: TObject); begin Value.Child.Twist; end;',
    'implementation procedure Run; begin Twist; end;',
    'implementation procedure Run; type TAlias = string; var Value: TAlias; begin Value.Twist; end;',
    'implementation procedure Run(Value: string; Other: TObject); begin with Other do Value.Twist; end;',
    'var Value: string; implementation initialization Value.Twist;',
    'type TLocal = class function Twist: string; end; ' +
      'TOwner = class Value: string; procedure Run; end; var Value: TLocal; ' +
      'implementation procedure TOwner.Run; begin Value.Twist; end;');
var LResult: TUnitAnalysisResult;
begin
  LResult := AnalyzeHelperSource('unit Sample; interface uses Helpers; ' + Sources[AScenario] + ' end.');
  Assert.AreEqual<NativeInt>(1, Length(LResult.Decisions));
  if AAction = 0 then
    Assert.AreEqual(Ord(daRemove), Ord(LResult.Decisions[0].Action));
  if AAction = 1 then
    Assert.AreEqual(Ord(daMoveToImplementation), Ord(LResult.Decisions[0].Action));
  if AAction = 2 then
  begin
    Assert.AreEqual(Ord(daPreserve), Ord(LResult.Decisions[0].Action));
    Assert.AreEqual(Ord(dsUnknown), Ord(LResult.Decisions[0].State));
  end;
end;

procedure TDelphiASTAdapterTests.CompetingHelpersPreserveBothImports;
var LResult: TUnitAnalysisResult; LDecision: TDependencyDecision;
begin
  LResult := AnalyzeHelperSource('unit Sample; interface uses Helpers, OtherHelpers; ' +
    'implementation procedure Run(Value: string); begin Value.Twist; end; end.', True);
  Assert.AreEqual<NativeInt>(2, Length(LResult.Decisions));
  for LDecision in LResult.Decisions do
  begin
    Assert.AreEqual(Ord(daPreserve), Ord(LDecision.Action));
    Assert.AreEqual(Ord(dsUnknown), Ord(LDecision.State));
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDelphiASTAdapterTests);

end.


