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

initialization
  TDUnitX.RegisterTestFixture(TDelphiASTAdapterTests);

end.


