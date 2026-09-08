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
    [Test]
    procedure SelectsOnlyActiveConfigurationAndPlatform;
    [Test]
    procedure ExpandsInheritedSearchPathInDeclarationOrder;
    [Test]
    procedure EvaluatesDelphiGeneratedBooleanConditions;
    [Test]
    procedure RespectsNestedLogicalParentheses;
    [Test]
    procedure EvaluatesExistsRelativeToProjectDirectory;
    [Test]
    procedure ExpandsPropertyChainsBeyondFiveLevels;
    [Test]
    procedure ReportsUnsupportedConditions;
    [Test]
    procedure ReportsCyclicPropertyExpansion;
    [Test]
    procedure ParsesActivePathsFromRepositoryProject;
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
  Assert.AreEqual(2, Integer(Length(LPaths)));
  Assert.AreEqual('C:\Path1', LPaths[0]);
  Assert.AreEqual('..\Path2', LPaths[1]);
end;

procedure TDprojParserTests.Test_GetProjectUnits;
var
  LUnits: TArray<string>;
begin
  LUnits := FParser.GetProjectUnits(FTestDprojPath);
  Assert.AreEqual(2, Integer(Length(LUnits)));
  // dfm should be ignored
  Assert.AreEqual('Unit1.pas', LUnits[0]);
  Assert.AreEqual('Unit2.pas', LUnits[1]);
end;

procedure TDprojParserTests.SelectsOnlyActiveConfigurationAndPlatform;
var
  LXML: TStringList;
  LParser: IProjectParser;
  LPaths, LUnits: TArray<string>;
begin
  LXML := TStringList.Create;
  try
    LXML.Text :=
      '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
      '<PropertyGroup><Config Condition="''$(Config)''==''''">Debug</Config>' +
      '<Platform Condition="''$(Platform)''==''''">Win32</Platform></PropertyGroup>' +
      '<PropertyGroup Condition="''$(Config)|$(Platform)''==''Debug|Win32''">' +
      '<DCC_UnitSearchPath>debug32</DCC_UnitSearchPath></PropertyGroup>' +
      '<PropertyGroup Condition="''$(Config)|$(Platform)''==''Release|Win64''">' +
      '<DCC_UnitSearchPath>release64</DCC_UnitSearchPath></PropertyGroup>' +
      '<ItemGroup Condition="''$(Config)|$(Platform)''==''Debug|Win32''">' +
      '<DCCReference Include="DebugUnit.pas"/></ItemGroup>' +
      '<ItemGroup Condition="''$(Config)|$(Platform)''==''Release|Win64''">' +
      '<DCCReference Include="ReleaseUnit.pas"/></ItemGroup></Project>';
    LXML.SaveToFile(FTestDprojPath, TEncoding.UTF8);
  finally
    LXML.Free;
  end;

  LParser := TDprojParserAdapter.Create('Release', 'Win64');
  LPaths := LParser.GetSearchPaths(FTestDprojPath);
  LUnits := LParser.GetProjectUnits(FTestDprojPath);
  Assert.AreEqual(1, Integer(Length(LPaths)));
  Assert.AreEqual('release64', LPaths[0]);
  Assert.AreEqual(1, Integer(Length(LUnits)));
  Assert.AreEqual('ReleaseUnit.pas', LUnits[0]);
end;

procedure TDprojParserTests.ExpandsInheritedSearchPathInDeclarationOrder;
var
  LXML: TStringList;
  LPaths: TArray<string>;
begin
  LXML := TStringList.Create;
  try
    LXML.Text :=
      '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
      '<PropertyGroup><DCC_UnitSearchPath>base</DCC_UnitSearchPath></PropertyGroup>' +
      '<PropertyGroup><DCC_UnitSearchPath>specific;$(DCC_UnitSearchPath);$(PROJECTDIR)shared</DCC_UnitSearchPath></PropertyGroup>' +
      '</Project>';
    LXML.SaveToFile(FTestDprojPath, TEncoding.UTF8);
  finally
    LXML.Free;
  end;
  LPaths := FParser.GetSearchPaths(FTestDprojPath);
  Assert.AreEqual(3, Integer(Length(LPaths)));
  Assert.AreEqual('specific', LPaths[0]);
  Assert.AreEqual('base', LPaths[1]);
  Assert.AreEqual('$(PROJECTDIR)shared', LPaths[2]);
