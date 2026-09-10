unit Atropos.Adapters.SymbolFacts;

interface

uses Atropos.Core.Ports, DelphiAST.Classes, System.Generics.Collections;

type
  TSymbolVisit = record
    ScopeId: Integer;
    InInterface, Uncertain: Boolean;
  end;
  TSymbolFactExtractor = class
  private
    FScopes: TList<TSymbolScope>;
    FDeclarations: TList<TSymbolDeclaration>;
    FReferences: TList<TSymbolReference>;
    FTypes: TDictionary<string, Integer>;
    FSource: string;
    FPosition: Integer;
    function AddScope(AParent: Integer; AOwner: Integer = -1): Integer;
    function AddDeclaration(ANode: TSyntaxNode; const AName: string;
      AScope: Integer; AKind: TLocalSymbolKind): Integer;
    procedure AddNamedDeclarations(ANode: TSyntaxNode; AScope: Integer;
      AKind: TLocalSymbolKind);
    procedure DelayDeclarations(AFirst: Integer);
    procedure AddReference(ANode: TSyntaxNode; const AName: string;
      const AVisit: TSymbolVisit; AArity: Integer = 0);
    function QualifiedName(ANode: TSyntaxNode): string;
    function MethodOwner(ANode: TSyntaxNode): Integer;
    function GenericArity(ANode: TSyntaxNode): Integer;
    procedure References(ANode: TSyntaxNode; const AVisit: TSymbolVisit);
    function EnterScope(ANode: TSyntaxNode; const AVisit: TSymbolVisit): TSymbolVisit;
    procedure Visit(ANode: TSyntaxNode; AVisit: TSymbolVisit);
  public
    constructor Create(const ASource: string);
    destructor Destroy; override;
    function Extract(ARoot: TSyntaxNode): TUnitSymbolFacts;
  end;

implementation

uses DelphiAST.Consts, System.SysUtils;

constructor TSymbolFactExtractor.Create(const ASource: string);
begin
  inherited Create;
  FSource := ASource;
  FScopes := TList<TSymbolScope>.Create;
  FDeclarations := TList<TSymbolDeclaration>.Create;
  FReferences := TList<TSymbolReference>.Create;
  FTypes := TDictionary<string, Integer>.Create;
end;

destructor TSymbolFactExtractor.Destroy;
begin
  FTypes.Free;
  FReferences.Free;
  FDeclarations.Free;
  FScopes.Free;
  inherited;
end;

function TSymbolFactExtractor.AddScope(AParent, AOwner: Integer): Integer;
var LScope: TSymbolScope;
begin
  LScope.ParentId := AParent;
  LScope.OwnerId := AOwner;
  Result := FScopes.Add(LScope);
end;

function TSymbolFactExtractor.GenericArity(ANode: TSyntaxNode): Integer;
var LParameters: TSyntaxNode;
begin
  LParameters := ANode.FindNode(ntTypeParams);
  if not Assigned(LParameters) then
    LParameters := ANode.FindNode(ntTypeArgs);
  Result := 0;
  if Assigned(LParameters) then
    Result := Length(LParameters.ChildNodes);
end;

function TSymbolFactExtractor.AddDeclaration(ANode: TSyntaxNode; const AName: string;
  AScope: Integer; AKind: TLocalSymbolKind): Integer;
var LItem: TSymbolDeclaration;
begin
  Result := -1;
  if AName.IsEmpty then
    Exit;
  LItem := Default(TSymbolDeclaration);
  LItem.Name := AName;
  LItem.ScopeId := AScope;
  LItem.Kind := AKind;
  LItem.AvailableFrom := FPosition;
  LItem.GenericArity := GenericArity(ANode);
  LItem.CanShadow := not ANode.HasAttribute(anOverload);
  LItem.SourcePath := ANode.FileName;
  if LItem.SourcePath.IsEmpty then
    LItem.SourcePath := FSource;
  LItem.NormalizedLine := ANode.Line;
  LItem.NormalizedColumn := ANode.Col;
  Result := FDeclarations.Add(LItem);
end;

procedure TSymbolFactExtractor.AddNamedDeclarations(ANode: TSyntaxNode;
  AScope: Integer; AKind: TLocalSymbolKind);
