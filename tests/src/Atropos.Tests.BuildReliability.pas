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
    TimedOut: Boolean;
    Cancelled: Boolean;
    TimeoutMs: Cardinal;
    ErrorFileContent: string;
    Command: string;
    function Execute(const ACommand: string; ATimeoutMs: Cardinal;
      const AShouldCancel: TCancellationCheck; out AOutput: string;
      out AExitCode: Cardinal; out ATimedOut, ACancelled: Boolean): Boolean;
  end;

  TBuildProfileCleanerSpy = class(TInterfacedObject, IBuildProfileCleaner)
  public
    ProfileName: string;
    procedure Cleanup(const AProfileName: string);
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
    [Test]
    procedure BuildTimeoutReturnsSpecificFailure;
    [Test]
    procedure Win32ProcessRunnerTerminatesTimedOutProcess;
    [Test]
    procedure BuildCancellationReturnsSpecificFailure;
    [Test]
    procedure Win32ProcessRunnerTerminatesCancelledProcess;
    [Test]
    procedure ApplicationCancellationRollsBack;
    [Test]
    procedure BuildAlwaysCleansTemporaryRegistryProfile;
    [Test]
    procedure WindowsProfileCleanerRemovesRegistryTree;
    [Test]
    procedure CancellationTerminatesChildProcessTree;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.RegularExpressions, System.Classes,
  System.Win.Registry, Winapi.Windows;

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

function TBuildProcessRunnerStub.Execute(const ACommand: string; ATimeoutMs: Cardinal;
  const AShouldCancel: TCancellationCheck; out AOutput: string;
  out AExitCode: Cardinal; out ATimedOut, ACancelled: Boolean): Boolean;
var
  LMatch: TMatch;
begin
  Command := ACommand;
  TimeoutMs := ATimeoutMs;
  AOutput := EmptyStr;
  AExitCode := ExitCode;
  ATimedOut := TimedOut;
  ACancelled := Cancelled;
  Result := ExecuteResult;
  if not Result then
    Exit;
  LMatch := TRegEx.Match(ACommand, '-o"([^"]+)"');
  if LMatch.Success then
    TFile.WriteAllText(LMatch.Groups[1].Value, ErrorFileContent);
end;

procedure TBuildProfileCleanerSpy.Cleanup(const AProfileName: string);
begin
  ProfileName := AProfileName;
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
    Assert.IsFalse(LApplicationService.Execute('Project.dproj'));
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
    Assert.IsTrue(LApplicationService.Execute('Project.dproj'));
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
      Assert.IsFalse(LService.Execute('Project.dproj'));
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
      Assert.IsTrue(LService.Execute('Project.dproj'));
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
      Assert.IsTrue(LService.Execute('Project.dproj'));
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
      Assert.IsTrue(LService.Execute('Project.dproj'));
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
  LTimedOut: Boolean;
  LCancelled: Boolean;
begin
  LRunner := TWin32BuildProcessRunner.Create;
  Assert.IsTrue(LRunner.Execute(
    '"' + TPath.Combine(GetEnvironmentVariable('WINDIR'), 'System32\cmd.exe') +
    '" /d /c "echo runner-output & exit /b 7"', 5000, nil, LOutput,
    LExitCode, LTimedOut, LCancelled));
  Assert.IsTrue(LOutput.Contains('runner-output'));
  Assert.AreEqual(Cardinal(7), LExitCode);
  Assert.IsFalse(LTimedOut);
end;

procedure TBuildReliabilityTests.BuildTimeoutReturnsSpecificFailure;
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
    LRunner.TimedOut := True;
    LService := TBuildServiceAdapter.Create(LEnvironment, nil, LRunner, 123);
    LMetrics := LService.BuildProject('Sample.dproj');
    Assert.IsFalse(LMetrics.Success);
    Assert.IsTrue(LMetrics.ErrorMessage.Contains('timed out after 123 ms'));
    Assert.AreEqual(Cardinal(123), LRunner.TimeoutMs);
  finally
    TDirectory.Delete(LRoot, True);
  end;
end;

procedure TBuildReliabilityTests.Win32ProcessRunnerTerminatesTimedOutProcess;
var
  LRunner: IBuildProcessRunner;
  LOutput: string;
  LExitCode: Cardinal;
  LTimedOut: Boolean;
  LCancelled: Boolean;
  LPowerShell: string;
begin
  LPowerShell := TPath.Combine(
    GetEnvironmentVariable('WINDIR'), 'System32\WindowsPowerShell\v1.0\powershell.exe');
  LRunner := TWin32BuildProcessRunner.Create;
  Assert.IsFalse(LRunner.Execute('"' + LPowerShell +
    '" -NoProfile -Command "Start-Sleep -Seconds 5"', 50, nil, LOutput,
    LExitCode, LTimedOut, LCancelled));
  Assert.IsTrue(LTimedOut);
end;

procedure TBuildReliabilityTests.BuildCancellationReturnsSpecificFailure;
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
    LRunner.Cancelled := True;
    LService := TBuildServiceAdapter.Create(LEnvironment, nil, LRunner);
    LMetrics := LService.BuildProject('Sample.dproj');
    Assert.IsFalse(LMetrics.Success);
    Assert.IsTrue(LMetrics.ErrorMessage.Contains('cancelled'));
  finally
    TDirectory.Delete(LRoot, True);
  end;
end;

procedure TBuildReliabilityTests.Win32ProcessRunnerTerminatesCancelledProcess;
var
  LRunner: IBuildProcessRunner;
  LOutput: string;
  LExitCode: Cardinal;
  LTimedOut, LCancelled: Boolean;
  LPowerShell: string;
