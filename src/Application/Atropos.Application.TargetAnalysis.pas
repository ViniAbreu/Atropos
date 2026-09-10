unit Atropos.Application.TargetAnalysis;

interface

uses System.Generics.Collections, Atropos.Core.Ports, Atropos.Core.Compilation,
  Atropos.Core.Domain, Atropos.Core.AnalysisIntersection,
  Atropos.Application.AnalysisPlan;

type
  TTargetAnalysisWorkflow = class
  private
    FProvider: IProjectContextProvider;
    FFactory: ITargetAnalysisFactory;
    FReport: IReportGenerator;
    FLog: TLogEvent;
    FLogger: ILogger;
    FCancel: TCancellationCheck;
    FSnapshots: TList<IAnalysisSnapshot>;
    FMerged: TObjectDictionary<string, TAnalysisIntersection>;
    FPaths: TDictionary<string, string>;
    FSearchPaths: TList<string>;
    procedure CheckCancellation;
    procedure AnalyzeTarget(const AContext: TProjectCompilationContext;
      const ADelphiPath: string; const AUnits: TArray<string>);
    procedure AnalyzeUnit(const APath, ATarget: string; const AParser: IASTParser;
      AContext: TProjectContext; AAnalyzer: TAnalyzeUnitUses);
    function CollectContexts(const AProjectPath, ADelphiPath: string;
      const ATargets: TArray<TBuildTarget>): TArray<TProjectCompilationContext>;
    function CreatePlan: TUnitAnalysisPlan;
  public
    constructor Create(const AProvider: IProjectContextProvider;
      const AFactory: ITargetAnalysisFactory; const AReport: IReportGenerator;
      const ALog: TLogEvent; const ACancel: TCancellationCheck; const ALogger: ILogger);
    destructor Destroy; override;
    function BuildPlan(const AProjectPath, ADelphiPath: string;
      const ATargets: TArray<TBuildTarget>; out AUnitCount, ASearchPathCount: Integer): TUnitAnalysisPlan;
  end;

implementation

uses System.SysUtils, System.IOUtils;

constructor TTargetAnalysisWorkflow.Create(const AProvider: IProjectContextProvider;
  const AFactory: ITargetAnalysisFactory; const AReport: IReportGenerator;
  const ALog: TLogEvent; const ACancel: TCancellationCheck; const ALogger: ILogger);
begin
  inherited Create;
  FProvider := AProvider;
  FFactory := AFactory;
  FReport := AReport;
  FLog := ALog;
  FLogger := ALogger;
  FCancel := ACancel;
  FSnapshots := TList<IAnalysisSnapshot>.Create;
  FMerged := TObjectDictionary<string, TAnalysisIntersection>.Create([doOwnsValues]);
  FPaths := TDictionary<string, string>.Create;
  FSearchPaths := TList<string>.Create;
end;

destructor TTargetAnalysisWorkflow.Destroy;
begin
  FSearchPaths.Free;
  FPaths.Free;
  FMerged.Free;
  FSnapshots.Free;
  inherited;
end;

procedure TTargetAnalysisWorkflow.CheckCancellation;
begin
  if Assigned(FCancel) and FCancel() then
    raise EAbort.Create('Operation cancelled by user.');
end;

function TTargetAnalysisWorkflow.CollectContexts(const AProjectPath,
  ADelphiPath: string; const ATargets: TArray<TBuildTarget>): TArray<TProjectCompilationContext>;
var
  LTargets: TArray<TBuildTarget>;
  LIndex: Integer;
  LPath: string;
begin
  LTargets := ATargets;
  if Length(LTargets) = 0 then
    LTargets := [Default(TBuildTarget)];
  SetLength(Result, Length(LTargets));
  for LIndex := 0 to High(LTargets) do
  begin
    CheckCancellation;
    Result[LIndex] := FProvider.EvaluateProject(AProjectPath, ADelphiPath, LTargets[LIndex]);
    for LPath in Result[LIndex].UnitPaths do
      FPaths.AddOrSetValue(TPath.GetFullPath(LPath).ToLowerInvariant, TPath.GetFullPath(LPath));
    for LPath in Result[LIndex].SearchPaths do
      if not FSearchPaths.Contains(LPath) then
        FSearchPaths.Add(LPath);
  end;
