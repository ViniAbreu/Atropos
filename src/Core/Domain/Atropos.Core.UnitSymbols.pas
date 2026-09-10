unit Atropos.Core.UnitSymbols;
interface
uses System.Generics.Collections, Atropos.Core.Ports;
type
  TUnitExports = class
  public
    UnitName: string;
    ExportedIdentifiers: TList<string>;
    ExportedHelpers: TObjectDictionary<string, TList<string>>;
    HasInitialization: Boolean;
    UnknownEffects: string;
    Imports: TArray<string>;
    ImportsKnown: Boolean;
    IsNative: Boolean;
    constructor Create(const AUnitName: string; AHasInit: Boolean = False; AIsNative: Boolean = False);
    destructor Destroy; override;
    procedure AddIdentifiers(const AIdentifiers: TArray<string>);
    procedure SetImplicitEffects(const AEffects: TArray<TImplicitEffect>; AKnown: Boolean);
    function MatchesLegacyHelper(const AName: string; const AIdentifiers: TArray<string>): Boolean;
  end;
implementation
uses System.SysUtils;

procedure TUnitExports.SetImplicitEffects(const AEffects: TArray<TImplicitEffect>; AKnown: Boolean);
var LEffect: TImplicitEffect;
begin
  UnknownEffects := '';
  if not AKnown then
  begin
    UnknownEffects := 'Implicit lifecycle metadata is unavailable.';
    Exit;
  end;
  for LEffect in AEffects do
  begin
    if LEffect.Definite then
    begin
      HasInitialization := True;
      Continue;
    end;
    if not UnknownEffects.IsEmpty then
      UnknownEffects := UnknownEffects + '; ';
    UnknownEffects := UnknownEffects + LEffect.Reason;
  end;
end;

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

procedure TUnitExports.AddIdentifiers(const AIdentifiers: TArray<string>);
var

  LIdent: string;
  LParts: TArray<string>;
  LMethod, LTarget: string;
  LList: TList<string>;
begin

  for LIdent in AIdentifiers do
  begin
    if not LIdent.StartsWith('!HELPER:') then
    begin
      ExportedIdentifiers.Add(LIdent.ToLower);
      Continue;
    end;
    LParts := LIdent.Split([':']);
    if Length(LParts) < 3 then
      Continue;
    LMethod := LParts[1].ToLower;
    LTarget := LParts[2].ToLower;
    if not ExportedHelpers.TryGetValue(LMethod, LList) then
    begin
      LList := TList<string>.Create;
      ExportedHelpers.Add(LMethod, LList);
    end;
    if not LList.Contains(LTarget) then
      LList.Add(LTarget);
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