begin
  LPowerShell := TPath.Combine(
    GetEnvironmentVariable('WINDIR'), 'System32\WindowsPowerShell\v1.0\powershell.exe');
  LRunner := TWin32BuildProcessRunner.Create;
  Assert.IsFalse(LRunner.Execute('"' + LPowerShell +
    '" -NoProfile -Command "Start-Sleep -Seconds 5"', 5000,
    function: Boolean
    begin
      Result := True;
    end,
    LOutput, LExitCode, LTimedOut, LCancelled));
  Assert.IsTrue(LCancelled);
  Assert.IsFalse(LTimedOut);
end;

procedure TBuildReliabilityTests.ApplicationCancellationRollsBack;
var
  LParser: TProjectParserSpy;
  LFiles: TFileServiceSpy;
  LService: TProjectCleanerAppService;
  LConfig: TToolConfig;
begin
  LParser := TProjectParserSpy.Create;
  LParser.Units := ['any-unit.pas'];
  LFiles := TFileServiceSpy.Create;
  LConfig := TToolConfig.Default;
  LService := TProjectCleanerAppService.Create(LParser, TASTParserStub.Create,
    LFiles, TReportGeneratorStub.Create, TDelphiEnvironmentStub.Create,
    TExternalResolverStub.Create, TSuccessfulBuildService.Create, LConfig,
    function: Boolean
    begin
      Result := True;
    end);
  try
    Assert.WillRaise(
      procedure
      begin
        LService.Execute('Project.dproj');
      end,
      EAbort);
    Assert.AreEqual(1, LFiles.RestoreCallCount);
  finally
    LService.Free;
  end;
end;

procedure TBuildReliabilityTests.BuildAlwaysCleansTemporaryRegistryProfile;
var
  LRoot, LBin: string;
  LEnvironment: TDelphiEnvironmentStub;
  LRunner: TBuildProcessRunnerStub;
  LCleaner: TBuildProfileCleanerSpy;
  LService: IBuildService;
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
    LCleaner := TBuildProfileCleanerSpy.Create;
    LService := TBuildServiceAdapter.Create(LEnvironment, nil, LRunner,
      600000, nil, LCleaner);
    LService.BuildProject('Sample.dproj');
    Assert.IsTrue(LCleaner.ProfileName.StartsWith('$atropos-ce-tmp\'));
  finally
    TDirectory.Delete(LRoot, True);
  end;
end;

procedure TBuildReliabilityTests.WindowsProfileCleanerRemovesRegistryTree;
var
  LProfileName, LKey: string;
  LRegistry: TRegistry;
  LCleaner: IBuildProfileCleaner;
begin
  LProfileName := '$atropos-ce-test\' + TGuid.NewGuid.ToString;
  LKey := 'Software\Embarcadero\' + LProfileName + '\23.0';
  LRegistry := TRegistry.Create(KEY_ALL_ACCESS);
  try
    LRegistry.RootKey := HKEY_CURRENT_USER;
    Assert.IsTrue(LRegistry.OpenKey(LKey, True));
    LRegistry.WriteString('Marker', 'Atropos');
    LRegistry.CloseKey;
    LCleaner := TWindowsBuildProfileCleaner.Create;
    LCleaner.Cleanup(LProfileName);
    Assert.IsFalse(LRegistry.KeyExists('Software\Embarcadero\' + LProfileName));
  finally
    LRegistry.Free;
  end;
end;

procedure TBuildReliabilityTests.CancellationTerminatesChildProcessTree;
var
  LRunner: IBuildProcessRunner;
  LOutput, LMarker, LStartedMarker, LScript, LCommand: string;
  LExitCode: Cardinal;
  LTimedOut, LCancelled: Boolean;
  LStartTick: UInt64;
begin
  LMarker := TPath.Combine(TPath.GetTempPath, TGuid.NewGuid.ToString + '.txt');
  LStartedMarker := LMarker + '.started';
  LScript := LMarker + '.cmd';
  TFile.WriteAllText(LScript,
    '@echo off' + sLineBreak +
    'start "" /b cmd.exe /d /c "echo started>""' + LStartedMarker +
      '"" & ping 127.0.0.1 -n 3 >nul & echo child>""' + LMarker + '"""' + sLineBreak +
    'ping 127.0.0.1 -n 10 >nul');
  LCommand := '"' + TPath.Combine(GetEnvironmentVariable('WINDIR'),
    'System32\cmd.exe') + '" /d /c "' + LScript + '"';
  LRunner := TWin32BuildProcessRunner.Create;
  LStartTick := GetTickCount64;
  Assert.IsFalse(LRunner.Execute(LCommand, 5000,
    function: Boolean
    begin
      Result := TFile.Exists(LStartedMarker) or (GetTickCount64 - LStartTick >= 2000);
    end,
    LOutput, LExitCode, LTimedOut, LCancelled));
  TThread.Sleep(1200);
  try
    Assert.IsTrue(LCancelled);
    Assert.IsTrue(TFile.Exists(LStartedMarker), 'The child process did not start.');
    Assert.IsFalse(TFile.Exists(LMarker), 'A child process survived cancellation.');
  finally
    if TFile.Exists(LStartedMarker) then
      TFile.Delete(LStartedMarker);
    if TFile.Exists(LMarker) then
      TFile.Delete(LMarker);
    if TFile.Exists(LScript) then
      TFile.Delete(LScript);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TBuildReliabilityTests);

end.
