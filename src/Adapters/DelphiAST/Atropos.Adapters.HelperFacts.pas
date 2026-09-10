unit Atropos.Adapters.HelperFacts;

interface

uses Atropos.Core.Ports, DelphiAST.Classes, System.Generics.Collections;

type
  THelperFactExtractor = class
  private
    FItems: TList<THelperDeclaration>;
    FSource: string;
    procedure Visit(ANode: TSyntaxNode);
    procedure CollectMembers(ANode: TSyntaxNode; const AHelper, AReceiver, AVisibility: string);
    procedure AddMember(ANode: TSyntaxNode; const AHelper, AReceiver, AVisibility: string);
  public
    constructor Create(const ASource: string);
    destructor Destroy; override;
    function Extract(ARoot: TSyntaxNode): TArray<THelperDeclaration>;
  end;

implementation

uses DelphiAST.Consts, System.SysUtils;

constructor THelperFactExtractor.Create(const ASource: string);
begin
  inherited Create;
  FItems := TList<THelperDeclaration>.Create;
  FSource := ASource;
end;

destructor THelperFactExtractor.Destroy;
begin
  FItems.Free;
  inherited;
end;

procedure THelperFactExtractor.AddMember(ANode: TSyntaxNode;
  const AHelper, AReceiver, AVisibility: string);
var LItem: THelperDeclaration;
begin
  LItem.HelperName := AHelper;
  LItem.ReceiverType := AReceiver;
  LItem.MemberName := ANode.GetAttribute(anName);
  LItem.Visibility := AVisibility;
  LItem.Kind := hmMethod;
  if ANode.Typ = ntProperty then
    LItem.Kind := hmProperty;
  LItem.SourcePath := ANode.FileName;
  if LItem.SourcePath.IsEmpty then
    LItem.SourcePath := FSource;
  LItem.NormalizedLine := ANode.Line;
  LItem.NormalizedColumn := ANode.Col;
  FItems.Add(LItem);
end;

procedure THelperFactExtractor.CollectMembers(ANode: TSyntaxNode;
  const AHelper, AReceiver, AVisibility: string);
var LChild: TSyntaxNode; LVisibility: string;
begin
  for LChild in ANode.ChildNodes do
  begin
    if LChild.Typ in [ntMethod, ntProperty] then
      AddMember(LChild, AHelper, AReceiver, AVisibility);
    if not (LChild.Typ in [ntPrivate, ntStrictPrivate, ntProtected, ntStrictProtected,
      ntPublic, ntPublished]) then
      Continue;
    LVisibility := 'public';
    if LChild.Typ in [ntPrivate, ntStrictPrivate] then
      LVisibility := 'private';
    if LChild.Typ in [ntProtected, ntStrictProtected] then
      LVisibility := 'protected';
    CollectMembers(LChild, AHelper, AReceiver, LVisibility);
  end;
end;

procedure THelperFactExtractor.Visit(ANode: TSyntaxNode);
var LType, LHelper, LTarget, LChild: TSyntaxNode;
begin
  if ANode.Typ = ntMethod then
    Exit;
  if ANode.Typ = ntTypeDecl then
  begin
    LType := ANode.FindNode(ntType);
    if not Assigned(LType) then
      Exit;
    LHelper := LType.FindNode(ntHelper);
    if not Assigned(LHelper) then
      Exit;
    LTarget := LHelper.FindNode(ntType);
    if Assigned(LTarget) then
      CollectMembers(LType, ANode.GetAttribute(anName), LTarget.GetAttribute(anName), 'public');
    Exit;
  end;
  for LChild in ANode.ChildNodes do
    Visit(LChild);
end;

function THelperFactExtractor.Extract(ARoot: TSyntaxNode): TArray<THelperDeclaration>;
var LInterface: TSyntaxNode;
begin
  FItems.Clear;
  LInterface := ARoot.FindNode(ntInterface);
  if Assigned(LInterface) then
    Visit(LInterface);
  Result := FItems.ToArray;
end;

end.
