unit Atropos.Core.LocalBinding;

interface

uses Atropos.Core.Ports;

type
  TLocalBindingState = (lbExternal, lbLocal, lbUnknown);
  TLocalSymbolBinding = class
  private
    FFacts: TUnitSymbolFacts;
    function HasOverloads(const AName: string): Boolean;
    function InScope(AScope: Integer; const AName: string;
      const AReference: TSymbolReference): TLocalBindingState;
    function Bind(const AReference: TSymbolReference): TLocalBindingState;
  public
    constructor Create(const AFacts: TUnitSymbolFacts);
    function Identifiers(AInterface: Boolean; AUncertainOnly: Boolean = False): TArray<string>;
  end;

implementation

uses System.SysUtils, System.Generics.Collections;

constructor TLocalSymbolBinding.Create(const AFacts: TUnitSymbolFacts);
begin
  inherited Create;
  FFacts := AFacts;
end;

function TLocalSymbolBinding.InScope(AScope: Integer; const AName: string;
  const AReference: TSymbolReference): TLocalBindingState;
var LDeclaration: TSymbolDeclaration;
begin
  Result := lbExternal;
  for LDeclaration in FFacts.Declarations do
  begin
    if (LDeclaration.ScopeId <> AScope) or
      (LDeclaration.AvailableFrom > AReference.Position) or
      not SameText(LDeclaration.Name, AName) then
      Continue;
    if LDeclaration.GenericArity <> AReference.GenericArity then
      Continue;
    if not LDeclaration.CanShadow or
      ((LDeclaration.Kind = skRoutine) and HasOverloads(AName)) then
      Exit(lbUnknown);
    Result := lbLocal;
  end;
end;

function TLocalSymbolBinding.HasOverloads(const AName: string): Boolean;
var LDeclaration: TSymbolDeclaration;
begin
  for LDeclaration in FFacts.Declarations do
    if (LDeclaration.Kind = skRoutine) and not LDeclaration.CanShadow and
      SameText(LDeclaration.Name, AName) then
      Exit(True);
  Result := False;
end;

function TLocalSymbolBinding.Bind(const AReference: TSymbolReference): TLocalBindingState;
var LScope, LDot, LGeneric, LSteps: Integer; LName: string;
begin
  if AReference.Uncertain then
    Exit(lbUnknown);
  LName := AReference.Name;
  LDot := Pos('.', LName);
  if LDot > 0 then
    LName := Copy(LName, 1, LDot - 1);
  LGeneric := Pos('<', LName);
  if LGeneric > 0 then
    LName := Copy(LName, 1, LGeneric - 1);
  LScope := AReference.ScopeId;
  LSteps := 0;
  while (LScope >= 0) and (LScope < Length(FFacts.Scopes)) do
  begin
    Inc(LSteps);
    if LSteps > Length(FFacts.Scopes) then
      Exit(lbUnknown);
    Result := InScope(LScope, LName, AReference);
    if Result <> lbExternal then
      Exit;
    if FFacts.Scopes[LScope].OwnerId >= 0 then
    begin
      Result := InScope(FFacts.Scopes[LScope].OwnerId, LName, AReference);
      if Result <> lbExternal then
        Exit;
    end;
    LScope := FFacts.Scopes[LScope].ParentId;
  end;
  Result := lbExternal;
end;

function TLocalSymbolBinding.Identifiers(AInterface, AUncertainOnly: Boolean): TArray<string>;
var LNames: TList<string>; LReference: TSymbolReference; LState: TLocalBindingState;
begin
  LNames := TList<string>.Create;
  try
    for LReference in FFacts.References do
    begin
      if LReference.InInterface <> AInterface then
        Continue;
      LState := Bind(LReference);
      if (LState = lbLocal) or (AUncertainOnly and (LState <> lbUnknown)) then
        Continue;
      if not LNames.Contains(LReference.Name) then
        LNames.Add(LReference.Name);
    end;
    Result := LNames.ToArray;
  finally
    LNames.Free;
  end;
end;

end.
