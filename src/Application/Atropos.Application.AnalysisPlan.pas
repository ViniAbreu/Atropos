unit Atropos.Application.AnalysisPlan;

interface

uses System.Generics.Collections, Atropos.Core.Domain, Atropos.Core.Modifier,
  Atropos.Core.UsesEditPlan;

type
  TPlannedUnitChange = record
    FilePath: string;
    Analysis: TUnitAnalysisResult;
    Editing: TUsesEditPlan;
  end;

  TUnitAnalysisPlan = class
  private
    FEntries: TList<TPlannedUnitChange>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AFilePath: string; const AAnalysis: TUnitAnalysisResult);
    procedure Prepare(AModifier: TApplyUsesChanges);
    function GetEnumerator: TList<TPlannedUnitChange>.TEnumerator;
  end;

implementation

procedure TUnitAnalysisPlan.Prepare(AModifier: TApplyUsesChanges);
var I: Integer; LEntry: TPlannedUnitChange;
begin
  for I := 0 to FEntries.Count - 1 do
  begin
    LEntry := FEntries[I];
    LEntry.Editing := AModifier.Prepare(LEntry.FilePath, LEntry.Analysis);
    LEntry.Analysis := LEntry.Editing.Analysis;
    FEntries[I] := LEntry;
  end;
end;

constructor TUnitAnalysisPlan.Create;
begin
  inherited;
  FEntries := TList<TPlannedUnitChange>.Create;
end;

destructor TUnitAnalysisPlan.Destroy;
begin
  FEntries.Free;
  inherited;
end;

procedure TUnitAnalysisPlan.Add(const AFilePath: string;
  const AAnalysis: TUnitAnalysisResult);
var
  LEntry: TPlannedUnitChange;
begin
  LEntry.FilePath := AFilePath;
  LEntry.Analysis := AAnalysis;
  FEntries.Add(LEntry);
end;

function TUnitAnalysisPlan.GetEnumerator: TList<TPlannedUnitChange>.TEnumerator;
begin
  Result := FEntries.GetEnumerator;
end;

end.
