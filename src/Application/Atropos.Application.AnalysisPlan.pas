unit Atropos.Application.AnalysisPlan;

interface

uses System.Generics.Collections, Atropos.Core.Domain;

type
  TPlannedUnitChange = record
    FilePath: string;
    Analysis: TUnitAnalysisResult;
  end;

  TUnitAnalysisPlan = class
  private
    FEntries: TList<TPlannedUnitChange>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AFilePath: string; const AAnalysis: TUnitAnalysisResult);
    function GetEnumerator: TList<TPlannedUnitChange>.TEnumerator;
  end;

implementation

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