end;

procedure TDprojParserTests.EvaluatesDelphiGeneratedBooleanConditions;
var
  LXML: TStringList;
  LParser: IProjectParser;
  LPaths: TArray<string>;
begin
  LXML := TStringList.Create;
  try
    LXML.Text :=
      '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
      '<PropertyGroup><Base>True</Base></PropertyGroup>' +
      '<PropertyGroup Condition="(''$(Platform)''==''Win32'' and ''$(Base)''==''true'') or ''$(Base_Win32)''!=''''">' +
      '<Base_Win32>true</Base_Win32></PropertyGroup>' +
      '<PropertyGroup Condition="''$(Base_Win32)''!=''''">' +
      '<DCC_UnitSearchPath>win32-only</DCC_UnitSearchPath></PropertyGroup>' +
      '</Project>';
    LXML.SaveToFile(FTestDprojPath, TEncoding.UTF8);
  finally
    LXML.Free;
  end;
  LParser := TDprojParserAdapter.Create('Debug', 'Win32');
  LPaths := LParser.GetSearchPaths(FTestDprojPath);
  Assert.AreEqual(1, Integer(Length(LPaths)));
  Assert.AreEqual('win32-only', LPaths[0]);
end;

procedure TDprojParserTests.RespectsNestedLogicalParentheses;
var
  LXML: TStringList;
  LPaths: TArray<string>;
  LWarnings: TArray<string>;
begin
  LXML := TStringList.Create;
  try
    LXML.Text :=
      '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
      '<PropertyGroup Condition="(''disabled''==''x'' or ''enabled''==''enabled'') and ''Win32''==''Win32''">' +
      '<DCC_UnitSearchPath>nested-match</DCC_UnitSearchPath></PropertyGroup>' +
      '<PropertyGroup Condition="(''disabled''==''x'' or ''disabled''==''enabled'') and ''Win32''==''Win32''">' +
      '<DCC_UnitSearchPath>nested-miss</DCC_UnitSearchPath></PropertyGroup>' +
      '</Project>';
    LXML.SaveToFile(FTestDprojPath, TEncoding.UTF8);
  finally
    LXML.Free;
  end;
  LPaths := FParser.GetSearchPaths(FTestDprojPath);
  LWarnings := FParser.TakeWarnings;
  Assert.AreEqual(1, Integer(Length(LPaths)), string.Join(' | ', LWarnings));
  Assert.AreEqual('nested-match', LPaths[0]);
end;

procedure TDprojParserTests.EvaluatesExistsRelativeToProjectDirectory;
var
  LXML: TStringList;
  LMarkerPath: string;
  LPaths: TArray<string>;
begin
  LMarkerPath := TPath.Combine(TPath.GetDirectoryName(FTestDprojPath),
    'atropos-condition.marker');
  TFile.WriteAllText(LMarkerPath, 'present');
  try
    LXML := TStringList.Create;
    try
      LXML.Text :=
        '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
        '<PropertyGroup Condition="Exists(''atropos-condition.marker'')">' +
        '<DCC_UnitSearchPath>existing-path</DCC_UnitSearchPath></PropertyGroup>' +
        '<PropertyGroup Condition="Exists(''missing.marker'')">' +
        '<DCC_UnitSearchPath>missing-path</DCC_UnitSearchPath></PropertyGroup>' +
        '<PropertyGroup Condition="!Exists(''missing.marker'')">' +
        '<DCC_UnitSearchPath>negated-missing-path;$(DCC_UnitSearchPath)</DCC_UnitSearchPath></PropertyGroup>' +
        '</Project>';
      LXML.SaveToFile(FTestDprojPath, TEncoding.UTF8);
    finally
      LXML.Free;
    end;
    LPaths := FParser.GetSearchPaths(FTestDprojPath);
    Assert.AreEqual(2, Integer(Length(LPaths)));
    Assert.AreEqual('negated-missing-path', LPaths[0]);
    Assert.AreEqual('existing-path', LPaths[1]);
  finally
    TFile.Delete(LMarkerPath);
  end;