end;

procedure TTargetAnalysisWorkflow.AnalyzeUnit(const APath, ATarget: string;
  const AParser: IASTParser; AContext: TProjectContext; AAnalyzer: TAnalyzeUnitUses);
var
  LResult: TUnitAnalysisResult;
  LKey: string;
  LIntersection: TAnalysisIntersection;
begin
  CheckCancellation;
  LResult := Default(TUnitAnalysisResult);
  try
    LResult := AAnalyzer.Execute(AParser.ParseFile(APath), AContext);
  except
    on E: Exception do
      LResult.PreservationReasons := ['unknown analysis for ' + APath + ': ' + E.Message];
  end;
  LKey := APath.ToLowerInvariant;
  if not FMerged.TryGetValue(LKey, LIntersection) then
  begin
    LIntersection := TAnalysisIntersection.Create;
    FMerged.Add(LKey, LIntersection);
  end;
  LIntersection.Include(ATarget, LResult);
end;

procedure TTargetAnalysisWorkflow.AnalyzeTarget(const AContext: TProjectCompilationContext;
  const ADelphiPath: string; const AUnits: TArray<string>);
var
  LServices: TTargetAnalysisServices;
  LSnapshot: IAnalysisSnapshot;
  LInputs: IProjectSnapshotInputs;
  LContext: TProjectContext;
  LAnalyzer: TAnalyzeUnitUses;
  LPath, LTarget, LWarning: string;
begin
  LTarget := AContext.Target.Configuration + '|' + AContext.Target.Platform;
  if Assigned(FLog) then
    FLog('Analyzing target ' + LTarget + '...');
  CheckCancellation;
  LServices := FFactory.CreateForTarget(AContext, ADelphiPath);
  if Supports(LServices.Parser, IAnalysisSnapshot, LSnapshot) then
  begin
    LSnapshot.BeginAnalysis;
    FSnapshots.Add(LSnapshot);
  end;
  if Supports(LServices.Parser, IProjectSnapshotInputs, LInputs) then
    LInputs.RegisterProjectInputs(AContext.ProjectFiles);
  LContext := TProjectContext.Create(LServices.Resolver, FLogger);
  LAnalyzer := TAnalyzeUnitUses.Create(FLogger);
  try
    for LPath in AUnits do
      AnalyzeUnit(LPath, LTarget, LServices.Parser, LContext, LAnalyzer);
    for LWarning in LServices.Resolver.GetWarnings do
      FReport.AddWarning('[' + LTarget + '] ' + LWarning);
  finally
    LAnalyzer.Free;
    LContext.Free;
  end;
end;

function TTargetAnalysisWorkflow.CreatePlan: TUnitAnalysisPlan;
var
  LPair: TPair<string, TAnalysisIntersection>;
  LAnalysis: TUnitAnalysisResult;
  LReason: string;
begin
  Result := TUnitAnalysisPlan.Create;
  try
    for LPair in FMerged do
    begin
      LAnalysis := LPair.Value.Combined;
      for LReason in LAnalysis.PreservationReasons do
        FReport.AddWarning(FPaths[LPair.Key] + ': preserved ' + LReason);
      Result.Add(FPaths[LPair.Key], LAnalysis);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TTargetAnalysisWorkflow.BuildPlan(const AProjectPath, ADelphiPath: string;
  const ATargets: TArray<TBuildTarget>; out AUnitCount, ASearchPathCount: Integer): TUnitAnalysisPlan;
var
  LContexts: TArray<TProjectCompilationContext>;
  LContext: TProjectCompilationContext;
  LUnits: TArray<string>;
  LSnapshot: IAnalysisSnapshot;
begin
  LContexts := CollectContexts(AProjectPath, ADelphiPath, ATargets);
  LUnits := FPaths.Values.ToArray;
  TArray.Sort<string>(LUnits);
  AUnitCount := Length(LUnits);
  ASearchPathCount := FSearchPaths.Count;
  for LContext in LContexts do
    AnalyzeTarget(LContext, ADelphiPath, LUnits);
  CheckCancellation;
  for LSnapshot in FSnapshots do
    LSnapshot.ValidateAnalysis;
  Result := CreatePlan;
end;

end.
