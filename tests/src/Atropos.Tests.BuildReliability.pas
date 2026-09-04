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
    Units: TArray<string>;
    function GetSearchPaths(const ADprojPath: string): TArray<string>;
    function GetProjectUnits(const ADprojPath: string): TArray<string>;
  end;

  TASTParserStub = class(TInterfacedObject, IASTParser)
  public
    SyntaxTree: IUnitSyntaxTree;
    RaiseOnParse: Boolean;
    function ParseFile(const AFilePath: string): IUnitSyntaxTree;
  end;

  TUnitSyntaxTreeStub = class(TInterfacedObject, IUnitSyntaxTree)
  public
    function GetUnitName: string;
    function GetInterfaceUses: TArray<string>;
    function GetImplementationUses: TArray<string>;
    function GetIdentifiersUsedInInterface: TArray<string>;
    function GetIdentifiersUsedInImplementation: TArray<string>;
    function GetExportedIdentifiers: TArray<string>;
    function HasInitializationSection: Boolean;
  end;

  TFileServiceSpy = class(TInterfacedObject, IFileService)
  public
    WriteCallCount: Integer;
    RestoreCallCount: Integer;
    BackupCallCount: Integer;
    CommitCallCount: Integer;
    Content: string;
    procedure BackupFile(const AFilePath: string);
    procedure RestoreBackups;
    procedure CommitBackups;
    function ReadFileContent(const AFilePath: string): string;
    procedure WriteFileContent(const AFilePath, AContent: string);
  end;

  TReportGeneratorStub = class(TInterfacedObject, IReportGenerator)
  public
    AddUnitCallCount: Integer;
    AddMetricsCallCount: Integer;
    SetInfoCallCount: Integer;
    procedure AddUnitProcessed(const AUnitName: string; const ARemovedUses, AMovedUses: TArray<string>);
    procedure AddMetrics(const ABefore, AAfter: TBuildMetrics);
    procedure SetAnalysisInfo(const AProjectName: string; AAnalysisTimeMs: Int64; AUnitsAnalyzed, ASearchPaths: Integer);
    function GetReportContentTXT: string;
    function GetReportContentHTML: string;
  end;

  TDelphiEnvironmentStub = class(TInterfacedObject, IDelphiEnvironmentService)
  public
    DelphiPath: string;
    function ResolveDelphiPath(const ADprojPath: string): string;
  end;

  TBuildProcessRunnerStub = class(TInterfacedObject, IBuildProcessRunner)
  public
    ExecuteResult: Boolean;
    ExitCode: Cardinal;
    ErrorFileContent: string;
    Command: string;
    function Execute(const ACommand: string; out AOutput: string;
      out AExitCode: Cardinal): Boolean;
  end;

  TExternalResolverStub = class(TInterfacedObject, IExternalUnitResolver)
  public
    ResolveKnownUnits: Boolean;
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

  TSequencedBuildService = class(TInterfacedObject, IBuildService)
  public
    CallCount: Integer;
    Results: TArray<TBuildMetrics>;
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
    [Test]
    procedure FailedFinalBuildRestoresModifiedFiles;
    [Test]
    procedure SuccessfulModificationCommitsAndRecordsMetrics;
    [Test]
    procedure ParserFailureSkipsUnitAndReportsProgress;
    [Test]
    procedure InlineHintIsFixedAndBuildIsVerifiedAgain;
    [Test]
    procedure InjectedProcessRunnerBuildsAndParsesCompilerOutput;
    [Test]
    procedure ProcessStartFailureReturnsBuildFailure;
    [Test]
    procedure MissingBdsExecutableDoesNotStartProcess;
    [Test]
    procedure Win32ProcessRunnerCapturesOutputAndExitCode;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.RegularExpressions;

function TProjectParserSpy.GetSearchPaths(const ADprojPath: string): TArray<string>;
begin
  Result := [];
end;

function TProjectParserSpy.GetProjectUnits(const ADprojPath: string): TArray<string>;
begin
  Inc(ProjectUnitsCallCount);
  Result := Units;
end;

function TASTParserStub.ParseFile(const AFilePath: string): IUnitSyntaxTree;
begin
  if RaiseOnParse then
    raise Exception.Create('Parser failure');
  if Assigned(SyntaxTree) then
    Exit(SyntaxTree);
  raise Exception.Create('AST parser must not be called after a failed baseline build.');
