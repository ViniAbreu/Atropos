unit Atropos.Application.AppService;

interface
uses
  Atropos.Core.Ports,
  Atropos.Core.Config,
  Atropos.Core.Domain,
  Atropos.Core.Modifier,
  System.Generics.Collections;

type
  TProgressEvent = reference to procedure(AMax, APosition: Integer);
  TLogEvent = reference to procedure(const AMsg: string);

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
    procedure ProcessUnits(const ABasePath, ADprojPath: string; out ATotalRemoved, ATotalMoved, AUnitCount: Integer; LLogger: ILogger; LContext: TProjectContext; LAnalyzer: TAnalyzeUnitUses; LModifier: TApplyUsesChanges);
    function RunFinalBuild(const AFullPath: string; ARemoved, AMoved: Integer): TBuildMetrics;
    function ProcessInlineHints(const AHints: TArray<TInlineHint>; LModifier: TApplyUsesChanges): Integer;
    procedure CommitChanges(const AMetricsBefore, AMetricsAfter: TBuildMetrics; const AFullPath: string; ATimeMs, AUnitCount, ASearchPathCount: Integer);
    procedure RollbackChanges(const AErrorMessage: string);
    procedure GenerateReports;
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
  if LDelphiPath.IsEmpty then
    Log('WARNING: Delphi environment not found. Standard RTL/VCL units will not be resolved and will be ignored.');

  LSearchPaths := FProjectParser.GetSearchPaths(AFullPath) + [ABasePath];
  
  FResolver.Initialize(LSearchPaths, LDelphiPath, ABasePath);
  Result := Length(LSearchPaths);
end;

function TProjectCleanerAppService.RunBaselineBuild(const AFullPath: string): TBuildMetrics;
begin
  Log('Running baseline build (Before)...');
  Result := FBuildService.BuildProject(AFullPath);
  if not Result.Success then
  begin
    Log('WARNING: Baseline build failed! Metrics will be collected, but rollback comparison might be inaccurate.');
    Log('Error: ' + Result.ErrorMessage);
    Exit;
  end;
  
  Log(Format('Baseline build successful. Hints: %d, Warnings: %d', [Result.Hints, Result.Warnings]));
  Log('Delphi Version: ' + Result.DelphiVersion);
end;

procedure TProjectCleanerAppService.ProcessUnits(const ABasePath, ADprojPath: string; out ATotalRemoved, ATotalMoved, AUnitCount: Integer; LLogger: ILogger; LContext: TProjectContext; LAnalyzer: TAnalyzeUnitUses; LModifier: TApplyUsesChanges);
var
  LUnits: TArray<string>;
  LUnit: string;
  LUnitPath: string;
  i: Integer;
  LResult: TUnitAnalysisResult;
  LSyntaxTree: IUnitSyntaxTree;
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

  Log(Format('Found %d units to process.', [AUnitCount]));
  
  for i := 0 to High(LUnits) do
  begin
    if Assigned(FShouldCancel) and FShouldCancel() then
      raise EAbort.Create('Operation cancelled by user.');
    LUnit := LUnits[i];
    LUnitPath := ResolvePath(ABasePath, LUnit);
    
    if not TFile.Exists(LUnitPath) then
    begin
      Log('Warning: File not found -> ' + LUnitPath);
      Progress(AUnitCount, i + 1);
      Continue;
    end;
    
    try
      LSyntaxTree := FASTParser.ParseFile(LUnitPath);
      LResult := LAnalyzer.Execute(LSyntaxTree, LContext);
    except
      on E: Exception do
      begin
        Log('Error processing ' + ExtractFileName(LUnitPath) + ': ' + E.Message);
        Progress(AUnitCount, i + 1);
        Continue;
      end;
    end;

    if (FConfig.RemoveUnused and (Length(LResult.UnusedUnits) > 0)) or
      (FConfig.MoveToImplementation and (Length(LResult.UnitsToMoveToImpl) > 0)) then
    begin
      LModifier.Execute(LUnitPath, LResult);
      Inc(ATotalRemoved, Length(LResult.UnusedUnits));
      Inc(ATotalMoved, Length(LResult.UnitsToMoveToImpl));
      FReportGen.AddUnitProcessed(LUnitPath, LResult.UnusedUnits, LResult.UnitsToMoveToImpl);
      Log('Cleaned: ' + ExtractFileName(LUnitPath));
    end;
    
    Progress(AUnitCount, i + 1);
  end;
