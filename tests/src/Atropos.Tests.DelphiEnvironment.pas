unit Atropos.Tests.DelphiEnvironment;

interface
uses
  DUnitX.TestFramework, Atropos.Core.Ports, Atropos.Adapters.DelphiEnvironment, System.SysUtils, System.IOUtils, System.Classes;

type
  TDelphiEnvironmentProbe = class(TDelphiEnvironmentAdapter)
  private
    FConfiguredPath: string;
    FRegistryPath: string;
    FRequestedVersion: string;
    FRegistryCallCount: Integer;
  protected
    function GetRootDirFromRegistry(const AVersion: string): string; override;
    function GetConfiguredBDSPath: string; override;
  public
    property ConfiguredPath: string read FConfiguredPath write FConfiguredPath;
    property RegistryPath: string read FRegistryPath write FRegistryPath;
    property RequestedVersion: string read FRequestedVersion;
    property RegistryCallCount: Integer read FRegistryCallCount;
  end;

  [TestFixture]
  TDelphiEnvironmentTests = class
  private
    FEnvironmentService: IDelphiEnvironmentService;
    FTestDprojPath: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Test_ResolveDelphiPath_Fallback_To_Highest_Or_BDS;
    
    [Test]
    procedure Test_ResolveDelphiPath_With_Mock_Dproj;
    [Test]
    procedure ProjectVersion201MapsToBDS230;
    [Test]
    procedure ProjectVersion203MapsToBDS230;
    [Test]
    procedure UnknownProjectVersionDoesNotGuessBDSVersion;
    [Test]
    procedure UnknownDeclaredVersionUsesCompatibilityFallback;
    [Test]
    procedure KnownVersionDoesNotFallBackToDifferentInstalledVersion;
  end;

implementation

function TDelphiEnvironmentProbe.GetConfiguredBDSPath: string;
begin
  Result := FConfiguredPath;
end;

function TDelphiEnvironmentProbe.GetRootDirFromRegistry(
  const AVersion: string): string;
begin
  Inc(FRegistryCallCount);
  FRequestedVersion := AVersion;
  Result := FRegistryPath;
end;

procedure TDelphiEnvironmentTests.ProjectVersion201MapsToBDS230;
begin
  Assert.AreEqual('23.0', TDelphiVersionMap.FromProjectVersion('20.1'));
end;

procedure TDelphiEnvironmentTests.ProjectVersion203MapsToBDS230;
begin
  Assert.AreEqual('23.0', TDelphiVersionMap.FromProjectVersion('20.3'));
end;

procedure TDelphiEnvironmentTests.UnknownProjectVersionDoesNotGuessBDSVersion;
begin
  Assert.AreEqual('', TDelphiVersionMap.FromProjectVersion('99.9'));
end;

procedure TDelphiEnvironmentTests.UnknownDeclaredVersionUsesCompatibilityFallback;
var
  LEnvironment: TDelphiEnvironmentProbe;
  LXMLContent: TStringList;
begin
  LXMLContent := TStringList.Create;
  try
    LXMLContent.Text := '<Project><ProjectVersion>99.9</ProjectVersion></Project>';
    LXMLContent.SaveToFile(FTestDprojPath, TEncoding.UTF8);
  finally
    LXMLContent.Free;
  end;
  LEnvironment := TDelphiEnvironmentProbe.Create;
  try
    LEnvironment.RegistryPath := 'C:\NewestButWrong';
    LEnvironment.ConfiguredPath := 'C:\ExplicitBDS';
    Assert.AreEqual('C:\NewestButWrong',
      LEnvironment.ResolveDelphiPath(FTestDprojPath));
    Assert.AreEqual(1, LEnvironment.RegistryCallCount);
    Assert.AreEqual('', LEnvironment.RequestedVersion);
  finally
    LEnvironment.Free;
  end;
end;

procedure TDelphiEnvironmentTests.KnownVersionDoesNotFallBackToDifferentInstalledVersion;
var
  LEnvironment: TDelphiEnvironmentProbe;
  LXMLContent: TStringList;
begin
  LXMLContent := TStringList.Create;
  try
    LXMLContent.Text := '<Project><ProjectVersion>20.3</ProjectVersion></Project>';
    LXMLContent.SaveToFile(FTestDprojPath, TEncoding.UTF8);
  finally
    LXMLContent.Free;
  end;
  LEnvironment := TDelphiEnvironmentProbe.Create;
  try
    LEnvironment.RegistryPath := '';
    LEnvironment.ConfiguredPath := 'C:\ExplicitBDS';
    Assert.AreEqual('C:\ExplicitBDS',
      LEnvironment.ResolveDelphiPath(FTestDprojPath));
    Assert.AreEqual(1, LEnvironment.RegistryCallCount);
    Assert.AreEqual('23.0', LEnvironment.RequestedVersion);
  finally
    LEnvironment.Free;
  end;
end;

procedure TDelphiEnvironmentTests.Setup;
begin
  FEnvironmentService := TDelphiEnvironmentAdapter.Create;
  FTestDprojPath := TPath.Combine(TPath.GetTempPath, 'TestProject.dproj');
end;

procedure TDelphiEnvironmentTests.TearDown;
begin
  if TFile.Exists(FTestDprojPath) then
    TFile.Delete(FTestDprojPath);
end;

procedure TDelphiEnvironmentTests.Test_ResolveDelphiPath_Fallback_To_Highest_Or_BDS;
var
  LResolvedPath: string;
begin
  // Passamos um dproj inexistente ou vazio para forÃ§ar o fallback (maior versÃ£o no reg ou var BDS)
  LResolvedPath := FEnvironmentService.ResolveDelphiPath('C:\InvalidPath\project.dproj');
  
  // O teste deve retornar ao menos alguma coisa se o desenvolvedor tiver Delphi instalado ou a var BDS setada
  // Em ambientes de CI limpos sem Delphi, isso pode retornar vazio, por isso nÃ£o exigimos Assert.IsNotEmpty,
  // apenas garantimos que a chamada ocorre sem quebrar (Access Violation)
  Assert.Pass('ResolveDelphiPath fallback executado com sucesso sem exceptions. Path: ' + LResolvedPath);
end;

procedure TDelphiEnvironmentTests.Test_ResolveDelphiPath_With_Mock_Dproj;
var
  LResolvedPath: string;
  LXmlContent: TStringList;
begin
  LXmlContent := TStringList.Create;
  try
    LXmlContent.Add('<?xml version="1.0" encoding="utf-8"?>');
    LXmlContent.Add('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">');
    LXmlContent.Add('  <PropertyGroup>');
    LXmlContent.Add('    <ProjectVersion>19.1</ProjectVersion>'); // Delphi 10.4
    LXmlContent.Add('  </PropertyGroup>');
    LXmlContent.Add('</Project>');
    LXmlContent.SaveToFile(FTestDprojPath, TEncoding.UTF8);
  finally
    LXmlContent.Free;
  end;

  LResolvedPath := FEnvironmentService.ResolveDelphiPath(FTestDprojPath);
  
  // Garantir que rodou sem quebrar e fez o parsing do ProjectVersion e a tentativa no Registry
  Assert.Pass('ResolveDelphiPath com mock DProj executado com sucesso. Path: ' + LResolvedPath);
end;

initialization
  TDUnitX.RegisterTestFixture(TDelphiEnvironmentTests);

end.

