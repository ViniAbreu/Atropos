unit Atropos.Tests.BuildReliability;

interface

uses
  Atropos.Application.AppService,
  Atropos.Adapters.BuildService,
  Atropos.Core.Config,
  Atropos.Core.Ports,
  DUnitX.TestFramework;

type
  TProjectParserSpy = class(TInterfacedObject, IProjectParser)
  public
    ProjectUnitsCallCount: Integer;
    function GetSearchPaths(const ADprojPath: string): TArray<string>;
    function GetProjectUnits(const ADprojPath: string): TArray<string>;
  end;

  TASTParserStub = class(TInterfacedObject, IASTParser)
  public
    function ParseFile(const AFilePath: string): IUnitSyntaxTree;
  end;

  TFileServiceSpy = class(TInterfacedObject, IFileService)
  public
    WriteCallCount: Integer;
    RestoreCallCount: Integer;
    procedure BackupFile(const AFilePath: string);
    procedure RestoreBackups;
    procedure CommitBackups;
    function ReadFileContent(const AFilePath: string): string;
    procedure WriteFileContent(const AFilePath, AContent: string);
  end;

  TReportGeneratorStub = class(TInterfacedObject, IReportGenerator)
  public
    procedure AddUnitProcessed(const AUnitName: string; const ARemovedUses, AMovedUses: TArray<string>);
    procedure AddMetrics(const ABefore, AAfter: TBuildMetrics);
    procedure SetAnalysisInfo(const AProjectName: string; AAnalysisTimeMs: Int64; AUnitsAnalyzed, ASearchPaths: Integer);
    function GetReportContentTXT: string;
    function GetReportContentHTML: string;
  end;

  TDelphiEnvironmentStub = class(TInterfacedObject, IDelphiEnvironmentService)
  public
    function ResolveDelphiPath(const ADprojPath: string): string;
  end;

  TExternalResolverStub = class(TInterfacedObject, IExternalUnitResolver)
  public
    procedure Initialize(const ASearchPaths: TArray<string>; const ADelphiPath, ABasePath: string); virtual;
    function TryResolveUnit(const AUnitName: string; out AExports: TArray<string>; out AHasInit, AIsNative: Boolean): Boolean;
  end;

  TFailingExternalResolver = class(TExternalResolverStub)
  public
    procedure Initialize(const ASearchPaths: TArray<string>; const ADelphiPath, ABasePath: string); override;
  end;

  TFailingBuildService = class(TInterfacedObject, IBuildService)
  public
    CallCount: Integer;
    function BuildProject(const AProjectPath: string): TBuildMetrics;
  end;

  TSuccessfulBuildService = class(TInterfacedObject, IBuildService)
  public
    CallCount: Integer;
    function BuildProject(const AProjectPath: string): TBuildMetrics;
  end;

  [TestFixture]
  TBuildReliabilityTests = class
  public
    [Test]
    procedure NonZeroExitCodeFailsBuildWithoutErrorText;
    [Test]
    procedure ZeroExitCodeAcceptsCleanBuildOutput;
    [Test]
    procedure FailedBaselineStopsBeforeProcessingOrWriting;
    [Test]
    procedure UnexpectedExceptionTriggersRollback;
    [Test]
    procedure CompilerErrorTextFailsEvenWithZeroExitCode;
    [Test]
    procedure BuildOutputCountsDiagnosticsAndInlineHints;
    [Test]
    procedure MissingDelphiEnvironmentFailsBuildGracefully;
    [Test]
    procedure HealthyProjectWithoutUnitsCommitsWithoutFinalBuild;
  end;

implementation

uses
  System.SysUtils;

function TProjectParserSpy.GetSearchPaths(const ADprojPath: string): TArray<string>;
begin
  Result := [];
end;

function TProjectParserSpy.GetProjectUnits(const ADprojPath: string): TArray<string>;
begin
  Inc(ProjectUnitsCallCount);
  Result := [];
end;

function TASTParserStub.ParseFile(const AFilePath: string): IUnitSyntaxTree;
begin
  raise Exception.Create('AST parser must not be called after a failed baseline build.');
end;

procedure TFileServiceSpy.BackupFile(const AFilePath: string);
begin
end;

