unit Atropos.Core.UsesEditPlan;

interface

uses Atropos.Core.Domain, Atropos.Core.Analysis, Atropos.Core.Config,
  Atropos.Core.UsesSyntax, Atropos.Core.UsesEditor, System.Generics.Collections;

type
  TUsesEditPlan = record
    Original, Updated: string;
    Warnings: TArray<string>;
    Analysis: TUnitAnalysisResult;
    function HasChanges: Boolean;
  end;
  TUsesEditPlanner = class
  private
    FDocument: TUsesSource;
    FEditor: TUsesEditor;
    FConfig: TToolConfig;
    FPath: string;
    function PositionOf(const ADecision: TDependencyDecision): Integer;
    function LegacyDecisions(const AAnalysis: TUnitAnalysisResult): TArray<TDependencyDecision>;
    procedure Apply(var ADecision: TDependencyDecision);
    function Conflicted(const ADecision: TDependencyDecision;
      const ADecisions: TArray<TDependencyDecision>): Boolean;
  public
    constructor Create(const ASource, APath: string; const AConfig: TToolConfig);
    destructor Destroy; override;
    function Prepare(const AAnalysis: TUnitAnalysisResult): TUsesEditPlan;
  end;

implementation

uses System.SysUtils, System.Generics.Defaults;

function TUsesEditPlanner.PositionOf(const ADecision: TDependencyDecision): Integer;
var LClause: TUsesClause; LIndex: Integer;
begin
  Result := 0;
  if FDocument.Find(ADecision.UnitName, ADecision.Section, LClause, LIndex) then
    Result := LClause.Entries[LIndex].StartOffset;
end;

function TUsesEditPlan.HasChanges: Boolean;
begin
  Result := Original <> Updated;
end;

constructor TUsesEditPlanner.Create(const ASource, APath: string; const AConfig: TToolConfig);
begin
  inherited Create;
  FPath := APath;
  FConfig := AConfig;
  FDocument := TUsesSource.Create(ASource);
  FEditor := TUsesEditor.Create(ASource);
end;

destructor TUsesEditPlanner.Destroy;
begin
  FEditor.Free;
  FDocument.Free;
  inherited;
end;

function TUsesEditPlanner.LegacyDecisions(const AAnalysis: TUnitAnalysisResult): TArray<TDependencyDecision>;
var LItems: TList<TDependencyDecision>; LName: string; LSection: TUsesSection;
begin
  LItems := TList<TDependencyDecision>.Create;
  try
    for LName in AAnalysis.UnusedUnits do
      for LSection := Low(TUsesSection) to High(TUsesSection) do
        LItems.Add(TDependencyDecision.Create(LName, LSection, dsUnused, daRemove, 'Legacy removal request.'));
    for LName in AAnalysis.UnitsToMoveToImpl do
      LItems.Add(TDependencyDecision.Create(LName, usInterface, dsUsed, daMoveToImplementation, 'Legacy move request.'));
    Result := LItems.ToArray;
  finally
    LItems.Free;
  end;
end;

function TUsesEditPlanner.Conflicted(const ADecision: TDependencyDecision;
  const ADecisions: TArray<TDependencyDecision>): Boolean;
var LOther: TDependencyDecision;
begin
  for LOther in ADecisions do
    if SameText(LOther.UnitName, ADecision.UnitName) and (LOther.Section = ADecision.Section) and
      ((LOther.Action <> ADecision.Action) or
       ((ADecision.Action <> daPreserve) and (LOther.State in [dsUnknown, dsAmbiguous]))) then
      Exit(True);
  Result := False;
end;

