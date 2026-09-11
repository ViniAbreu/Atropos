unit Atropos.Adapters.ExportFacts;

interface

uses Atropos.Core.Ports, DelphiAST.Classes, System.Generics.Collections;

type
  TExportFactExtractor = class
  private
    FItems: TList<TExportedSymbol>;
    procedure Add(ANode: TSyntaxNode; const AName: string; AKind: TExportKind);
    procedure AddNames(ANode: TSyntaxNode; AKind: TExportKind);
    procedure Visit(ANode: TSyntaxNode);
    procedure EnumMembers(ANode: TSyntaxNode);
  public
    constructor Create;
    destructor Destroy; override;
    function Extract(ARoot: TSyntaxNode): TArray<TExportedSymbol>;
  end;

implementation

uses DelphiAST.Consts, System.SysUtils, Atropos.Core.TypeNames;

constructor TExportFactExtractor.Create;
begin
  inherited Create;
  FItems := TList<TExportedSymbol>.Create;
end;

destructor TExportFactExtractor.Destroy;
begin
  FItems.Free;
  inherited;
end;

procedure TExportFactExtractor.Add(ANode: TSyntaxNode; const AName: string; AKind: TExportKind);
var LItem: TExportedSymbol; LParameters: TSyntaxNode; LName: TTypeName; LGeneric: Integer;
begin
  if AName.IsEmpty then
    Exit;
  LItem := Default(TExportedSymbol);
  LItem.Name := AName;
  LName := TTypeName.Read(AName);
  LItem.GenericArity := LName.Arity;
  LGeneric := Pos('<', AName);
  if LGeneric > 0 then
    LItem.Name := Copy(AName, 1, LGeneric - 1);
  LItem.Kind := AKind;
  LParameters := ANode.FindNode(ntTypeParams);
  if Assigned(LParameters) then
    LItem.GenericArity := Length(LParameters.ChildNodes);
  FItems.Add(LItem);
end;

procedure TExportFactExtractor.AddNames(ANode: TSyntaxNode; AKind: TExportKind);
var LChild: TSyntaxNode;
begin
  Add(ANode, ANode.GetAttribute(anName), AKind);
  for LChild in ANode.ChildNodes do
    if (LChild.Typ = ntName) and (LChild is TValuedSyntaxNode) then
      Add(ANode, TValuedSyntaxNode(LChild).Value, AKind);
end;

procedure TExportFactExtractor.EnumMembers(ANode: TSyntaxNode);
var LChild, LType: TSyntaxNode;
begin
  LType := ANode.FindNode(ntType);
  if not Assigned(LType) or (LType.GetAttribute(anName) <> 'enum') then
    Exit;
  if (ANode.Typ = ntTypeDecl) and (LType.GetAttribute(anVisibility) = 'scoped') then
    Exit;
  for LChild in LType.ChildNodes do
    if LChild.Typ in [ntIdentifier, ntElement] then
      AddNames(LChild, ekValue);
end;

procedure TExportFactExtractor.Visit(ANode: TSyntaxNode);
var LChild: TSyntaxNode;
begin
  if ANode.Typ = ntUses then
    Exit;
  if ANode.Typ = ntTypeDecl then
  begin
    AddNames(ANode, ekType);
    EnumMembers(ANode);
    Exit;
  end;
  if ANode.Typ = ntMethod then
  begin
    AddNames(ANode, ekRoutine);
    Exit;
  end;
  if ANode.Typ in [ntVariable, ntConstant, ntResourceString] then
  begin
    AddNames(ANode, ekValue);
    EnumMembers(ANode);
    Exit;
  end;
  for LChild in ANode.ChildNodes do
    Visit(LChild);
end;

function TExportFactExtractor.Extract(ARoot: TSyntaxNode): TArray<TExportedSymbol>;
var LInterface: TSyntaxNode;
begin
  FItems.Clear;
  LInterface := ARoot.FindNode(ntInterface);
  if Assigned(LInterface) then
    Visit(LInterface);
  Result := FItems.ToArray;
end;

end.
