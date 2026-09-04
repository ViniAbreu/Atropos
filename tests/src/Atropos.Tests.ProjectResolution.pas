unit Atropos.Tests.ProjectResolution;

interface

uses
  Atropos.Core.Ports,
  DUnitX.TestFramework;

type
  [TestFixture]
  TProjectResolutionTests = class
  private
    FBasePath: string;
    function ResolveUnit(const ASearchPath, AUnitName: string): Boolean;
    procedure WriteUnit(const ADirectory, AUnitName: string);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SearchPathDoesNotImplicitlyIncludeSubdirectories;
    [Test]
    procedure ProjectDirMacroResolvesAgainstProjectBasePath;
  end;

implementation

uses
  Atropos.Adapters.DelphiAST,
  Atropos.Adapters.ExternalUnitResolver,
  System.IOUtils,
  System.SysUtils;

procedure TProjectResolutionTests.Setup;
begin
  FBasePath := TPath.Combine(TPath.GetTempPath, 'AtroposResolver-' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FBasePath);
end;

procedure TProjectResolutionTests.TearDown;
begin
  if TDirectory.Exists(FBasePath) then
    TDirectory.Delete(FBasePath, True);
end;

procedure TProjectResolutionTests.WriteUnit(const ADirectory, AUnitName: string);
var
  LSource: string;
begin
  TDirectory.CreateDirectory(ADirectory);
  LSource := 'unit ' + AUnitName + ';' + sLineBreak +
    'interface' + sLineBreak +
    'const ExportedValue = 1;' + sLineBreak +
    'implementation' + sLineBreak +
    'end.';
  TFile.WriteAllText(TPath.Combine(ADirectory, AUnitName + '.pas'), LSource, TEncoding.UTF8);
end;

function TProjectResolutionTests.ResolveUnit(const ASearchPath, AUnitName: string): Boolean;
var
  LResolver: IExternalUnitResolver;
  LExports: TArray<string>;
  LHasInitialization: Boolean;
  LIsNative: Boolean;
begin
  LResolver := TExternalUnitResolverAdapter.Create(TDelphiASTAdapter.Create);
  LResolver.Initialize([ASearchPath], '', FBasePath);
  Result := LResolver.TryResolveUnit(AUnitName, LExports, LHasInitialization, LIsNative);
end;

procedure TProjectResolutionTests.SearchPathDoesNotImplicitlyIncludeSubdirectories;
var
  LNestedPath: string;
begin
  WriteUnit(FBasePath, 'TopLevelUnit');
  LNestedPath := TPath.Combine(FBasePath, 'Nested');
  WriteUnit(LNestedPath, 'NestedUnit');

  Assert.IsTrue(ResolveUnit(FBasePath, 'TopLevelUnit'));
  Assert.IsFalse(ResolveUnit(FBasePath, 'NestedUnit'));
  Assert.IsTrue(ResolveUnit(LNestedPath, 'NestedUnit'));
end;

procedure TProjectResolutionTests.ProjectDirMacroResolvesAgainstProjectBasePath;
var
  LLibraryPath: string;
begin
  LLibraryPath := TPath.Combine(FBasePath, 'Library');
  WriteUnit(LLibraryPath, 'MacroUnit');

  Assert.IsTrue(ResolveUnit('$(PROJECTDIR)\Library', 'MacroUnit'));
end;

initialization
  TDUnitX.RegisterTestFixture(TProjectResolutionTests);

end.
