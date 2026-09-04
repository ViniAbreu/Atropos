unit Atropos.Tests.CompilerDirectives;

interface
uses
  Atropos.Core.Ports, Atropos.Adapters.DelphiAST, DUnitX.TestFramework, System.SysUtils, System.Classes, System.IOUtils;

type
  [TestFixture]
  TCompilerDirectivesTests = class
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
    [TestCase('Ignore DCU and directives', 'Should ignore .dcu files and compiler directives in uses clauses')]
    procedure Test_IgnoreDcu_And_Directives;
  end;

implementation

procedure TCompilerDirectivesTests.CreateMockPasFile;
var
  LList: TStringList;
begin
  LList := TStringList.Create;
  try
    LList.Add('unit MockDirectivesUnit;');
    LList.Add('interface');
    LList.Add('uses');
    LList.Add('  System.SysUtils,');
    LList.Add('  MyUnit.dcu,');
    LList.Add('  {$IFDEF MSWINDOWS}');
    LList.Add('  Winapi.Windows,');
    LList.Add('  {$ENDIF}');
    LList.Add('  System.Classes;');
    LList.Add('type TMyClass = class end;');
    LList.Add('implementation');
    LList.Add('end.');
    LList.SaveToFile(FTestFile, TEncoding.UTF8);
  finally
    LList.Free;
  end;
end;

procedure TCompilerDirectivesTests.Setup;
begin
  FParser := TDelphiASTAdapter.Create;
  FTestFile := TPath.Combine(TPath.GetTempPath, 'MockDirectivesUnit.pas');
  CreateMockPasFile;
end;

procedure TCompilerDirectivesTests.TearDown;
begin
  if TFile.Exists(FTestFile) then
    TFile.Delete(FTestFile);
  FParser := nil;
end;

procedure TCompilerDirectivesTests.Test_IgnoreDcu_And_Directives;
var
  LTree: IUnitSyntaxTree;
  LIntfUses: TArray<string>;
begin
  LTree := FParser.ParseFile(FTestFile);
  LIntfUses := LTree.GetInterfaceUses;
  
  // Como .dcu deve ser ignorado e Winapi.Windows est dentro do {$IFDEF} mas o parser foi atualizado para iterar recursivamente,
  // a lista final deve conter System.SysUtils, Winapi.Windows e System.Classes
  Assert.AreEqual(3, Integer(Length(LIntfUses)));
  Assert.AreEqual('System.SysUtils', LIntfUses[0]);
  Assert.AreEqual('Winapi.Windows', LIntfUses[1]);
  Assert.AreEqual('System.Classes', LIntfUses[2]);
end;

initialization
  TDUnitX.RegisterTestFixture(TCompilerDirectivesTests);

end.


