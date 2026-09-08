unit Atropos.Tests.ProjectResolution;

interface

uses
  Atropos.Core.Ports,
  DUnitX.TestFramework;

type
  TFailingASTParser = class(TInterfacedObject, IASTParser)
  public
    function ParseFile(const AFilePath: string): IUnitSyntaxTree;
  end;

  TLoggerSpy = class(TInterfacedObject, ILogger)
  public
    Messages: TArray<string>;
    procedure Log(const AMsg: string);
  end;

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
    [Test]
    procedure MissingSearchPathProducesObservableWarning;
    [Test]
    procedure ParserFailureProducesObservableWarning;
  end;

implementation

uses
  Atropos.Adapters.DelphiAST,
  Atropos.Adapters.ExternalUnitResolver,
  System.IOUtils,
  System.SysUtils;

function TFailingASTParser.ParseFile(const AFilePath: string): IUnitSyntaxTree;
begin
  raise Exception.Create('deliberate parser failure');
end;

procedure TLoggerSpy.Log(const AMsg: string);
begin
  Messages := Messages + [AMsg];
end;

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

procedure TProjectResolutionTests.MissingSearchPathProducesObservableWarning;
var
  LResolver: IExternalUnitResolver;
  LLogger: TLoggerSpy;
  LExports: TArray<string>;
  LWarnings: TArray<string>;
  LHasInitialization: Boolean;
  LIsNative: Boolean;
  LMissingPath: string;
begin
  LMissingPath := TPath.Combine(FBasePath, 'Missing');
  LLogger := TLoggerSpy.Create;
  LResolver := TExternalUnitResolverAdapter.Create(TDelphiASTAdapter.Create,
    LLogger);
  LResolver.Initialize([LMissingPath], '', FBasePath);
  Assert.IsFalse(LResolver.TryResolveUnit('UnknownUnit', LExports,
    LHasInitialization, LIsNative));
  LWarnings := LResolver.GetWarnings;
  Assert.AreEqual(1, Integer(Length(LWarnings)));
  Assert.IsTrue(LWarnings[0].Contains('directory not found'));
  Assert.AreEqual(1, Integer(Length(LLogger.Messages)));
  Assert.IsTrue(LLogger.Messages[0].StartsWith('WARNING:'));
end;

procedure TProjectResolutionTests.ParserFailureProducesObservableWarning;
var
  LResolver: IExternalUnitResolver;
  LExports: TArray<string>;
  LWarnings: TArray<string>;
  LHasInitialization: Boolean;
  LIsNative: Boolean;
begin
  WriteUnit(FBasePath, 'BrokenUnit');
  LResolver := TExternalUnitResolverAdapter.Create(TFailingASTParser.Create);
  LResolver.Initialize([FBasePath], '', FBasePath);
  Assert.IsFalse(LResolver.TryResolveUnit('BrokenUnit', LExports,
    LHasInitialization, LIsNative));
  LWarnings := LResolver.GetWarnings;
  Assert.AreEqual(1, Integer(Length(LWarnings)));
  Assert.IsTrue(LWarnings[0].Contains('failed to parse unit BrokenUnit'));
  Assert.IsFalse(LHasInitialization);
  Assert.IsFalse(LIsNative);
end;

initialization
  TDUnitX.RegisterTestFixture(TProjectResolutionTests);

end.
