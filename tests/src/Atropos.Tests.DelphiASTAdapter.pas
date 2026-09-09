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

initialization
  TDUnitX.RegisterTestFixture(TDelphiASTAdapterTests);

end.


