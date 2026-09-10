unit Atropos.Adapters.MemberReferences;

interface

uses Atropos.Core.Ports, DelphiAST.Classes, System.Generics.Collections;

type
  TMemberReferenceExtractor = class
  private
    FItems: TList<TMemberReference>;
    FRoot: TSyntaxNode;
    procedure Visit(ANode: TSyntaxNode; AInterface: Boolean);
    procedure AddReference(ANode: TSyntaxNode; AInterface: Boolean);
    procedure FindBindings(ANode: TSyntaxNode; const AName: string;
      var ACount: Integer; var AType: string);
    function ReceiverType(ANode: TSyntaxNode; const AName: string): string;
    function FindType(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
    function HasUnresolvedType(ANode: TSyntaxNode; const AName: string): Boolean;
    function IsClassType(ANode: TSyntaxNode; const AName: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function Extract(ARoot: TSyntaxNode): TArray<TMemberReference>;
  end;

implementation

uses DelphiAST.Consts, System.SysUtils;

constructor TMemberReferenceExtractor.Create;
begin
  inherited;
  FItems := TList<TMemberReference>.Create;
end;

destructor TMemberReferenceExtractor.Destroy;
begin
  FItems.Free;
  inherited;
end;

procedure TMemberReferenceExtractor.FindBindings(ANode: TSyntaxNode;
  const AName: string; var ACount: Integer; var AType: string);
var LChild, LType: TSyntaxNode;
begin
  if ANode.Typ in [ntMethod, ntTypeDecl] then
    Exit;
  if ANode.Typ in [ntParameter, ntVariable] then
  begin
    LType := ANode.FindNode(ntType);
    for LChild in ANode.ChildNodes do
      if (LChild is TValuedSyntaxNode) and (LChild.Typ = ntName) and
        SameText(TValuedSyntaxNode(LChild).Value, AName) then
      begin
        Inc(ACount);
        if Assigned(LType) then
          AType := LType.GetAttribute(anName);
      end;
  end;
  for LChild in ANode.ChildNodes do
    FindBindings(LChild, AName, ACount, AType);
end;

function TMemberReferenceExtractor.ReceiverType(ANode: TSyntaxNode;
  const AName: string): string;
var LScope, LChild: TSyntaxNode; LCount: Integer;
begin
  Result := '';
  if SameText(AName, 'Self') or SameText(AName, 'Result') then
    Exit;
  LScope := ANode.ParentNode;
  while Assigned(LScope) do
  begin
    if LScope.Typ = ntWith then
      Exit('');
    if LScope.Typ in [ntMethod, ntUnit] then
    begin
      LCount := 0;
      for LChild in LScope.ChildNodes do
        FindBindings(LChild, AName, LCount, Result);
      if LCount = 1 then
      begin
        if HasUnresolvedType(ANode, Result) then
          Exit('');
        Exit;
      end;
      if LCount > 1 then
        Exit('');
      if (LScope.Typ = ntMethod) and LScope.GetAttribute(anName).Contains('.') then
        Exit('');
    end;
    LScope := LScope.ParentNode;
  end;
end;

function TMemberReferenceExtractor.FindType(ANode: TSyntaxNode;
  const AName: string): TSyntaxNode;
var LChild: TSyntaxNode;
begin
  Result := nil;
  if ANode.Typ = ntMethod then
    Exit;
  if ANode.Typ = ntTypeDecl then
  begin
    if SameText(ANode.GetAttribute(anName), AName) then
      Result := ANode.FindNode(ntType);
    Exit;
  end;
  for LChild in ANode.ChildNodes do
  begin
    Result := FindType(LChild, AName);
    if Assigned(Result) then
      Exit;
  end;
end;

function TMemberReferenceExtractor.HasUnresolvedType(ANode: TSyntaxNode;
  const AName: string): Boolean;
var LScope, LChild, LType: TSyntaxNode;
begin
  LScope := ANode.ParentNode;
  while Assigned(LScope) do
  begin
    if LScope.Typ in [ntMethod, ntUnit] then
      for LChild in LScope.ChildNodes do
      begin
        LType := FindType(LChild, AName);
        if Assigned(LType) then
          Exit(not SameText(LType.GetAttribute(anType), 'class'));
      end;
    LScope := LScope.ParentNode;
  end;
  Result := False;
end;

function TMemberReferenceExtractor.IsClassType(ANode: TSyntaxNode;
  const AName: string): Boolean;
var LChild, LType: TSyntaxNode;
begin
  Result := False;
  if ANode.Typ = ntMethod then
    Exit;
  if ANode.Typ = ntTypeDecl then
  begin
    if not SameText(ANode.GetAttribute(anName), AName) then
      Exit;
    LType := ANode.FindNode(ntType);
    Exit(Assigned(LType) and SameText(LType.GetAttribute(anType), 'class'));
  end;
  for LChild in ANode.ChildNodes do
    if IsClassType(LChild, AName) then
      Exit(True);
end;

procedure TMemberReferenceExtractor.AddReference(ANode: TSyntaxNode; AInterface: Boolean);
var LItem: TMemberReference; LLeft, LRight: TSyntaxNode;
begin
  LItem := Default(TMemberReference);
  LItem.InInterface := AInterface;
  LItem.MemberName := ANode.GetAttribute(anName);
  if ANode.Typ = ntDot then
  begin
    if Length(ANode.ChildNodes) <> 2 then
      Exit;
    LLeft := ANode.ChildNodes[0];
    LRight := ANode.ChildNodes[1];
    if LRight.Typ <> ntIdentifier then
      Exit;
    LItem.MemberName := LRight.GetAttribute(anName);
    if LLeft.Typ = ntIdentifier then
      LItem.ReceiverType := ReceiverType(ANode, LLeft.GetAttribute(anName));
  end;
  LItem.ReceiverIsClass := not LItem.ReceiverType.IsEmpty and
    IsClassType(FRoot, LItem.ReceiverType);
  FItems.Add(LItem);
end;

procedure TMemberReferenceExtractor.Visit(ANode: TSyntaxNode; AInterface: Boolean);
var LChild: TSyntaxNode;
begin
  if ANode.Typ = ntUses then
    Exit;
  if ANode.Typ = ntInterface then
    AInterface := True;
  if ANode.Typ = ntDot then
    AddReference(ANode, AInterface);
  if (ANode.Typ = ntIdentifier) and
    (not Assigned(ANode.ParentNode) or (ANode.ParentNode.Typ <> ntDot)) then
    AddReference(ANode, AInterface);
  for LChild in ANode.ChildNodes do
    Visit(LChild, AInterface);
end;

function TMemberReferenceExtractor.Extract(ARoot: TSyntaxNode): TArray<TMemberReference>;
begin
  FItems.Clear;
  FRoot := ARoot;
  Visit(ARoot, False);
  Result := FItems.ToArray;
end;

end.
