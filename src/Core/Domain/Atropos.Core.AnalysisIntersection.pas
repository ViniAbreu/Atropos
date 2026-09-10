unit Atropos.Core.AnalysisIntersection;

interface

uses Atropos.Core.Domain, Atropos.Core.Analysis, System.Generics.Collections;

type
  TAnalysisIntersection = class
  private
    FInitialized: Boolean;
    FResult: TUnitAnalysisResult;
    FDecisions: TList<TDependencyDecision>;
    FAllowed: TDictionary<string, TDependencyAction>;
    FStructured: Boolean;
    procedure IntersectDecisions(const ADecisions: TArray<TDependencyDecision>);
    class function DecisionKey(const ADecision: TDependencyDecision): string; static;
    class function Contains(const AValues: TArray<string>; const AValue: string): Boolean; static;
    class function Intersect(const ALeft, ARight: TArray<string>): TArray<string>; static;
    function IsAllowed(const ADecision: TDependencyDecision): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Include(const ATarget: string; const AAnalysis: TUnitAnalysisResult);
    function Combined: TUnitAnalysisResult;
  end;

implementation

uses System.SysUtils;

constructor TAnalysisIntersection.Create;
begin
  inherited;
  FDecisions := TList<TDependencyDecision>.Create;
  FAllowed := TDictionary<string, TDependencyAction>.Create;
end;

destructor TAnalysisIntersection.Destroy;
begin
  FDecisions.Free;
  FAllowed.Free;
  inherited;
end;

class function TAnalysisIntersection.Contains(const AValues: TArray<string>;
  const AValue: string): Boolean;
var LValue: string;
begin
  for LValue in AValues do
    if SameText(LValue, AValue) then
      Exit(True);
  Result := False;
end;

class function TAnalysisIntersection.Intersect(const ALeft,
  ARight: TArray<string>): TArray<string>;
var LValues: TList<string>; LValue: string;
begin
  LValues := TList<string>.Create;
  try
    for LValue in ALeft do
      if Contains(ARight, LValue) then
        LValues.Add(LValue);
    Result := LValues.ToArray;
  finally
    LValues.Free;
  end;
end;

procedure TAnalysisIntersection.Include(const ATarget: string;
  const AAnalysis: TUnitAnalysisResult);
var LDecision, LTagged: TDependencyDecision; LReason: string;
begin
  IntersectDecisions(AAnalysis.Decisions);
  if not FInitialized then
  begin
    FResult.UnitName := AAnalysis.UnitName;
    FResult.UnusedUnits := Copy(AAnalysis.UnusedUnits);
    FResult.UnitsToMoveToImpl := Copy(AAnalysis.UnitsToMoveToImpl);
    FInitialized := True;
  end;
  FResult.UnusedUnits := Intersect(FResult.UnusedUnits, AAnalysis.UnusedUnits);
  FResult.UnitsToMoveToImpl := Intersect(FResult.UnitsToMoveToImpl, AAnalysis.UnitsToMoveToImpl);
  FResult.PreservedAmbiguities := FResult.PreservedAmbiguities + AAnalysis.PreservedAmbiguities;
  for LReason in AAnalysis.PreservationReasons do
    FResult.PreservationReasons := FResult.PreservationReasons + ['[' + ATarget + '] ' + LReason];
  for LDecision in AAnalysis.Decisions do
  begin
    LTagged := LDecision;
    LTagged.Reason := '[' + ATarget + '] ' + LDecision.Reason;
    FDecisions.Add(LTagged);
  end;
end;

function TAnalysisIntersection.IsAllowed(const ADecision: TDependencyDecision): Boolean;
var LAction: TDependencyAction;
begin
  if FStructured and (ADecision.Action <> daPreserve) then
    Exit(FAllowed.TryGetValue(DecisionKey(ADecision), LAction) and (LAction = ADecision.Action));
  if ADecision.Action = daRemove then
    Exit(Contains(FResult.UnusedUnits, ADecision.UnitName));
  if ADecision.Action = daMoveToImplementation then
    Exit(Contains(FResult.UnitsToMoveToImpl, ADecision.UnitName));
  Result := True;
end;

class function TAnalysisIntersection.DecisionKey(const ADecision: TDependencyDecision): string;
begin
  Result := LowerCase(ADecision.UnitName) + ':' + IntToStr(Ord(ADecision.Section));
end;

procedure TAnalysisIntersection.IntersectDecisions(const ADecisions: TArray<TDependencyDecision>);
var LKey: string; LDecision: TDependencyDecision; LCurrent: TDictionary<string, TDependencyAction>;
  LAction: TDependencyAction;
begin
  LCurrent := TDictionary<string, TDependencyAction>.Create;
  try
    for LDecision in ADecisions do
    begin
      LKey := DecisionKey(LDecision);
      LAction := LDecision.Action;
      if LCurrent.ContainsKey(LKey) and (LCurrent[LKey] <> LAction) then
        LAction := daPreserve;
      if LDecision.State in [dsUnknown, dsAmbiguous] then
        LAction := daPreserve;
      LCurrent.AddOrSetValue(LKey, LAction);
    end;
    if not FInitialized then
    begin
      FStructured := Length(ADecisions) > 0;
      for LKey in LCurrent.Keys do
        FAllowed.Add(LKey, LCurrent[LKey]);
      Exit;
    end;
    for LKey in FAllowed.Keys.ToArray do
      if not LCurrent.TryGetValue(LKey, LAction) or (LAction <> FAllowed[LKey]) then
        FAllowed.Remove(LKey);
  finally
    LCurrent.Free;
  end;
end;

function TAnalysisIntersection.Combined: TUnitAnalysisResult;
var LIndex: Integer; LDecision: TDependencyDecision;
begin
  Result := FResult;
  SetLength(Result.Decisions, FDecisions.Count);
  for LIndex := 0 to FDecisions.Count - 1 do
  begin
    LDecision := FDecisions[LIndex];
    if not IsAllowed(LDecision) then
    begin
      LDecision.Action := daPreserve;
      LDecision.State := dsUnknown;
      LDecision.Reason := LDecision.Reason + '; edit is not supported by every analyzed target.';
      Result.PreservationReasons := Result.PreservationReasons + [LDecision.PreservationMessage];
    end;
    Result.Decisions[LIndex] := LDecision;
  end;
end;

end.
