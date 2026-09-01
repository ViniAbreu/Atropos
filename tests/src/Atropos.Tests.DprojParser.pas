unit Atropos.Tests.DprojParser;

interface
uses
  Atropos.Core.Ports, Atropos.Adapters.ProjectParser, DUnitX.TestFramework, System.SysUtils, System.Classes, System.IOUtils;

type
  [TestFixture]
  TDprojParserTests = class
  private
    FParser: IProjectParser;
    FTestDprojPath: string;
    procedure CreateMockDproj;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    
    [Test]
    [TestCase('Get search paths', 'Should correctly extract search paths from project file')]
    procedure Test_GetSearchPaths;
    [Test]
    [TestCase('Get project units', 'Should list all units belonging to the project')]
    procedure Test_GetProjectUnits;
  end;

implementation

procedure TDprojParserTests.CreateMockDproj;
var
  LXML: TStringList;
begin
  LXML := TStringList.Create;
  try
    LXML.Add('<?xml version="1.0" encoding="utf-8"?>');
    LXML.Add('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">');
    LXML.Add('  <PropertyGroup>');
    LXML.Add('    <DCC_UnitSearchPath>C:\Path1;..\Path2;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>');
    LXML.Add('  </PropertyGroup>');
    LXML.Add('  <ItemGroup>');
    LXML.Add('    <DCCReference Include="Unit1.pas" />');
    LXML.Add('    <DCCReference Include="Unit2.pas">');
    LXML.Add('      <Form>Form2</Form>');
    LXML.Add('    </DCCReference>');
    LXML.Add('    <DCCReference Include="Unit3.dfm" />');
    LXML.Add('  </ItemGroup>');
    LXML.Add('</Project>');
    LXML.SaveToFile(FTestDprojPath, TEncoding.UTF8);
  finally
    LXML.Free;
  end;
end;

procedure TDprojParserTests.Setup;
begin
  FParser := TDprojParserAdapter.Create;
  FTestDprojPath := TPath.Combine(TPath.GetTempPath, 'TestProject.dproj');
  CreateMockDproj;
end;

procedure TDprojParserTests.TearDown;
begin
  if TFile.Exists(FTestDprojPath) then
    TFile.Delete(FTestDprojPath);
  FParser := nil;
end;

procedure TDprojParserTests.Test_GetSearchPaths;
var
  LPaths: TArray<string>;
begin
  LPaths := FParser.GetSearchPaths(FTestDprojPath);
  Assert.AreEqual(2, Length(LPaths));
  Assert.AreEqual('C:\Path1', LPaths[0]);
  Assert.AreEqual('..\Path2', LPaths[1]);
end;

procedure TDprojParserTests.Test_GetProjectUnits;
var
  LUnits: TArray<string>;
begin
  LUnits := FParser.GetProjectUnits(FTestDprojPath);
  Assert.AreEqual(2, Length(LUnits));
  // dfm should be ignored
  Assert.AreEqual('Unit1.pas', LUnits[0]);
  Assert.AreEqual('Unit2.pas', LUnits[1]);
end;

initialization
  TDUnitX.RegisterTestFixture(TDprojParserTests);

end.


