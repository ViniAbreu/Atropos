unit Atropos.Application.AppService;

interface
uses
  Atropos.Core.Ports,
  Atropos.Core.Config,
  Atropos.Core.Domain,
  Atropos.Core.Modifier,
  Atropos.Application.AnalysisPlan,
  System.Generics.Collections;

type
  TProgressEvent = reference to procedure(AMax, APosition: Integer);

  TProjectCleanerAppService = class
  private
    FProjectParser: IProjectParser;
    FASTParser: IASTParser;
    FFileService: IFileService;
    FReportGen: IReportGenerator;
    FDelphiEnvironment: IDelphiEnvironmentService;
    FResolver: IExternalUnitResolver;
    FBuildService: IBuildService;
    FConfig: TToolConfig;
    FShouldCancel: TCancellationCheck;
    
    FOnProgress: TProgressEvent;
    FOnLog: TLogEvent;

    procedure Log(const AMsg: string);
    procedure Progress(AMax, APosition: Integer);
    function ResolvePath(const ABasePath, ARelativePath: string): string;

    function RunBaselineBuild(const AFullPath: string): TBuildMetrics;
    procedure LogBuildDiagnostics(const AMetrics: TBuildMetrics);
    function RunConfiguredBuilds(const AFullPath: string): TBuildMetrics;
    procedure ProcessUnits(const ABasePath, ADprojPath: string; out ATotalRemoved, ATotalMoved, AUnitCount: Integer; LLogger: ILogger; LContext: TProjectContext; LAnalyzer: TAnalyzeUnitUses; LModifier: TApplyUsesChanges);
    procedure CheckCancellation;
    procedure AnalyzeUnit(const APath: string; AContext: TProjectContext;
      AAnalyzer: TAnalyzeUnitUses; APlan: TUnitAnalysisPlan);
    procedure ApplyPlannedUnit(const AChange: TPlannedUnitChange;
      AModifier: TApplyUsesChanges; var ARemoved, AMoved: Integer);
    function RunFinalBuild(const AFullPath: string; ARemoved, AMoved: Integer): TBuildMetrics;
    function ProcessInlineHints(const AHints: TArray<TInlineHint>; LModifier: TApplyUsesChanges): Integer;
    procedure CommitChanges(const AMetricsBefore,
      AMetricsAfter: TBuildMetrics);
    procedure RollbackChanges(const AErrorMessage: string);
    procedure RecordRolledBackReport;
    procedure GenerateReports(const AOutputDirectory: string);
    procedure CollectProjectParserWarnings;
    procedure CollectResolverWarnings;
    procedure ReportPreservationReasons(const AUnitPath: string;
      const AReasons: TArray<string>);
    function SetupEnvironment(const AFullPath, ABasePath: string): Integer;
    function CreateLogger: ILogger;
    function ExecuteSafely(const ADprojPath: string): Boolean;
  public
    constructor Create(
      const AProjectParser: IProjectParser;
      const AASTParser: IASTParser;
      const AFileService: IFileService;
      const AReportGen: IReportGenerator;
      const ADelphiEnvironment: IDelphiEnvironmentService;
      const AResolver: IExternalUnitResolver;
      const ABuildService: IBuildService;
      const AConfig: TToolConfig;
      const AShouldCancel: TCancellationCheck = nil);
      
    property OnProgress: TProgressEvent read FOnProgress write FOnProgress;
    property OnLog: TLogEvent read FOnLog write FOnLog;

    function Execute(const ADprojPath: string): Boolean;
  end;

implementation
uses System.Diagnostics, System.IOUtils, System.Threading,
  System.SysUtils;

type
  TApplicationLogger = class(TInterfacedObject, ILogger)
  private
    FOnLog: TLogEvent;
  public
    constructor Create(const AOnLog: TLogEvent);
    procedure Log(const AMsg: string);
  end;

procedure TProjectCleanerAppService.CollectProjectParserWarnings;
var
  LWarning: string;
begin
  for LWarning in FProjectParser.TakeWarnings do
  begin
    Log('WARNING: ' + LWarning);
    FReportGen.AddWarning(LWarning);
  end;
end;

procedure TProjectCleanerAppService.CollectResolverWarnings;
var
  LWarning: string;
begin
  for LWarning in FResolver.GetWarnings do
  begin
    Log('WARNING: ' + LWarning);
    FReportGen.AddWarning(LWarning);
  end;
end;

constructor TApplicationLogger.Create(const AOnLog: TLogEvent);
begin
  FOnLog := AOnLog;