end;

function TUnitSyntaxTreeStub.GetUnitName: string;
begin Result := 'TestUnit'; end;
function TUnitSyntaxTreeStub.GetInterfaceUses: TArray<string>;
begin Result := ['Unused.Unit']; end;
function TUnitSyntaxTreeStub.GetImplementationUses: TArray<string>;
begin Result := []; end;
function TUnitSyntaxTreeStub.GetIdentifiersUsedInInterface: TArray<string>;
begin Result := []; end;
function TUnitSyntaxTreeStub.GetIdentifiersUsedInImplementation: TArray<string>;
begin Result := []; end;
function TUnitSyntaxTreeStub.GetExportedIdentifiers: TArray<string>;
begin Result := []; end;
function TUnitSyntaxTreeStub.HasInitializationSection: Boolean;
begin Result := False; end;

procedure TFileServiceSpy.BackupFile(const AFilePath: string);
begin
  Inc(BackupCallCount);
end;

procedure TFileServiceSpy.RestoreBackups;
begin
  Inc(RestoreCallCount);
end;

procedure TFileServiceSpy.CommitBackups;
begin
  Inc(CommitCallCount);
end;

function TFileServiceSpy.ReadFileContent(const AFilePath: string): string;
begin
  Result := Content;
end;

procedure TFileServiceSpy.WriteFileContent(const AFilePath, AContent: string);
begin
  Inc(WriteCallCount);
  Content := AContent;
end;

procedure TReportGeneratorStub.AddUnitProcessed(const AUnitName: string; const ARemovedUses, AMovedUses: TArray<string>);
begin
  Inc(AddUnitCallCount);
end;

procedure TReportGeneratorStub.AddMetrics(const ABefore, AAfter: TBuildMetrics);
begin
  Inc(AddMetricsCallCount);
end;

procedure TReportGeneratorStub.SetAnalysisInfo(const AProjectName: string; AAnalysisTimeMs: Int64; AUnitsAnalyzed, ASearchPaths: Integer);
begin
  Inc(SetInfoCallCount);
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
  Result := DelphiPath;
end;

function TBuildProcessRunnerStub.Execute(const ACommand: string; out AOutput: string;
  out AExitCode: Cardinal): Boolean;
var
  LMatch: TMatch;
begin
  Command := ACommand;
  AOutput := EmptyStr;
  AExitCode := ExitCode;
  Result := ExecuteResult;
  if not Result then
    Exit;
  LMatch := TRegEx.Match(ACommand, '-o"([^"]+)"');
  if LMatch.Success then
    TFile.WriteAllText(LMatch.Groups[1].Value, ErrorFileContent);
end;

procedure TExternalResolverStub.Initialize(const ASearchPaths: TArray<string>; const ADelphiPath, ABasePath: string);
begin
end;

function TExternalResolverStub.TryResolveUnit(const AUnitName: string; out AExports: TArray<string>; out AHasInit, AIsNative: Boolean): Boolean;
begin
  AExports := [];
  AHasInit := False;
  AIsNative := False;
  if ResolveKnownUnits then
    AExports := ['UnusedSymbol'];
  Result := ResolveKnownUnits;
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

function TSequencedBuildService.BuildProject(const AProjectPath: string): TBuildMetrics;
begin
  Result := Results[CallCount];
  Inc(CallCount);
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

procedure TBuildReliabilityTests.FailedFinalBuildRestoresModifiedFiles;
var
  LParser: TProjectParserSpy;
  LAST: TASTParserStub;
  LFiles: TFileServiceSpy;
  LReports: TReportGeneratorStub;
  LResolver: TExternalResolverStub;
  LBuild: TSequencedBuildService;
  LService: TProjectCleanerAppService;
  LConfig: TToolConfig;
  LTempFile: string;
  LSuccess, LFailure: TBuildMetrics;
