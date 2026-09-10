unit Atropos.Core.LocalBinding;

interface

uses Atropos.Core.Ports, System.Generics.Collections;

type
  TLocalBindingState = (lbExternal, lbLocal, lbUnknown);
  TLocalSymbolBinding = class
  private
    FFacts: TUnitSymbolFacts;
    FDeclarations: TObjectDictionary<string, TList<Integer>>;
    FOverloads: TDictionary<string, Boolean>;
    procedure IndexDeclarations;
    class function ScopeKey(AScope: Integer; const AName: string): string; static;
    function HasOverloads(const AName: string): Boolean;
    function InScope(AScope: Integer; const AName: string;
      const AReference: TSymbolReference): TLocalBindingState;
    function Bind(const AReference: TSymbolReference): TLocalBindingState;
  public
    constructor Create(const AFacts: TUnitSymbolFacts);
    destructor Destroy; override;
    function Identifiers(AInterface: Boolean; AUncertainOnly: Boolean = False): TArray<string>;
  end;

implementation

uses System.SysUtils;

constructor TLocalSymbolBinding.Create(const AFacts: TUnitSymbolFacts);
begin
  inherited Create;
  FFacts := AFacts;
  FFacts.Declarations := Copy(AFacts.Declarations);
  FFacts.Scopes := Copy(AFacts.Scopes);
  FFacts.References := Copy(AFacts.References);
  FDeclarations := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  FOverloads := TDictionary<string, Boolean>.Create;
  IndexDeclarations;
end;

destructor TLocalSymbolBinding.Destroy;
begin
  FOverloads.Free;
  FDeclarations.Free;
  inherited;
end;

class function TLocalSymbolBinding.ScopeKey(AScope: Integer; const AName: string): string;
begin
  Result := IntToStr(AScope) + ':' + UpperCase(AName);
end;

procedure TLocalSymbolBinding.IndexDeclarations;
var I: Integer; LDeclaration: TSymbolDeclaration; LKey: string; LItems: TList<Integer>;
begin
  for I := 0 to High(FFacts.Declarations) do
  begin
    LDeclaration := FFacts.Declarations[I];
    LKey := ScopeKey(LDeclaration.ScopeId, LDeclaration.Name);
    if not FDeclarations.TryGetValue(LKey, LItems) then
    begin
      LItems := TList<Integer>.Create;
      FDeclarations.Add(LKey, LItems);
    end;
    LItems.Add(I);
    if (LDeclaration.Kind = skRoutine) and not LDeclaration.CanShadow then
      FOverloads.AddOrSetValue(UpperCase(LDeclaration.Name), True);
  end;
end;

function TLocalSymbolBinding.InScope(AScope: Integer; const AName: string;
  const AReference: TSymbolReference): TLocalBindingState;
var LDeclaration: TSymbolDeclaration; LItems: TList<Integer>; I: Integer;
begin
  Result := lbExternal;
  if not FDeclarations.TryGetValue(ScopeKey(AScope, AName), LItems) then Exit;
  for I in LItems do
  begin
    LDeclaration := FFacts.Declarations[I];
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
begin
  Result := FOverloads.ContainsKey(UpperCase(AName));
end;

function TLocalSymbolBinding.Bind(const AReference: TSymbolReference): TLocalBindingState;
var LScope, LDot, LGeneric, LSteps: Integer; LName: string;
begin
  if AReference.Uncertain or AReference.IsAttribute then
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
  LAttribute: string;
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
      if LReference.IsAttribute and not LReference.Name.ToLower.EndsWith('attribute') then
      begin
        LAttribute := LReference.Name + 'Attribute';
        if not LNames.Contains(LAttribute) then
          LNames.Add(LAttribute);
      end;
    end;
    Result := LNames.ToArray;
  finally
    LNames.Free;
  end;
end;

end.
