unit Atropos.Tests.DelphiASTAdapter;

interface
uses
  Atropos.Core.Ports, Atropos.Adapters.DelphiAST, DUnitX.TestFramework, System.SysUtils, System.Classes, System.IOUtils;

type
  [TestFixture]
  TDelphiASTAdapterTests = class
  private
    FParser: IASTParser;
    FTestFile: string;
    procedure CreateMockPasFile;
    procedure WriteUtf8BomFile(const ASource: string);
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
  end;

implementation

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
  FTestFile := TPath.Combine(TPath.GetTempPath, 'MockUnit.pas');
  CreateMockPasFile;
end;

procedure TDelphiASTAdapterTests.TearDown;
begin
  if TFile.Exists(FTestFile) then
    TFile.Delete(FTestFile);
  FParser := nil;
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
initialization
  TDUnitX.RegisterTestFixture(TDelphiASTAdapterTests);

end.