begin
  LTempFile := TPath.GetTempFileName;
  try
    LParser := TProjectParserSpy.Create;
    LParser.Units := [LTempFile];
    LAST := TASTParserStub.Create;
    LAST.SyntaxTree := TUnitSyntaxTreeStub.Create;
    LFiles := TFileServiceSpy.Create;
    LFiles.Content := 'unit TestUnit;' + sLineBreak + 'interface' + sLineBreak +
      'uses Unused.Unit;' + sLineBreak + 'implementation' + sLineBreak + 'end.';
    LReports := TReportGeneratorStub.Create;
    LResolver := TExternalResolverStub.Create;
    LResolver.ResolveKnownUnits := True;
    LSuccess := Default(TBuildMetrics);
    LSuccess.Success := True;
    LFailure := Default(TBuildMetrics);
    LFailure.Success := False;
    LFailure.ErrorMessage := 'Final build failed';
    LBuild := TSequencedBuildService.Create;
    LBuild.Results := [LSuccess, LFailure];
    LConfig := TToolConfig.Default;
    LConfig.RemoveUnused := True;
    LService := TProjectCleanerAppService.Create(LParser, LAST, LFiles, LReports,
      TDelphiEnvironmentStub.Create, LResolver, LBuild, LConfig);
    try
      LService.Execute('Project.dproj');
      Assert.AreEqual(2, LBuild.CallCount);
      Assert.AreEqual(1, LFiles.WriteCallCount);
      Assert.AreEqual(1, LFiles.RestoreCallCount);
      Assert.AreEqual(0, LFiles.CommitCallCount);
      Assert.AreEqual(1, LReports.AddUnitCallCount);
    finally
      LService.Free;
    end;
  finally
    TFile.Delete(LTempFile);
  end;
end;

procedure TBuildReliabilityTests.SuccessfulModificationCommitsAndRecordsMetrics;
var
  LParser: TProjectParserSpy;
  LAST: TASTParserStub;
  LFiles: TFileServiceSpy;
  LReports: TReportGeneratorStub;
  LResolver: TExternalResolverStub;
  LBuild: TSequencedBuildService;
  LService: TProjectCleanerAppService;
  LConfig: TToolConfig;
  LTempFile: string;
  LSuccess: TBuildMetrics;
begin
  LTempFile := TPath.GetTempFileName;
  try
    LParser := TProjectParserSpy.Create;
    LParser.Units := [LTempFile];
    LAST := TASTParserStub.Create;
    LAST.SyntaxTree := TUnitSyntaxTreeStub.Create;
    LFiles := TFileServiceSpy.Create;
    LFiles.Content := 'unit TestUnit;' + sLineBreak + 'interface' + sLineBreak +
      'uses Unused.Unit;' + sLineBreak + 'implementation' + sLineBreak + 'end.';
    LReports := TReportGeneratorStub.Create;
    LResolver := TExternalResolverStub.Create;
    LResolver.ResolveKnownUnits := True;
    LSuccess := Default(TBuildMetrics);
    LSuccess.Success := True;
    LBuild := TSequencedBuildService.Create;
    LBuild.Results := [LSuccess, LSuccess];
    LConfig := TToolConfig.Default;
    LConfig.RemoveUnused := True;
    LConfig.EnableDebug := True;
    LService := TProjectCleanerAppService.Create(LParser, LAST, LFiles, LReports,
      TDelphiEnvironmentStub.Create, LResolver, LBuild, LConfig);
    try
      LService.Execute('Project.dproj');
      Assert.AreEqual(2, LBuild.CallCount);
      Assert.AreEqual(1, LFiles.CommitCallCount);
      Assert.AreEqual(0, LFiles.RestoreCallCount);
      Assert.AreEqual(1, LReports.AddMetricsCallCount);
      Assert.AreEqual(1, LReports.SetInfoCallCount);
    finally
      LService.Free;
    end;
  finally
    TFile.Delete(LTempFile);
  end;
end;

procedure TBuildReliabilityTests.ParserFailureSkipsUnitAndReportsProgress;
var
  LParser: TProjectParserSpy;
  LAST: TASTParserStub;
  LFiles: TFileServiceSpy;
  LBuild: TSuccessfulBuildService;
  LService: TProjectCleanerAppService;
  LConfig: TToolConfig;
  LTempFile: string;
  LProgressPosition: Integer;