end;

procedure TApplicationLogger.Log(const AMsg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(AMsg);
end;

constructor TProjectCleanerAppService.Create(
  const AProjectParser: IProjectParser;
  const AASTParser: IASTParser;
  const AFileService: IFileService;
  const AReportGen: IReportGenerator;
  const ADelphiEnvironment: IDelphiEnvironmentService;
  const AResolver: IExternalUnitResolver;
  const ABuildService: IBuildService;
  const AConfig: TToolConfig;
  const AShouldCancel: TCancellationCheck);
begin
  FProjectParser := AProjectParser;
  FASTParser := AASTParser;
  FFileService := AFileService;
  FReportGen := AReportGen;
  FDelphiEnvironment := ADelphiEnvironment;
  FResolver := AResolver;
  FBuildService := ABuildService;
  FConfig := AConfig;
  FShouldCancel := AShouldCancel;
end;

procedure TProjectCleanerAppService.Log(const AMsg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(AMsg);
end;

procedure TProjectCleanerAppService.Progress(AMax, APosition: Integer);
begin
  if Assigned(FOnProgress) then
    FOnProgress(AMax, APosition);
end;

function TProjectCleanerAppService.ResolvePath(const ABasePath, ARelativePath: string): string;
begin
  Result := ARelativePath;
  if TPath.IsRelativePath(ARelativePath) then
    Result := TPath.GetFullPath(TPath.Combine(ABasePath, ARelativePath));
end;

function TProjectCleanerAppService.CreateLogger: ILogger;
begin
  Result := nil;
  if FConfig.EnableDebug then
  begin
    Result := TApplicationLogger.Create(
      procedure(const AMsg: string)
      begin
        Self.Log(AMsg);
      end);
  end;
end;

function TProjectCleanerAppService.SetupEnvironment(const AFullPath, ABasePath: string): Integer;
var
  LSearchPaths: TArray<string>;
  LDelphiPath: string;
begin
  LDelphiPath := FDelphiEnvironment.ResolveDelphiPath(AFullPath);
  if not LDelphiPath.IsEmpty then
    Log('Resolved Delphi installation: ' + LDelphiPath);
  if LDelphiPath.IsEmpty then
    Log('WARNING: Delphi environment not found. Standard RTL/VCL units will not be resolved and will be ignored.');

  LSearchPaths := FProjectParser.GetSearchPaths(AFullPath) + [ABasePath];
  
  FResolver.Initialize(LSearchPaths, LDelphiPath, ABasePath);
  Result := Length(LSearchPaths);
end;

function TProjectCleanerAppService.RunBaselineBuild(const AFullPath: string): TBuildMetrics;
begin
  Log('Running baseline build (Before)...');
  Result := RunConfiguredBuilds(AFullPath);
  LogBuildDiagnostics(Result);
  if not Result.Success then
  begin
    Log('WARNING: Baseline build failed. Analysis is stopped; no source files will be changed.');
    Log('Error: ' + Result.ErrorMessage);
    Exit;
  end;
  
  Log(Format('Baseline build successful. Hints: %d, Warnings: %d', [Result.Hints, Result.Warnings]));
  Log('Delphi Version: ' + Result.DelphiVersion);
end;

procedure TProjectCleanerAppService.LogBuildDiagnostics(
  const AMetrics: TBuildMetrics);
begin
  if not FConfig.EnableDebug then
    Exit;
  if AMetrics.DiagnosticOutput.IsEmpty then
    Exit;
  Log('DEBUG: Complete compiler output:' + sLineBreak +
    AMetrics.DiagnosticOutput);
end;

function TProjectCleanerAppService.RunConfiguredBuilds(
  const AFullPath: string): TBuildMetrics;
var
  LTarget: TBuildTarget;
begin
  if Length(FConfig.BuildTargets) = 0 then
    Exit(FBuildService.BuildProject(AFullPath));
  Result := Default(TBuildMetrics);
  for LTarget in FConfig.BuildTargets do
  begin
    Log(Format('Building target %s|%s...', [LTarget.Configuration,
      LTarget.Platform]));
    Result := FBuildService.BuildProjectForTarget(AFullPath, LTarget);
    if Result.Success then
      Continue;
    Result.ErrorMessage := Format('[%s|%s] %s', [LTarget.Configuration,
      LTarget.Platform, Result.ErrorMessage]);
    Exit;
  end;
end;

procedure TProjectCleanerAppService.ReportPreservationReasons(
  const AUnitPath: string; const AReasons: TArray<string>);
var
  LReason: string;
begin
  for LReason in AReasons do
    FReportGen.AddWarning(AUnitPath + ': preserved ' + LReason);
end;

procedure TProjectCleanerAppService.CheckCancellation;
begin
  if Assigned(FShouldCancel) and FShouldCancel() then
    raise EAbort.Create('Operation cancelled by user.');
end;

procedure TProjectCleanerAppService.AnalyzeUnit(const APath: string;
  AContext: TProjectContext; AAnalyzer: TAnalyzeUnitUses; APlan: TUnitAnalysisPlan);
var
  LTree: IUnitSyntaxTree;
  LResult: TUnitAnalysisResult;
begin
  if not TFile.Exists(APath) then
  begin
    Log('Warning: File not found -> ' + APath);
    FReportGen.AddWarning(APath + ': unknown analysis; source file not found.');
    Exit;
  end;
  try
    LTree := FASTParser.ParseFile(APath);
    LResult := AAnalyzer.Execute(LTree, AContext);
  except
    on E: Exception do
    begin
      Log('Error processing ' + ExtractFileName(APath) + ': ' + E.Message);
      FReportGen.AddWarning(APath + ': unknown analysis; imports preserved: ' + E.Message);
      Exit;
    end;
  end;
  ReportPreservationReasons(APath, LResult.PreservationReasons);
  APlan.Add(APath, LResult);
end;

procedure TProjectCleanerAppService.ApplyPlannedUnit(
  const AChange: TPlannedUnitChange; AModifier: TApplyUsesChanges;
  var ARemoved, AMoved: Integer);
var
  LResult: TUnitAnalysisResult;
  LHasConfiguredChanges, LHasAmbiguity: Boolean;
begin
  LResult := AChange.Analysis;
  if FConfig.DryRun then
  begin
    if (Length(LResult.UnusedUnits) > 0) or
      (Length(LResult.UnitsToMoveToImpl) > 0) or
      (Length(LResult.PreservedAmbiguities) > 0) then
      FReportGen.AddUnitProcessed(AChange.FilePath, LResult.UnusedUnits,
        LResult.UnitsToMoveToImpl, LResult.PreservedAmbiguities);
    Exit;
  end;
  LHasConfiguredChanges :=
    (FConfig.RemoveUnused and (Length(LResult.UnusedUnits) > 0)) or
    (FConfig.MoveToImplementation and (Length(LResult.UnitsToMoveToImpl) > 0));
  LHasAmbiguity := Length(LResult.PreservedAmbiguities) > 0;
  if LHasConfiguredChanges then
  begin
    AModifier.Execute(AChange.FilePath, LResult);
    if FConfig.RemoveUnused then
      Inc(ARemoved, Length(LResult.UnusedUnits));
    if FConfig.MoveToImplementation then
      Inc(AMoved, Length(LResult.UnitsToMoveToImpl));
    Log('Cleaned: ' + ExtractFileName(AChange.FilePath));
  end;
  if LHasConfiguredChanges or LHasAmbiguity then
    FReportGen.AddUnitProcessed(AChange.FilePath, LResult.UnusedUnits,
      LResult.UnitsToMoveToImpl, LResult.PreservedAmbiguities);
end;

procedure TProjectCleanerAppService.ProcessUnits(const ABasePath, ADprojPath: string; out ATotalRemoved, ATotalMoved, AUnitCount: Integer; LLogger: ILogger; LContext: TProjectContext; LAnalyzer: TAnalyzeUnitUses; LModifier: TApplyUsesChanges);
var
  LUnits: TArray<string>;
  LIndex: Integer;
  LPlan: TUnitAnalysisPlan;
  LChange: TPlannedUnitChange;
  LSnapshot: IAnalysisSnapshot;
begin
  ATotalRemoved := 0;
  ATotalMoved := 0;
  LUnits := FProjectParser.GetProjectUnits(ADprojPath);
  AUnitCount := Length(LUnits);
  Progress(AUnitCount, 0);
  if AUnitCount = 0 then
  begin
    Log('No units found in project.');
    Exit;
  end;
  if Supports(FASTParser, IAnalysisSnapshot, LSnapshot) then
    LSnapshot.BeginAnalysis;
  LPlan := TUnitAnalysisPlan.Create;
  try
    Log(Format('Analyzing %d units before applying changes.', [AUnitCount]));
    for LIndex := 0 to High(LUnits) do
    begin
      CheckCancellation;
      AnalyzeUnit(ResolvePath(ABasePath, LUnits[LIndex]), LContext, LAnalyzer, LPlan);
      Progress(AUnitCount, LIndex + 1);
    end;
    CheckCancellation;
    if Assigned(LSnapshot) then
      LSnapshot.ValidateAnalysis;
    for LChange in LPlan do
    begin
      CheckCancellation;
      ApplyPlannedUnit(LChange, LModifier, ATotalRemoved, ATotalMoved);
    end;
    CheckCancellation;
  finally
    LPlan.Free;
  end;
end;

function TProjectCleanerAppService.RunFinalBuild(const AFullPath: string; ARemoved, AMoved: Integer): TBuildMetrics;
begin
  Log('Modifications applied. Running final build (After)...');
  Result := RunConfiguredBuilds(AFullPath);
  LogBuildDiagnostics(Result);
  Result.RemovedUnitsCount := ARemoved;
  Result.MovedUnitsCount := AMoved;
end;

function TProjectCleanerAppService.ProcessInlineHints(const AHints: TArray<TInlineHint>; LModifier: TApplyUsesChanges): Integer;
var
  LHint: TInlineHint;
  LContent: string;
begin
  Result := 0;
  for LHint in AHints do
  begin
    if not TFile.Exists(LHint.FilePath) then 
      Continue;
    
    LContent := FFileService.ReadFileContent(LHint.FilePath);
    FFileService.BackupFile(LHint.FilePath);
    
    LContent := TApplyUsesChanges.RemoveUnitFromUsesClause(LContent, LHint.UnitNeeded, False);
    LContent := TApplyUsesChanges.AddUnitToInterfaceUses(LContent, LHint.UnitNeeded);
    
    FFileService.WriteFileContent(LHint.FilePath, LContent);
    Log('Fixed ' + LHint.HintType + ' in ' + ExtractFileName(LHint.FilePath) + ': injected ' + LHint.UnitNeeded);
    Inc(Result);
  end;
end;

procedure TProjectCleanerAppService.RollbackChanges(const AErrorMessage: string);
begin
  Log('ERROR: Final build failed! Restoring backups (Auto-Rollback)...');
  Log('Error: ' + AErrorMessage);
  FFileService.RestoreBackups;
  Log('Rollback complete. Project restored to original state.');
end;

procedure TProjectCleanerAppService.RecordRolledBackReport;
begin
  FReportGen.AddWarning(
    'Final build failed. All listed changes were rolled back; no source changes were retained.');
end;

procedure TProjectCleanerAppService.CommitChanges(const AMetricsBefore,
  AMetricsAfter: TBuildMetrics);
begin
  Log('Final build successful! Committing changes...');
  FFileService.CommitBackups;
  FReportGen.AddMetrics(AMetricsBefore, AMetricsAfter);
end;

procedure TProjectCleanerAppService.GenerateReports(const AOutputDirectory: string);
begin
  Log('');
  Log(FReportGen.GetReportContentTXT);
  
  if FConfig.ExportTXT then
  begin
    FFileService.EnsureDirectory(AOutputDirectory);
    FFileService.WriteFileContent(TPath.Combine(AOutputDirectory, 'AtroposReport.txt'), FReportGen.GetReportContentTXT);
  end;

  if FConfig.ExportHTML then
  begin
    FFileService.EnsureDirectory(AOutputDirectory);
    FFileService.WriteFileContent(TPath.Combine(AOutputDirectory, 'AtroposReport.html'), FReportGen.GetReportContentHTML);
  end;
end;

function TProjectCleanerAppService.ExecuteSafely(const ADprojPath: string): Boolean;
var
  LContext: TProjectContext;
  LLogger: ILogger;
  LAnalyzer: TAnalyzeUnitUses;
  LModifier: TApplyUsesChanges;
  LFullPath: string;
  LBasePath: string;
  LMetricsBefore: TBuildMetrics;
  LMetricsAfter: TBuildMetrics;
  LVerifyMetrics: TBuildMetrics;
  LTotalRemoved: Integer;
  LTotalMoved: Integer;
  LUnitCount: Integer;
  LSearchPathCount: Integer;
  LReportOutputDirectory: string;
  LStopwatch: TStopwatch;
begin
  LStopwatch := TStopwatch.StartNew;
  LUnitCount := 0;
  LFullPath := TPath.GetFullPath(ADprojPath);
  LBasePath := TPath.GetDirectoryName(LFullPath);
  LReportOutputDirectory := FConfig.OutputDirectory;
  if not LReportOutputDirectory.IsEmpty then
    LReportOutputDirectory := ResolvePath(LBasePath, LReportOutputDirectory);
  if LReportOutputDirectory.IsEmpty then
    LReportOutputDirectory := LBasePath;

  FFileService.RecoverPendingBackups(LBasePath);
  
  Log('Analyzing project: ' + LFullPath);
  Log('Loading dependencies... Please wait.');
  
  LSearchPathCount := SetupEnvironment(LFullPath, LBasePath);
  CollectProjectParserWarnings;
  LMetricsBefore := RunBaselineBuild(LFullPath);
  if not LMetricsBefore.Success then
  begin
    Log('Analysis aborted because the baseline build is not healthy. No files were changed.');
    FFileService.RestoreBackups;
    FReportGen.SetAnalysisInfo(ExtractFileName(LFullPath),
      LStopwatch.ElapsedMilliseconds, LUnitCount, LSearchPathCount);
    GenerateReports(LReportOutputDirectory);
    Exit(False);
  end;

  LLogger := CreateLogger;
  LContext := TProjectContext.Create(FResolver, LLogger);
  LAnalyzer := TAnalyzeUnitUses.Create(LLogger);
  LModifier := TApplyUsesChanges.Create(FFileService, FConfig);
  try
    ProcessUnits(LBasePath, ADprojPath, LTotalRemoved, LTotalMoved, LUnitCount, LLogger, LContext, LAnalyzer, LModifier);
    CollectProjectParserWarnings;
    CollectResolverWarnings;
    if (LTotalRemoved = 0) and (LTotalMoved = 0) then
    begin
      Log('No modifications were necessary.');
      FFileService.CommitBackups;
      FReportGen.SetAnalysisInfo(ExtractFileName(LFullPath),
        LStopwatch.ElapsedMilliseconds, LUnitCount, LSearchPathCount);
      GenerateReports(LReportOutputDirectory);
      Exit(True);
    end;
    
    LMetricsAfter := RunFinalBuild(LFullPath, LTotalRemoved, LTotalMoved);
    if not LMetricsAfter.Success then
    begin
      RollbackChanges(LMetricsAfter.ErrorMessage);
      RecordRolledBackReport;
      FReportGen.SetAnalysisInfo(ExtractFileName(LFullPath),
        LStopwatch.ElapsedMilliseconds, LUnitCount, LSearchPathCount);
      GenerateReports(LReportOutputDirectory);
      Exit(False);
    end;
    
    if Length(LMetricsAfter.InlineHints) > 0 then
    begin
      Log(Format('Found %d inline hints (H2443/H2445). Applying post-operative fixes...', [Length(LMetricsAfter.InlineHints)]));
      LMetricsAfter.ResolvedInlineHintsCount := ProcessInlineHints(LMetricsAfter.InlineHints, LModifier);
      
      if LMetricsAfter.ResolvedInlineHintsCount > 0 then
      begin
        Log('Re-verifying build after post-operative fixes...');
        LVerifyMetrics := RunFinalBuild(LFullPath, LTotalRemoved, LTotalMoved);
        if not LVerifyMetrics.Success then
        begin
          RollbackChanges('Verification build failed after resolving inline hints: ' + LVerifyMetrics.ErrorMessage);
          RecordRolledBackReport;
          FReportGen.SetAnalysisInfo(ExtractFileName(LFullPath),
            LStopwatch.ElapsedMilliseconds, LUnitCount, LSearchPathCount);
          GenerateReports(LReportOutputDirectory);
          Exit(False);
        end;
        LVerifyMetrics.ResolvedInlineHintsCount := LMetricsAfter.ResolvedInlineHintsCount;
        LMetricsAfter := LVerifyMetrics;
      end;
    end;
      
    CommitChanges(LMetricsBefore, LMetricsAfter);
    FReportGen.SetAnalysisInfo(ExtractFileName(LFullPath),
      LStopwatch.ElapsedMilliseconds, LUnitCount, LSearchPathCount);
    GenerateReports(LReportOutputDirectory);
    Result := True;
  finally
    LAnalyzer.Free;
    LContext.Free;
    LModifier.Free;
  end;
end;

function TProjectCleanerAppService.Execute(const ADprojPath: string): Boolean;
begin
  try
    Result := ExecuteSafely(ADprojPath);
  except
    FFileService.RestoreBackups;
    raise;
  end;
end;

end.