procedure TUsesEditPlanner.Apply(var ADecision: TDependencyDecision);
var LClause: TUsesClause; LIndex: Integer; LEntry: TUsesOccurrence; LChanged: Boolean;
begin
  if ADecision.Action = daPreserve then
    Exit;
  if ((ADecision.Action = daRemove) and not FConfig.RemoveUnused) or
    ((ADecision.Action = daMoveToImplementation) and not FConfig.MoveToImplementation) then
  begin
    ADecision.Action := daPreserve;
    Exit;
  end;
  LChanged := False;
  if FDocument.Find(ADecision.UnitName, ADecision.Section, LClause, LIndex) then
  begin
    LEntry := LClause.Entries[LIndex];
    ADecision.Occurrence.FilePath := FPath;
    ADecision.Occurrence.Condition := LEntry.Condition;
    ADecision.Occurrence.StartOffset := LEntry.StartOffset;
    ADecision.Occurrence.EndOffset := LEntry.EndOffset;
    if ADecision.Action = daRemove then
      LChanged := FEditor.Remove(ADecision.UnitName, ADecision.Section);
    if (ADecision.Action = daMoveToImplementation) and (ADecision.Section = usInterface) then
      LChanged := FEditor.Move(ADecision.UnitName);
  end;
  if LChanged then
    Exit;
  ADecision.Action := daPreserve;
  ADecision.State := dsUnknown;
  ADecision.Reason := 'Original import occurrence is absent, ambiguous or cannot be edited safely.';
end;

function TUsesEditPlanner.Prepare(const AAnalysis: TUnitAnalysisResult): TUsesEditPlan;
var LDecisions: TArray<TDependencyDecision>; LDone: TDictionary<string, TDependencyDecision>;
  LKey: string; I: Integer; LDecision, LPrevious: TDependencyDecision;
  LRemoved, LMoved: TList<string>;
begin
  Result := Default(TUsesEditPlan);
  Result.Original := FDocument.Source;
  Result.Analysis := AAnalysis;
  LDecisions := Copy(AAnalysis.Decisions);
  if Length(LDecisions) = 0 then
    LDecisions := LegacyDecisions(AAnalysis);
  TArray.Sort<TDependencyDecision>(LDecisions,
    TComparer<TDependencyDecision>.Construct(
      function(const ALeft, ARight: TDependencyDecision): Integer
      begin Result := PositionOf(ALeft) - PositionOf(ARight) end));
  LDone := TDictionary<string, TDependencyDecision>.Create;
  LRemoved := TList<string>.Create;
  LMoved := TList<string>.Create;
  try
    // Prepending in reverse preserves the original ordering of moved imports.
    for I := High(LDecisions) downto 0 do
    begin
      LDecision := LDecisions[I];
      LKey := LowerCase(LDecision.UnitName) + ':' + IntToStr(Ord(LDecision.Section));
      if LDone.TryGetValue(LKey, LPrevious) then
      begin
        LDecisions[I] := LPrevious;
        Continue;
      end;
      if Conflicted(LDecision, AAnalysis.Decisions) then
      begin
        LDecision.Action := daPreserve;
        LDecision.State := dsUnknown;
        LDecision.Reason := 'Conflicting decisions for the same import occurrence.';
      end;
      Apply(LDecision);
      LDone.Add(LKey, LDecision);
      LDecisions[I] := LDecision;
    end;
    for LDecision in LDecisions do
    begin
      if (LDecision.Action = daRemove) and not LRemoved.Contains(LDecision.UnitName) then
        LRemoved.Add(LDecision.UnitName);
      if (LDecision.Action = daMoveToImplementation) and not LMoved.Contains(LDecision.UnitName) then
        LMoved.Add(LDecision.UnitName);
      if (LDecision.State = dsUnknown) and
        (LDecision.Reason.StartsWith('Original import occurrence') or
         LDecision.Reason.StartsWith('Conflicting decisions')) then
      begin
        Result.Analysis.PreservationReasons := Result.Analysis.PreservationReasons + [LDecision.PreservationMessage];
        Result.Warnings := Result.Warnings + [LDecision.PreservationMessage];
      end;
    end;
    Result.Analysis.Decisions := LDecisions;
    Result.Analysis.UnusedUnits := LRemoved.ToArray;
    Result.Analysis.UnitsToMoveToImpl := LMoved.ToArray;
    Result.Updated := FEditor.Source;
  finally
    LMoved.Free;
    LRemoved.Free;
    LDone.Free;
  end;
end;

end.