begin
  LTempFile := TPath.GetTempFileName;
  try
    LParser := TProjectParserSpy.Create;
    LParser.Units := [LTempFile];
    LAST := TASTParserStub.Create;
    LAST.RaiseOnParse := True;
    LFiles := TFileServiceSpy.Create;
    LBuild := TSuccessfulBuildService.Create;
    LConfig := TToolConfig.Default;
    LService := TProjectCleanerAppService.Create(LParser, LAST, LFiles,
      TReportGeneratorStub.Create, TDelphiEnvironmentStub.Create,
      TExternalResolverStub.Create, LBuild, LConfig);
    try
      LProgressPosition := -1;
      LService.OnProgress :=
        procedure(AMax, APosition: Integer)
        begin
          LProgressPosition := APosition;
        end;
      LService.Execute('Project.dproj');
      Assert.AreEqual(1, LProgressPosition);
      Assert.AreEqual(1, LBuild.CallCount);
      Assert.AreEqual(0, LFiles.WriteCallCount);
    finally
      LService.Free;
    end;
  finally
    TFile.Delete(LTempFile);
  end;
end;

procedure TBuildReliabilityTests.InlineHintIsFixedAndBuildIsVerifiedAgain;
var
  LParser: TProjectParserSpy;
  LAST: TASTParserStub;
  LFiles: TFileServiceSpy;
  LReports: TReportGeneratorStub;
  LResolver: TExternalResolverStub;
  LBuild: TSequencedBuildService;
  LService: TProjectCleanerAppService;
  LConfig: TToolConfig;
  LTempFile: string;
  LBaseline, LAfter, LVerified: TBuildMetrics;
  LHint: TInlineHint;
begin
  LTempFile := TPath.GetTempFileName;
  try
    LParser := TProjectParserSpy.Create;
    LParser.Units := [LTempFile];
    LAST := TASTParserStub.Create;
    LAST.SyntaxTree := TUnitSyntaxTreeStub.Create;
    LFiles := TFileServiceSpy.Create;
    LFiles.Content := 'unit TestUnit;' + sLineBreak + 'interface' + sLineBreak +
      'uses Unused.Unit;' + sLineBreak + 'implementation' + sLineBreak +
      'uses Needed.Unit;' + sLineBreak + 'end.';
    LReports := TReportGeneratorStub.Create;
    LResolver := TExternalResolverStub.Create;
    LResolver.ResolveKnownUnits := True;
    LBaseline := Default(TBuildMetrics);
    LBaseline.Success := True;
    LAfter := LBaseline;
    LHint.HintType := 'H2443';
    LHint.FilePath := LTempFile;
    LHint.UnitNeeded := 'Needed.Unit';
    LAfter.InlineHints := [LHint];
    LVerified := LBaseline;
    LBuild := TSequencedBuildService.Create;
    LBuild.Results := [LBaseline, LAfter, LVerified];
    LConfig := TToolConfig.Default;
    LConfig.RemoveUnused := True;
    LService := TProjectCleanerAppService.Create(LParser, LAST, LFiles, LReports,
      TDelphiEnvironmentStub.Create, LResolver, LBuild, LConfig);
    try
      LService.Execute('Project.dproj');
      Assert.AreEqual(3, LBuild.CallCount);
      Assert.AreEqual(2, LFiles.WriteCallCount);
      Assert.AreEqual(2, LFiles.BackupCallCount);
      Assert.AreEqual(1, LFiles.CommitCallCount);
      Assert.IsTrue(LFiles.Content.Contains('Needed.Unit'));
      Assert.IsTrue(Pos('Needed.Unit', LFiles.Content) < Pos('implementation', LFiles.Content));
    finally
      LService.Free;
    end;
  finally
    TFile.Delete(LTempFile);
  end;
end;

procedure TBuildReliabilityTests.InjectedProcessRunnerBuildsAndParsesCompilerOutput;
var
  LRoot, LBin, LBds, LProject: string;
  LEnvironment: TDelphiEnvironmentStub;
  LRunner: TBuildProcessRunnerStub;
  LService: IBuildService;
  LMetrics: TBuildMetrics;