procedure TFileServiceSpy.RestoreBackups;
begin
  Inc(RestoreCallCount);
end;

procedure TFileServiceSpy.CommitBackups;
begin
end;

function TFileServiceSpy.ReadFileContent(const AFilePath: string): string;
begin
  Result := EmptyStr;
end;

procedure TFileServiceSpy.WriteFileContent(const AFilePath, AContent: string);
begin
  Inc(WriteCallCount);
end;

procedure TReportGeneratorStub.AddUnitProcessed(const AUnitName: string; const ARemovedUses, AMovedUses: TArray<string>);
begin
end;

procedure TReportGeneratorStub.AddMetrics(const ABefore, AAfter: TBuildMetrics);
begin
end;

procedure TReportGeneratorStub.SetAnalysisInfo(const AProjectName: string; AAnalysisTimeMs: Int64; AUnitsAnalyzed, ASearchPaths: Integer);
begin
end;

function TReportGeneratorStub.GetReportContentTXT: string;
begin
  Result := EmptyStr;
end;

function TReportGeneratorStub.GetReportContentHTML: string;
begin
  Result := EmptyStr;
end;

function TDelphiEnvironmentStub.ResolveDelphiPath(const ADprojPath: string): string;
begin
  Result := EmptyStr;
end;

procedure TExternalResolverStub.Initialize(const ASearchPaths: TArray<string>; const ADelphiPath, ABasePath: string);
begin
end;

function TExternalResolverStub.TryResolveUnit(const AUnitName: string; out AExports: TArray<string>; out AHasInit, AIsNative: Boolean): Boolean;
begin
  AExports := [];
  AHasInit := False;
  AIsNative := False;
  Result := False;
end;

procedure TFailingExternalResolver.Initialize(const ASearchPaths: TArray<string>; const ADelphiPath, ABasePath: string);
begin
  raise Exception.Create('Unexpected resolver failure');
end;

function TFailingBuildService.BuildProject(const AProjectPath: string): TBuildMetrics;
begin
  Inc(CallCount);
  Result := Default(TBuildMetrics);
  Result.Success := False;
  Result.ErrorMessage := 'Baseline failed';
end;

function TSuccessfulBuildService.BuildProject(const AProjectPath: string): TBuildMetrics;
begin
  Inc(CallCount);
  Result := Default(TBuildMetrics);
  Result.Success := True;
end;

procedure TBuildReliabilityTests.NonZeroExitCodeFailsBuildWithoutErrorText;
var
  LMetrics: TBuildMetrics;
begin
  LMetrics := TBuildOutputParser.Parse('', 'Project.dproj', 1);
  Assert.IsFalse(LMetrics.Success);
end;

procedure TBuildReliabilityTests.ZeroExitCodeAcceptsCleanBuildOutput;
var
  LMetrics: TBuildMetrics;
begin
  LMetrics := TBuildOutputParser.Parse('', 'Project.dproj', 0);
  Assert.IsTrue(LMetrics.Success);
end;

procedure TBuildReliabilityTests.FailedBaselineStopsBeforeProcessingOrWriting;
var
  LProjectParser: TProjectParserSpy;
  LFileService: TFileServiceSpy;
  LBuildService: TFailingBuildService;
  LApplicationService: TProjectCleanerAppService;
  LConfig: TToolConfig;
begin
  LProjectParser := TProjectParserSpy.Create;
  LFileService := TFileServiceSpy.Create;
  LBuildService := TFailingBuildService.Create;
  LConfig := TToolConfig.Default;
  LApplicationService := TProjectCleanerAppService.Create(
    LProjectParser,
    TASTParserStub.Create,
    LFileService,
    TReportGeneratorStub.Create,
    TDelphiEnvironmentStub.Create,
    TExternalResolverStub.Create,
    LBuildService,
    LConfig);
  try
    LApplicationService.Execute('Project.dproj');
    Assert.AreEqual(1, LBuildService.CallCount);
    Assert.AreEqual(0, LProjectParser.ProjectUnitsCallCount);
    Assert.AreEqual(0, LFileService.WriteCallCount);
  finally
    LApplicationService.Free;
  end;
end;

