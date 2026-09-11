unit Atropos.Core.Effects;

interface

uses System.Generics.Collections;

type
  TEffectState = (esNone, esPresent, esUnknown);
  TUnitEffectFacts = record
    DirectEffects: Boolean;
    ImportsKnown: Boolean;
    Imports: TArray<string>;
  end;
  TEffectAssessment = record
    State: TEffectState;
    Reason: string;
  end;
  TEffectLookup = reference to function(const AUnitName: string): TUnitEffectFacts;

  TUnitEffectGraph = class
  private
    FPending: TQueue<string>;
    FPaths: TDictionary<string, string>;
    procedure Enqueue(const AName, APath: string);
    procedure AddImports(const AImports: TArray<string>; const APath: string);
  public
    constructor Create;
    destructor Destroy; override;
    function Assess(const AUnitName: string; const ALookup: TEffectLookup): TEffectAssessment;
  end;

implementation

uses System.SysUtils;

constructor TUnitEffectGraph.Create;
begin
  inherited;
  FPending := TQueue<string>.Create;
  FPaths := TDictionary<string, string>.Create;
end;

destructor TUnitEffectGraph.Destroy;
begin
  FPaths.Free;
  FPending.Free;
  inherited;
end;

procedure TUnitEffectGraph.Enqueue(const AName, APath: string);
begin
  if FPaths.ContainsKey(AName.ToLowerInvariant) then
    Exit;
  FPaths.Add(AName.ToLowerInvariant, APath);
  FPending.Enqueue(AName);
end;

procedure TUnitEffectGraph.AddImports(const AImports: TArray<string>; const APath: string);
var LImport: string;
begin
  for LImport in AImports do
    Enqueue(LImport, APath + ' -> ' + LImport);
end;

function TUnitEffectGraph.Assess(const AUnitName: string;
  const ALookup: TEffectLookup): TEffectAssessment;
var LName, LPath: string; LFacts: TUnitEffectFacts;
begin
  FPending.Clear;
  FPaths.Clear;
  Result := Default(TEffectAssessment);
  Enqueue(AUnitName, AUnitName);
  while FPending.Count > 0 do
  begin
    LName := FPending.Dequeue;
    LPath := FPaths[LName.ToLowerInvariant];
    LFacts := ALookup(LName);
    if LFacts.DirectEffects then
    begin
      Result.State := esPresent;
      Result.Reason := 'Known lifecycle effects via ' + LPath + '.';
      Exit;
    end;
    if not LFacts.ImportsKnown then
    begin
      Result.State := esUnknown;
      if Result.Reason.IsEmpty then
        Result.Reason := 'Incomplete lifecycle dependency graph via ' + LPath + '.';
    end;
    AddImports(LFacts.Imports, LPath);
  end;
end;

end.
