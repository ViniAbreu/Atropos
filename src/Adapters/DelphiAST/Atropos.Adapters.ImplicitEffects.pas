unit Atropos.Adapters.ImplicitEffects;

interface

uses Atropos.Core.Ports, DelphiAST.Classes, System.Generics.Collections;

type
  TStorageEffect = (seNone, seDefinite, seUnknown);
  TImplicitEffectExtractor = class
  private
    FTypes: TDictionary<string, TSyntaxNode>;
    FResolving: TList<string>;
    FItems: TList<TImplicitEffect>;
    FSource: string;
    FHasImports: Boolean;
    procedure CollectTypes(ANode: TSyntaxNode);
    procedure Visit(ANode: TSyntaxNode; AInsideType: Boolean);
    procedure AddEffect(ANode: TSyntaxNode; AKind: TImplicitEffectKind;
      const AName, AReason: string; ADefinite: Boolean);
    function TypeEffect(ANode: TSyntaxNode): TStorageEffect;
    function NamedTypeEffect(const AName: string): TStorageEffect;
    function RecordEffect(ANode: TSyntaxNode): TStorageEffect;
    procedure InspectVariable(ANode: TSyntaxNode);
  public
    constructor Create(const ASource: string);
    destructor Destroy; override;
    function Extract(ARoot: TSyntaxNode): TArray<TImplicitEffect>;
  end;

implementation

uses DelphiAST.Consts, System.SysUtils;

constructor TImplicitEffectExtractor.Create(const ASource: string);
begin
  inherited Create;
  FSource := ASource;
  FTypes := TDictionary<string, TSyntaxNode>.Create;
  FResolving := TList<string>.Create;
  FItems := TList<TImplicitEffect>.Create;
end;

destructor TImplicitEffectExtractor.Destroy;
begin
  FItems.Free;
  FResolving.Free;
  FTypes.Free;
  inherited;
end;

procedure TImplicitEffectExtractor.CollectTypes(ANode: TSyntaxNode);
var LChild: TSyntaxNode; LName: string;
begin
  if ANode.Typ = ntMethod then
    Exit;
  if ANode.Typ = ntUses then
    FHasImports := True;
  if ANode.Typ = ntTypeDecl then
  begin
    LName := LowerCase(ANode.GetAttribute(anName));
    if FTypes.ContainsKey(LName) then
    begin
      FTypes[LName] := nil;
      Exit;
    end;
    FTypes.Add(LName, ANode.FindNode(ntType));
    Exit;
  end;
  for LChild in ANode.ChildNodes do
    CollectTypes(LChild);
end;

function TImplicitEffectExtractor.NamedTypeEffect(const AName: string): TStorageEffect;
const Scalars = '|byte|shortint|smallint|word|integer|longint|cardinal|longword|' +
  'int64|uint64|nativeint|nativeuint|boolean|bytebool|wordbool|longbool|char|' +
  'ansichar|widechar|single|double|extended|currency|comp|pointer|shortstring|';
var LName: string; LType: TSyntaxNode; LSystem: Boolean;
begin
  LName := LowerCase(AName);
  if FTypes.TryGetValue(LName, LType) then
  begin
    if not Assigned(LType) or FResolving.Contains(LName) then
      Exit(seUnknown);
    FResolving.Add(LName);
    try
      Exit(TypeEffect(LType));
    finally
      FResolving.Remove(LName);
    end;
  end;
  LSystem := LName.StartsWith('system.');
  if LSystem then
    LName := Copy(LName, 8, MaxInt);
  if not FHasImports or LSystem then
    if Scalars.Contains('|' + LName + '|') and not LName.IsEmpty then
      Exit(seNone);
  Result := seUnknown;
end;

function TImplicitEffectExtractor.RecordEffect(ANode: TSyntaxNode): TStorageEffect;
var LChild: TSyntaxNode; LEffect: TStorageEffect; LName: string;
begin
  Result := seNone;
  if ANode.GetAttribute(anClass) = 'true' then
    Result := seUnknown;
  for LChild in ANode.ChildNodes do
  begin
    LName := LowerCase(LChild.GetAttribute(anName));
    if (LChild.Typ = ntMethod) and (LChild.GetAttribute(anClass) = 'true') and
      not LChild.HasAttribute(anKind) and ((LName = 'initialize') or (LName = 'finalize')) then
      Exit(seDefinite);
    LEffect := seNone;
    if (LChild.Typ = ntField) and (LChild.GetAttribute(anClass) <> 'true') and
      (ANode.GetAttribute(anClass) <> 'true') then
      LEffect := TypeEffect(LChild.FindNode(ntType));
    if not (LChild.Typ in [ntMethod, ntField, ntTypeDecl]) then
      LEffect := RecordEffect(LChild);
    if LEffect = seDefinite then
      Exit(seDefinite);
    if LEffect = seUnknown then
      Result := seUnknown;
  end;