procedure TBuildReliabilityTests.UnexpectedExceptionTriggersRollback;
var
  LFileService: TFileServiceSpy;
  LApplicationService: TProjectCleanerAppService;
  LConfig: TToolConfig;
  LExceptionRaised: Boolean;
begin
  LFileService := TFileServiceSpy.Create;
  LConfig := TToolConfig.Default;
  LApplicationService := TProjectCleanerAppService.Create(
    TProjectParserSpy.Create,
    TASTParserStub.Create,
    LFileService,
    TReportGeneratorStub.Create,
    TDelphiEnvironmentStub.Create,
    TFailingExternalResolver.Create,
    TFailingBuildService.Create,
    LConfig);
  try
    LExceptionRaised := False;
    try
      LApplicationService.Execute('Project.dproj');
    except
      on E: Exception do
        LExceptionRaised := True;
    end;
    Assert.IsTrue(LExceptionRaised);
    Assert.AreEqual(1, LFileService.RestoreCallCount);
  finally
    LApplicationService.Free;
  end;
end;

procedure TBuildReliabilityTests.CompilerErrorTextFailsEvenWithZeroExitCode;
var
  LMetrics: TBuildMetrics;
begin
  LMetrics := TBuildOutputParser.Parse(
    '[dcc32 Error] Unit1.pas(10): E2003 Undeclared identifier',
    'Project.dproj', 0);
  Assert.IsFalse(LMetrics.Success);
  Assert.IsTrue(LMetrics.ErrorMessage.Contains('E2003'));
end;

procedure TBuildReliabilityTests.BuildOutputCountsDiagnosticsAndInlineHints;
var
  LMetrics: TBuildMetrics;
  LOutput: string;
begin
  LOutput := '[dcc32 Hint] Unit1.pas(10): H2443 Inline function ''Run'' has not been expanded because unit ''System.SysUtils'' is not specified in USES list' + sLineBreak +
    '[dcc32 Warning] Unit1.pas(11): W1000 Symbol is deprecated';
  LMetrics := TBuildOutputParser.Parse(LOutput, 'Project.dproj', 0);
  Assert.IsTrue(LMetrics.Success);
  Assert.AreEqual(1, LMetrics.Hints);
  Assert.AreEqual(1, LMetrics.Warnings);
  Assert.AreEqual(1, Length(LMetrics.InlineHints));
  Assert.AreEqual('System.SysUtils', LMetrics.InlineHints[0].UnitNeeded);
end;

procedure TBuildReliabilityTests.MissingDelphiEnvironmentFailsBuildGracefully;
var
  LBuildService: IBuildService;
  LMetrics: TBuildMetrics;
begin
  LBuildService := TBuildServiceAdapter.Create(TDelphiEnvironmentStub.Create);
  LMetrics := LBuildService.BuildProject('Project.dproj');
  Assert.IsFalse(LMetrics.Success);
  Assert.IsTrue(LMetrics.ErrorMessage.Contains('Delphi path not found'));
end;

procedure TBuildReliabilityTests.HealthyProjectWithoutUnitsCommitsWithoutFinalBuild;
var
  LProjectParser: TProjectParserSpy;
  LFileService: TFileServiceSpy;
  LBuildService: TSuccessfulBuildService;
  LApplicationService: TProjectCleanerAppService;
  LConfig: TToolConfig;
begin
  LProjectParser := TProjectParserSpy.Create;
  LFileService := TFileServiceSpy.Create;
  LBuildService := TSuccessfulBuildService.Create;
  LConfig := TToolConfig.Default;
  LApplicationService := TProjectCleanerAppService.Create(
    LProjectParser, TASTParserStub.Create, LFileService,
    TReportGeneratorStub.Create, TDelphiEnvironmentStub.Create,
    TExternalResolverStub.Create, LBuildService, LConfig);
  try
    LApplicationService.Execute('Project.dproj');
    Assert.AreEqual(1, LBuildService.CallCount);
    Assert.AreEqual(1, LProjectParser.ProjectUnitsCallCount);
    Assert.AreEqual(0, LFileService.WriteCallCount);
  finally
    LApplicationService.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TBuildReliabilityTests);

end.
