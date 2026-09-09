unit Atropos.Core.Analysis;

interface

uses System.Generics.Collections;

type
  TUsesSection = (usInterface, usImplementation);
  TDependencyState = (dsUsed, dsUnused, dsAmbiguous, dsUnknown);
  TDependencyAction = (daPreserve, daRemove, daMoveToImplementation);

  TDependencyDecision = record
    UnitName: string;
    Section: TUsesSection;
    State: TDependencyState;
    Action: TDependencyAction;
    Reason: string;
    class function Create(const AUnitName: string; ASection: TUsesSection;
      AState: TDependencyState; AAction: TDependencyAction;
      const AReason: string): TDependencyDecision; static;
    function PreservationMessage: string;
  end;

  TDependencyDecisions = class
  private
    FItems: TList<TDependencyDecision>;
    function EveryOccurrenceRemovable(const AUnitName: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const ADecision: TDependencyDecision);
    function ToArray: TArray<TDependencyDecision>;
    function UnitsForAction(AAction: TDependencyAction): TArray<string>;
    function PreservationMessages: TArray<string>;
  end;

implementation

uses System.SysUtils;

class function TDependencyDecision.Create(const AUnitName: string;
  ASection: TUsesSection; AState: TDependencyState; AAction: TDependencyAction;
  const AReason: string): TDependencyDecision;
begin
  if (AState in [dsUnknown, dsAmbiguous]) and (AAction <> daPreserve) then
    raise EArgumentException.Create('Uncertain dependencies must be preserved.');
  Result.UnitName := AUnitName;
  Result.Section := ASection;
  Result.State := AState;
  Result.Action := AAction;
  Result.Reason := AReason;
end;

function TDependencyDecision.PreservationMessage: string;
const
  SectionNames: array[TUsesSection] of string = ('interface', 'implementation');
  StateNames: array[TDependencyState] of string =
    ('used', 'unused', 'ambiguous', 'unknown');
begin
  Result := Format('%s [%s, %s]: %s', [UnitName, SectionNames[Section],
    StateNames[State], Reason]);
end;

constructor TDependencyDecisions.Create;
begin
  inherited Create;
  FItems := TList<TDependencyDecision>.Create;
end;

destructor TDependencyDecisions.Destroy;
begin
  FItems.Free;
  inherited;
end;

procedure TDependencyDecisions.Add(const ADecision: TDependencyDecision);
begin
  FItems.Add(ADecision);
end;

function TDependencyDecisions.ToArray: TArray<TDependencyDecision>;
begin
  Result := FItems.ToArray;
end;

function TDependencyDecisions.EveryOccurrenceRemovable(
  const AUnitName: string): Boolean;
var
  LDecision: TDependencyDecision;
begin
  for LDecision in FItems do
  begin
    if not SameText(LDecision.UnitName, AUnitName) then
      Continue;
    if LDecision.Action <> daRemove then
      Exit(False);
  end;
  Result := True;
end;

function TDependencyDecisions.UnitsForAction(
  AAction: TDependencyAction): TArray<string>;
var
  LDecision: TDependencyDecision;
  LNames: TList<string>;
begin
  LNames := TList<string>.Create;
  try
    for LDecision in FItems do
    begin
      if LDecision.Action <> AAction then
        Continue;
      if (AAction = daRemove) and not EveryOccurrenceRemovable(LDecision.UnitName) then
        Continue;
      if not LNames.Contains(LDecision.UnitName) then
        LNames.Add(LDecision.UnitName);
    end;
    Result := LNames.ToArray;
  finally
    LNames.Free;
  end;
end;

function TDependencyDecisions.PreservationMessages: TArray<string>;
var
  LDecision: TDependencyDecision;
  LMessages: TList<string>;
begin
  LMessages := TList<string>.Create;
  try
    for LDecision in FItems do
    begin
      if not (LDecision.State in [dsUnknown, dsAmbiguous]) then
        Continue;
      LMessages.Add(LDecision.PreservationMessage);
    end;
    Result := LMessages.ToArray;
  finally
    LMessages.Free;
  end;
end;

end.
