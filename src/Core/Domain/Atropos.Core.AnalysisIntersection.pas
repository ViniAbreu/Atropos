unit Atropos.Core.AnalysisIntersection;

interface

uses Atropos.Core.Domain, Atropos.Core.Analysis, System.Generics.Collections;

type
  TAnalysisIntersection = class
  private
    FInitialized: Boolean;
    FResult: TUnitAnalysisResult;
    FDecisions: TList<TDependencyDecision>;
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
end;

destructor TAnalysisIntersection.Destroy;
begin
  FDecisions.Free;
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
begin
  if ADecision.Action = daRemove then
    Exit(Contains(FResult.UnusedUnits, ADecision.UnitName));
  if ADecision.Action = daMoveToImplementation then
    Exit(Contains(FResult.UnitsToMoveToImpl, ADecision.UnitName));
  Result := True;
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