var LChild: TSyntaxNode;
begin
  if ANode.HasAttribute(anName) then
    AddDeclaration(ANode, ANode.GetAttribute(anName), AScope, AKind);
  for LChild in ANode.ChildNodes do
    if (LChild.Typ = ntName) and (LChild is TValuedSyntaxNode) then
      AddDeclaration(ANode, TValuedSyntaxNode(LChild).Value, AScope, AKind);
end;

procedure TSymbolFactExtractor.DelayDeclarations(AFirst: Integer);
var I: Integer; LItem: TSymbolDeclaration;
begin
  for I := AFirst to FDeclarations.Count - 1 do
  begin
    LItem := FDeclarations[I];
    LItem.AvailableFrom := FPosition + 1;
    FDeclarations[I] := LItem;
  end;
end;

procedure TSymbolFactExtractor.AddReference(ANode: TSyntaxNode; const AName: string;
  const AVisit: TSymbolVisit; AArity: Integer);
var LItem: TSymbolReference;
begin
  if AName.IsEmpty then
    Exit;
  LItem := Default(TSymbolReference);
  LItem.Name := AName;
  LItem.ScopeId := AVisit.ScopeId;
  LItem.Position := FPosition;
  LItem.GenericArity := AArity;
  LItem.InInterface := AVisit.InInterface;
  LItem.Uncertain := AVisit.Uncertain;
  LItem.SourcePath := ANode.FileName;
  if LItem.SourcePath.IsEmpty then
    LItem.SourcePath := FSource;
  LItem.NormalizedLine := ANode.Line;
  LItem.NormalizedColumn := ANode.Col;
  FReferences.Add(LItem);
end;

function TSymbolFactExtractor.QualifiedName(ANode: TSyntaxNode): string;
var LLeft, LRight: string;
begin
  Result := '';
  if ANode.Typ = ntIdentifier then
    Exit(ANode.GetAttribute(anName));
  if (ANode.Typ <> ntDot) or (Length(ANode.ChildNodes) <> 2) then
    Exit;
  LLeft := QualifiedName(ANode.ChildNodes[0]);
  LRight := QualifiedName(ANode.ChildNodes[1]);
  if not LLeft.IsEmpty and not LRight.IsEmpty then
    Result := LLeft + '.' + LRight;
end;

function TSymbolFactExtractor.MethodOwner(ANode: TSyntaxNode): Integer;
var LName: string; LDot: Integer;
begin
  Result := -1;
  LName := ANode.GetAttribute(anName);
  LDot := LastDelimiter('.', LName);
  if LDot = 0 then
    Exit;
  LName := LowerCase(Copy(LName, 1, LDot - 1));
  if not FTypes.TryGetValue(LName, Result) then
    Result := -1;
end;

procedure TSymbolFactExtractor.References(ANode: TSyntaxNode; const AVisit: TSymbolVisit);
var LName: string; LParent: TSyntaxNode; LArity: Integer;
begin
  LParent := ANode.ParentNode;
  if ANode.Typ = ntDot then
  begin
    if Assigned(LParent) and (LParent.Typ = ntDot) then
      Exit;
    LName := QualifiedName(ANode);
    AddReference(ANode, LName, AVisit);
    if not LName.IsEmpty then
      AddReference(ANode, Copy(LName, 1, Pos('.', LName) - 1), AVisit);
    Exit;
  end;
  if not (ANode.Typ in [ntIdentifier, ntType, ntAttribute]) then
    Exit;
  if Assigned(LParent) and (LParent.Typ = ntTypeParam) then
    Exit;
  if Assigned(LParent) and (LParent.Typ = ntDot) and
    (LParent.ChildNodes[0] <> ANode) then
    Exit;
  LName := ANode.GetAttribute(anName);
  LArity := 0;
  if Assigned(LParent) and (LParent.Typ = ntGeneric) and
    (LParent.ChildNodes[0] = ANode) then
  begin
    LArity := GenericArity(LParent);
    LName := LName + '<T>';
  end;
  AddReference(ANode, LName, AVisit, LArity);
end;