end;

function TImplicitEffectExtractor.TypeEffect(ANode: TSyntaxNode): TStorageEffect;
var LKind, LName: string;
begin
  if not Assigned(ANode) then
    Exit(seUnknown);
  LKind := LowerCase(ANode.GetAttribute(anType));
  LName := LowerCase(ANode.GetAttribute(anName));
  if (LKind = 'pointer') or (LKind = 'class') or (LKind = 'classof') or
    (LName = 'enum') or (LName = 'subrange') or (LKind = 'set') then
    Exit(seNone);
  if LKind = 'record' then
    Exit(RecordEffect(ANode));
  Result := NamedTypeEffect(LName);
end;

procedure TImplicitEffectExtractor.AddEffect(ANode: TSyntaxNode; AKind: TImplicitEffectKind;
  const AName, AReason: string; ADefinite: Boolean);
var LItem: TImplicitEffect;
begin
  LItem := Default(TImplicitEffect);
  LItem.Kind := AKind;
  LItem.Name := AName;
  LItem.Reason := AReason;
  LItem.Definite := ADefinite;
  LItem.SourcePath := ANode.FileName;
  if LItem.SourcePath.IsEmpty then
    LItem.SourcePath := FSource;
  LItem.NormalizedLine := ANode.Line;
  LItem.NormalizedColumn := ANode.Col;
  FItems.Add(LItem);
end;

procedure TImplicitEffectExtractor.InspectVariable(ANode: TSyntaxNode);
var LType, LNameNode: TSyntaxNode; LName: string; LEffect: TStorageEffect;
begin
  LType := ANode.FindNode(ntType);
  LEffect := TypeEffect(LType);
  if LEffect = seNone then
    Exit;
  LName := '';
  LNameNode := ANode.FindNode(ntName);
  if LNameNode is TValuedSyntaxNode then
    LName := TValuedSyntaxNode(LNameNode).Value;
  if LEffect = seDefinite then
  begin
    AddEffect(ANode, ieRecordStorage, LName, 'Managed record storage executes lifecycle operators: ' + LName, True);
    Exit;
  end;
  AddEffect(ANode, ieUnresolvedStorage, LName, 'Global storage lifecycle is unresolved: ' + LName, False);
end;

procedure TImplicitEffectExtractor.Visit(ANode: TSyntaxNode; AInsideType: Boolean);
var LChild: TSyntaxNode;
begin
  if ANode.Typ = ntMethod then
  begin
    if AInsideType and (ANode.GetAttribute(anClass) = 'true') and
      (ANode.GetAttribute(anKind) = 'constructor') then
      AddEffect(ANode, ieClassConstructor, ANode.GetAttribute(anName),
        'Class constructor activation requires compiler reachability analysis.', False);
    for LChild in ANode.ChildNodes do
      if LChild.Typ = ntTypeSection then
        Visit(LChild, False);
    Exit;
  end;
  if ANode.Typ = ntTypeDecl then
    AInsideType := True;
  if (ANode.Typ = ntType) and (ANode.GetAttribute(anClass) = 'true') then
    AddEffect(ANode, ieUnresolvedStorage, ANode.GetAttribute(anName),
      'Class storage lifecycle is unresolved.', False);
  if (ANode.Typ = ntVariable) and not AInsideType then
    InspectVariable(ANode);
  if (ANode.Typ = ntConstant) and Assigned(ANode.FindNode(ntType)) then
    if TypeEffect(ANode.FindNode(ntType)) <> seNone then
      AddEffect(ANode, ieUnresolvedStorage, ANode.GetAttribute(anName),
        'Typed constant lifecycle is unresolved.', False);
  if (ANode.Typ = ntVariable) and AInsideType then
    AddEffect(ANode, ieUnresolvedStorage, ANode.GetAttribute(anName),
      'Type-owned storage lifecycle is unresolved.', False);
  if (ANode.Typ = ntField) and (ANode.GetAttribute(anClass) = 'true') then
    AddEffect(ANode, ieUnresolvedStorage, ANode.GetAttribute(anName),
      'Class storage lifecycle is unresolved.', False);
  for LChild in ANode.ChildNodes do
    Visit(LChild, AInsideType);
end;

function TImplicitEffectExtractor.Extract(ARoot: TSyntaxNode): TArray<TImplicitEffect>;
begin
  FTypes.Clear;
  FItems.Clear;
  FResolving.Clear;
  FHasImports := False;
  CollectTypes(ARoot);
  Visit(ARoot, False);
  Result := FItems.ToArray;
end;

end.
