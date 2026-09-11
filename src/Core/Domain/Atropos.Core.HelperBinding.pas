unit Atropos.Core.HelperBinding;

interface

uses Atropos.Core.Ports, Atropos.Core.UnitSymbols, System.Generics.Collections;

type
  THelperUse = (huUnused, huUsed, huUnknown);
  THelperBinding = class
  private
    class function Match(AExports: TUnitExports;
      const AReference: TMemberReference): THelperUse; static;
    class function Competitors(const AName: string; const AReference: TMemberReference;
      AExports: TObjectDictionary<string, TUnitExports>;
      const AVisibleUnits: TArray<string>): Boolean; static;
  public
    class function Assess(const AName: string;
      AExports: TObjectDictionary<string, TUnitExports>;
      const AVisibleUnits: TArray<string>; const AReferences: TArray<TMemberReference>;
      AKnown, AInterface: Boolean): THelperUse; static;
  end;

implementation

uses System.SysUtils;

class function THelperBinding.Match(AExports: TUnitExports;
  const AReference: TMemberReference): THelperUse;
var LTargets: TList<string>; LTarget: string;
begin
  Result := huUnused;
  if not AExports.ExportedHelpers.TryGetValue(LowerCase(AReference.MemberName), LTargets) then
    Exit;
  for LTarget in LTargets do
  begin
    if AReference.ReceiverIsClass and (LTarget = 'string') then
      Continue;
    if SameText(LTarget, AReference.ReceiverType) and not LTarget.IsEmpty then
      Exit(huUsed);
    Result := huUnknown;
  end;
end;

class function THelperBinding.Competitors(const AName: string;
  const AReference: TMemberReference; AExports: TObjectDictionary<string, TUnitExports>;
  const AVisibleUnits: TArray<string>): Boolean;
var LName: string; LExports: TUnitExports;
begin
  for LName in AVisibleUnits do
  begin
    if SameText(LName, AName) then
      Continue;
    if not AExports.TryGetValue(LowerCase(LName), LExports) then
      Exit(True);
    if Match(LExports, AReference) <> huUnused then
      Exit(True);
  end;
  Result := False;
end;

class function THelperBinding.Assess(const AName: string;
  AExports: TObjectDictionary<string, TUnitExports>; const AVisibleUnits: TArray<string>;
  const AReferences: TArray<TMemberReference>; AKnown, AInterface: Boolean): THelperUse;
var LExports: TUnitExports; LReference: TMemberReference; LMatch: THelperUse;
begin
  Result := huUnused;
  if not AExports.TryGetValue(LowerCase(AName), LExports) then
    Exit;
  if LExports.ExportedHelpers.Count = 0 then
    Exit;
  if not AKnown then
    Exit(huUnknown);
  for LReference in AReferences do
  begin
    if LReference.InInterface <> AInterface then
      Continue;
    LMatch := Match(LExports, LReference);
    if LMatch = huUnused then
      Continue;
    if (LMatch = huUnknown) or Competitors(AName, LReference, AExports, AVisibleUnits) then
      Exit(huUnknown);
    Result := huUsed;
  end;
end;

end.