end;

function TProjectCleanerAppService.RunFinalBuild(const AFullPath: string; ARemoved, AMoved: Integer): TBuildMetrics;
begin
  Log('Modifications applied. Running final build (After)...');
  Result := FBuildService.BuildProject(AFullPath);
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

procedure TProjectCleanerAppService.CommitChanges(const AMetricsBefore, AMetricsAfter: TBuildMetrics; const AFullPath: string; ATimeMs, AUnitCount, ASearchPathCount: Integer);
begin
  Log('Final build successful! Committing changes...');
  FFileService.CommitBackups;
  FReportGen.SetAnalysisInfo(ExtractFileName(AFullPath), ATimeMs, AUnitCount, ASearchPathCount);
  FReportGen.AddMetrics(AMetricsBefore, AMetricsAfter);
end;

procedure TProjectCleanerAppService.GenerateReports;
begin
  Log('');
  Log(FReportGen.GetReportContentTXT);
  
  if FConfig.ExportTXT then
    FFileService.WriteFileContent(TPath.Combine(ExtractFilePath(ParamStr(0)), 'AtroposReport.txt'), FReportGen.GetReportContentTXT);

  if FConfig.ExportHTML then
    FFileService.WriteFileContent(TPath.Combine(ExtractFilePath(ParamStr(0)), 'AtroposReport.html'), FReportGen.GetReportContentHTML);
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
  LStopwatch: TStopwatch;
begin
  LStopwatch := TStopwatch.StartNew;
  LFullPath := TPath.GetFullPath(ADprojPath);
  LBasePath := TPath.GetDirectoryName(LFullPath);
  
  Log('Analyzing project: ' + LFullPath);
  Log('Loading dependencies... Please wait.');
  
  LSearchPathCount := SetupEnvironment(LFullPath, LBasePath);
  LMetricsBefore := RunBaselineBuild(LFullPath);
  if not LMetricsBefore.Success then
  begin
    Log('Analysis aborted because the baseline build is not healthy. No files were changed.');
    GenerateReports;
    Exit(False);
  end;

  LLogger := CreateLogger;
  LContext := TProjectContext.Create(FResolver, LLogger);
  LAnalyzer := TAnalyzeUnitUses.Create(LLogger);
  LModifier := TApplyUsesChanges.Create(FFileService, FConfig);
  try
    ProcessUnits(LBasePath, ADprojPath, LTotalRemoved, LTotalMoved, LUnitCount, LLogger, LContext, LAnalyzer, LModifier);
    
    if (LTotalRemoved = 0) and (LTotalMoved = 0) then
    begin
      Log('No modifications were necessary.');
      FFileService.CommitBackups;
      GenerateReports;
      Exit(True);
    end;
    
    LMetricsAfter := RunFinalBuild(LFullPath, LTotalRemoved, LTotalMoved);
    if not LMetricsAfter.Success then
    begin
      RollbackChanges(LMetricsAfter.ErrorMessage);
      GenerateReports;
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
          GenerateReports;
          Exit(False);
        end;
        LVerifyMetrics.ResolvedInlineHintsCount := LMetricsAfter.ResolvedInlineHintsCount;
        LMetricsAfter := LVerifyMetrics;
      end;
    end;
      
    CommitChanges(LMetricsBefore, LMetricsAfter, LFullPath, LStopwatch.ElapsedMilliseconds, LUnitCount, LSearchPathCount);
    GenerateReports;
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