end;

procedure TDprojParserTests.ExpandsPropertyChainsBeyondFiveLevels;
var
  LXML: TStringList;
  LPaths: TArray<string>;
begin
  LXML := TStringList.Create;
  try
    LXML.Text :=
      '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
      '<PropertyGroup><P1>$(P2)</P1><P2>$(P3)</P2><P3>$(P4)</P3>' +
      '<P4>$(P5)</P4><P5>$(P6)</P5><P6>$(P7)</P6><P7>resolved</P7>' +
      '<DCC_UnitSearchPath>$(P1)</DCC_UnitSearchPath></PropertyGroup>' +
      '</Project>';
    LXML.SaveToFile(FTestDprojPath, TEncoding.UTF8);
  finally
    LXML.Free;
  end;
  LPaths := FParser.GetSearchPaths(FTestDprojPath);
  Assert.AreEqual(1, Integer(Length(LPaths)));
  Assert.AreEqual('resolved', LPaths[0]);
end;

procedure TDprojParserTests.ReportsUnsupportedConditions;
var
  LXML: TStringList;
  LPaths: TArray<string>;
  LWarnings: TArray<string>;
begin
  LXML := TStringList.Create;
  try
    LXML.Text :=
      '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
      '<PropertyGroup Condition="HasTrailingSlash(''src\'')">' +
      '<DCC_UnitSearchPath>unsupported</DCC_UnitSearchPath></PropertyGroup>' +
      '</Project>';
    LXML.SaveToFile(FTestDprojPath, TEncoding.UTF8);
  finally
    LXML.Free;
  end;
  LPaths := FParser.GetSearchPaths(FTestDprojPath);
  LWarnings := FParser.TakeWarnings;
  Assert.AreEqual(0, Integer(Length(LPaths)));
  Assert.AreEqual(1, Integer(Length(LWarnings)));
  Assert.IsTrue(LWarnings[0].Contains('unsupported MSBuild condition'));
  Assert.AreEqual(0, Integer(Length(FParser.TakeWarnings)));
end;

procedure TDprojParserTests.ReportsCyclicPropertyExpansion;
var
  LXML: TStringList;
  LWarnings: TArray<string>;
begin
  LXML := TStringList.Create;
  try
    LXML.Text :=
      '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
      '<PropertyGroup><First>$(Second)</First><Second>$(First)</Second>' +
      '<DCC_UnitSearchPath>$(First)</DCC_UnitSearchPath></PropertyGroup>' +
      '</Project>';
    LXML.SaveToFile(FTestDprojPath, TEncoding.UTF8);
  finally
    LXML.Free;
  end;
  FParser.GetSearchPaths(FTestDprojPath);
  LWarnings := FParser.TakeWarnings;
  Assert.IsTrue(Length(LWarnings) > 0);
  Assert.IsTrue(LWarnings[0].Contains('cyclic property expansion'));
end;

procedure TDprojParserTests.ParsesActivePathsFromRepositoryProject;
var
  LProjectPath: string;
  LParser: IProjectParser;
  LPaths: TArray<string>;
  LPath: string;
  LFoundSource, LFoundParser: Boolean;
begin
  LProjectPath := TPath.GetFullPath(
    TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\..\AtroposCLI.dproj'));
  Assert.IsTrue(TFile.Exists(LProjectPath));
  LParser := TDprojParserAdapter.Create('Debug', 'Win32');
  LPaths := LParser.GetSearchPaths(LProjectPath);
  LFoundSource := False;
  LFoundParser := False;
  for LPath in LPaths do
  begin
    LFoundSource := LFoundSource or SameText(LPath, 'third_party\DelphiAST\Source');
    LFoundParser := LFoundParser or SameText(LPath, 'third_party\DelphiAST\Source\SimpleParser');
  end;
  Assert.IsTrue(LFoundSource);
  Assert.IsTrue(LFoundParser);
end;

initialization
  TDUnitX.RegisterTestFixture(TDprojParserTests);

end.