function TSymbolFactExtractor.EnterScope(ANode: TSyntaxNode;
  const AVisit: TSymbolVisit): TSymbolVisit;
var LName: string;
begin
  Result := AVisit;
  if ANode.Typ = ntInterface then
  begin
    Result.ScopeId := 0;
    Result.InInterface := True;
    Exit;
  end;
  if ANode.Typ in [ntImplementation, ntInitialization, ntFinalization] then
  begin
    Result.ScopeId := 1;
    Result.InInterface := False;
    Exit;
  end;
  if ANode.Typ = ntWith then
    Result.Uncertain := True;
  if ANode.Typ in [ntMethod, ntAnonymousMethod, ntTypeDecl, ntStatements,
    ntFor, ntRepeat, ntExceptionHandler, ntProperty, ntThen, ntElse, ntCaseElse] then
    Result.ScopeId := AddScope(AVisit.ScopeId, MethodOwner(ANode));
  if (ANode.Typ = ntType) and Assigned(ANode.FindNode(ntParameters)) then
    Result.ScopeId := AddScope(AVisit.ScopeId);
  if (ANode.Typ = ntTypeDecl) and (AVisit.ScopeId in [0, 1]) then
  begin
    LName := LowerCase(ANode.GetAttribute(anName));
    FTypes.AddOrSetValue(LName, Result.ScopeId);
  end;
end;

procedure TSymbolFactExtractor.Visit(ANode: TSyntaxNode; AVisit: TSymbolVisit);
var LChild, LType: TSyntaxNode; LFirst, LDeclaration: Integer; LDelay: Boolean;
begin
  if ANode.Typ = ntUses then
    Exit;
  Inc(FPosition);
  LFirst := FDeclarations.Count;
  LDelay := ANode.Typ in [ntVariable, ntParameter, ntField, ntConstant, ntResourceString];
  if ANode.Typ = ntVariable then
    AddNamedDeclarations(ANode, AVisit.ScopeId, skVariable);
  if ANode.Typ = ntParameter then
    AddNamedDeclarations(ANode, AVisit.ScopeId, skParameter);
  if ANode.Typ = ntField then
    AddNamedDeclarations(ANode, AVisit.ScopeId, skField);
  if ANode.Typ in [ntConstant, ntResourceString] then
    AddNamedDeclarations(ANode, AVisit.ScopeId, skConstant);
  if ANode.Typ = ntMethod then
    AddDeclaration(ANode, ANode.GetAttribute(anName), AVisit.ScopeId, skRoutine);
  LDeclaration := -1;
  if ANode.Typ = ntTypeDecl then
    LDeclaration := AddDeclaration(ANode, ANode.GetAttribute(anName), AVisit.ScopeId, skType);
  if ANode.Typ = ntTypeParam then
  begin
    LType := ANode.FindNode(ntType);
    if Assigned(LType) then
      AddDeclaration(LType, LType.GetAttribute(anName), AVisit.ScopeId, skTypeParameter);
  end;
  AVisit := EnterScope(ANode, AVisit);
  References(ANode, AVisit);
  for LChild in ANode.ChildNodes do
    Visit(LChild, AVisit);
  if LDelay or ((ANode.Typ = ntVariables) and Assigned(ANode.FindNode(ntAssign))) then
    DelayDeclarations(LFirst);
  if LDeclaration >= 0 then
  begin
    LType := ANode.FindNode(ntType);
    if Assigned(LType) and LType.GetAttribute(anType).IsEmpty then
      DelayDeclarations(LDeclaration);
  end;
end;

function TSymbolFactExtractor.Extract(ARoot: TSyntaxNode): TUnitSymbolFacts;
var LVisit: TSymbolVisit;
begin
  FScopes.Clear;
  FDeclarations.Clear;
  FReferences.Clear;
  FTypes.Clear;
  FPosition := 0;
  AddScope(-1);
  AddScope(0);
  LVisit := Default(TSymbolVisit);
  LVisit.ScopeId := 1;
  Visit(ARoot, LVisit);
  Result.Scopes := FScopes.ToArray;
  Result.Declarations := FDeclarations.ToArray;
  Result.References := FReferences.ToArray;
end;

end.