begin
  LRoot := TPath.Combine(TPath.GetTempPath, TGuid.NewGuid.ToString);
  LBin := TPath.Combine(LRoot, 'bin');
  TDirectory.CreateDirectory(LBin);
  LBds := TPath.Combine(LBin, 'bds.exe');
  TFile.WriteAllText(LBds, EmptyStr);
  LProject := TPath.Combine(LRoot, 'Sample.dproj');
  try
    LEnvironment := TDelphiEnvironmentStub.Create;
    LEnvironment.DelphiPath := LRoot;
    LRunner := TBuildProcessRunnerStub.Create;
    LRunner.ExecuteResult := True;
    LRunner.ExitCode := 0;
    LRunner.ErrorFileContent := '[dcc32 Warning] Unit1.pas(1): W1000 Warning';
    LService := TBuildServiceAdapter.Create(LEnvironment, nil, LRunner);
    LMetrics := LService.BuildProject(LProject);
    Assert.IsTrue(LMetrics.Success);
    Assert.AreEqual(1, LMetrics.Warnings);
    Assert.IsTrue(LRunner.Command.Contains('-b -ns'));
    Assert.IsTrue(LRunner.Command.Contains(LProject));
    Assert.AreEqual(ExtractFileName(LRoot), LMetrics.DelphiVersion);
  finally
    TDirectory.Delete(LRoot, True);
  end;
end;

procedure TBuildReliabilityTests.ProcessStartFailureReturnsBuildFailure;
var
  LRoot, LBin: string;
  LEnvironment: TDelphiEnvironmentStub;
  LRunner: TBuildProcessRunnerStub;
  LService: IBuildService;
  LMetrics: TBuildMetrics;
begin
  LRoot := TPath.Combine(TPath.GetTempPath, TGuid.NewGuid.ToString);
  LBin := TPath.Combine(LRoot, 'bin');
  TDirectory.CreateDirectory(LBin);
  TFile.WriteAllText(TPath.Combine(LBin, 'bds.exe'), EmptyStr);
  try
    LEnvironment := TDelphiEnvironmentStub.Create;
    LEnvironment.DelphiPath := LRoot;
    LRunner := TBuildProcessRunnerStub.Create;
    LRunner.ExecuteResult := False;
    LService := TBuildServiceAdapter.Create(LEnvironment, nil, LRunner);
    LMetrics := LService.BuildProject('Sample.dproj');
    Assert.IsFalse(LMetrics.Success);
    Assert.IsTrue(LMetrics.ErrorMessage.Contains('Failed to execute'));
  finally
    TDirectory.Delete(LRoot, True);
  end;
end;

procedure TBuildReliabilityTests.MissingBdsExecutableDoesNotStartProcess;
var
  LRoot: string;
  LEnvironment: TDelphiEnvironmentStub;
  LRunner: TBuildProcessRunnerStub;
  LService: IBuildService;
  LMetrics: TBuildMetrics;
begin
  LRoot := TPath.Combine(TPath.GetTempPath, TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(LRoot);
  try
    LEnvironment := TDelphiEnvironmentStub.Create;
    LEnvironment.DelphiPath := LRoot;
    LRunner := TBuildProcessRunnerStub.Create;
    LRunner.ExecuteResult := True;
    LService := TBuildServiceAdapter.Create(LEnvironment, nil, LRunner);
    LMetrics := LService.BuildProject('Sample.dproj');
    Assert.IsFalse(LMetrics.Success);
    Assert.IsTrue(LMetrics.ErrorMessage.Contains('bds.exe not found'));
    Assert.IsTrue(LRunner.Command.IsEmpty);
  finally
    TDirectory.Delete(LRoot, True);
  end;
end;

procedure TBuildReliabilityTests.Win32ProcessRunnerCapturesOutputAndExitCode;
var
  LRunner: IBuildProcessRunner;
  LOutput: string;
  LExitCode: Cardinal;
begin
  LRunner := TWin32BuildProcessRunner.Create;
  Assert.IsTrue(LRunner.Execute(
    '"' + TPath.Combine(GetEnvironmentVariable('WINDIR'), 'System32\cmd.exe') +
    '" /d /c "echo runner-output & exit /b 7"', LOutput, LExitCode));
  Assert.IsTrue(LOutput.Contains('runner-output'));
  Assert.AreEqual(Cardinal(7), LExitCode);
end;

initialization
  TDUnitX.RegisterTestFixture(TBuildReliabilityTests);

end.
