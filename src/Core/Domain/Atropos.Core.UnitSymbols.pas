unit Atropos.Core.UnitSymbols;
interface
uses System.Generics.Collections;
type
  TUnitExports = class
  public
    UnitName: string;
    ExportedIdentifiers: TList<string>;
    ExportedHelpers: TObjectDictionary<string, TList<string>>;
    HasInitialization: Boolean;
    Imports: TArray<string>;
    ImportsKnown: Boolean;
    IsNative: Boolean;
    constructor Create(const AUnitName: string; AHasInit: Boolean = False; AIsNative: Boolean = False);
    destructor Destroy; override;
    function MatchesLegacyHelper(const AName: string; const AIdentifiers: TArray<string>): Boolean;
  end;
implementation
uses System.SysUtils;

function TUnitExports.MatchesLegacyHelper(const AName: string;
  const AIdentifiers: TArray<string>): Boolean;
var LTargets: TList<string>; LTarget, LIdentifier: string;
begin
  Result := False;
  if not ExportedHelpers.TryGetValue(AName, LTargets) then
    Exit;
  for LTarget in LTargets do
  begin
    if (LTarget = 'string') or (LTarget = 'integer') or (LTarget = 'tobject') then
      Exit(True);
    for LIdentifier in AIdentifiers do
      if SameText(LIdentifier, LTarget) then
        Exit(True);
  end;
end;

constructor TUnitExports.Create(const AUnitName: string; AHasInit: Boolean = False; AIsNative: Boolean = False);
begin
  UnitName := AUnitName;
  HasInitialization := AHasInit;
  ImportsKnown := False;
  IsNative := AIsNative;
  ExportedIdentifiers := TList<string>.Create;
  ExportedHelpers := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
end;

destructor TUnitExports.Destroy;
begin
  ExportedHelpers.Free;
  ExportedIdentifiers.Free;
  inherited;
end;

end.
