unit Atropos.Adapters.DelphiAST;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atropos.Core.Ports,
  DelphiAST.Classes,
  DelphiAST.Consts;

type
  EASTParserException = class(Exception);

  TDelphiASTSyntaxTree = class(TInterfacedObject, IUnitSyntaxTree)
  private
    FFileName: string;
    FUnitName: string;
    FRoot: TSyntaxNode;
    
    function GetUsesList(ANodeType: TSyntaxNodeType): TArray<string>;
    function GetIdentifiersList(ANodeType: TSyntaxNodeType): TArray<string>;
    
    procedure FindAllUses(ANode: TSyntaxNode; AList: TList<string>);
    procedure FindAllIdentifiers(ANode: TSyntaxNode; AList: TList<string>);
    
    function ExtractNodeName(ANode: TSyntaxNode): string;
    function CanExportNode(ANode: TSyntaxNode; AInsideTypeDecl, AInsideHelper: Boolean): Boolean;
    function IsHelperNode(ANode: TSyntaxNode): Boolean;
    
    procedure FindExportedIdentifiers(ANode: TSyntaxNode; AList: TList<string>; AInsideTypeDecl: Boolean = False;
      AInsideHelper: Boolean = False);
  public
    constructor Create(const AFileName: string; ARoot: TSyntaxNode);
    destructor Destroy; override;
    
    function GetUnitName: string;
    function GetInterfaceUses: TArray<string>;
    function GetImplementationUses: TArray<string>;
    function GetIdentifiersUsedInInterface: TArray<string>;
    function GetIdentifiersUsedInImplementation: TArray<string>;
    function GetExportedIdentifiers: TArray<string>;
    function HasInitializationSection: Boolean;
  end;

  TDelphiASTAdapter = class(TInterfacedObject, IASTParser)
  public
    function ParseFile(const AFilePath: string): IUnitSyntaxTree;
  end;

implementation

uses
  DelphiAST,
  System.JSON,
  System.Classes;

function TDelphiASTAdapter.ParseFile(const AFilePath: string): IUnitSyntaxTree;
var
  LRoot: TSyntaxNode;
begin
  if not FileExists(AFilePath) then
    raise EASTParserException.CreateFmt('File not found: %s', [AFilePath]);

  try
    LRoot := TPasSyntaxTreeBuilder.Run(AFilePath);
    if LRoot = nil then
      raise EASTParserException.Create('Parser returned nil tree.');
      
    Result := TDelphiASTSyntaxTree.Create(AFilePath, LRoot);
  except
    on E: Exception do
      raise EASTParserException.CreateFmt('Error parsing file "%s": %s', [AFilePath, E.Message]);
  end;
end;

constructor TDelphiASTSyntaxTree.Create(const AFileName: string; ARoot: TSyntaxNode);
begin
  FFileName := AFileName;
  FRoot := ARoot;
  FUnitName := ExtractFileName(AFileName);
  if Assigned(FRoot) and (FRoot.Typ = ntUnit) then
  begin
    if FRoot.HasAttribute(anName) then
      FUnitName := FRoot.GetAttribute(anName);
  end;
end;

destructor TDelphiASTSyntaxTree.Destroy;
begin
  FRoot.Free;
  inherited;
end;

function TDelphiASTSyntaxTree.GetUnitName: string;
begin
  Result := FUnitName;
end;

procedure TDelphiASTSyntaxTree.FindAllUses(ANode: TSyntaxNode; AList: TList<string>);
var
  LChild: TSyntaxNode;
  LUsesNode: TSyntaxNode;
  LUnitName: string;
begin
  if not Assigned(ANode) then Exit;
  
  LUsesNode := ANode.FindNode(ntUses);
  if Assigned(LUsesNode) then
  begin
    for LChild in LUsesNode.ChildNodes do
    begin
      if (LChild.Typ = ntUnit) and LChild.HasAttribute(anName) then
      begin
        LUnitName := LChild.GetAttribute(anName);
        if not LUnitName.ToLower.EndsWith('.dcu') then
          AList.Add(LUnitName);
      end;
    end;
  end;
end;

procedure TDelphiASTSyntaxTree.FindAllIdentifiers(ANode: TSyntaxNode; AList: TList<string>);
var
  LChild: TSyntaxNode;
  LName: string;
begin
  if not Assigned(ANode) then
    Exit;

  if ANode.Typ = ntUses then
    Exit;
    
  LName := ExtractNodeName(ANode);
  
  if not LName.IsEmpty and not (ANode.Typ in [ntUnit, ntUses, ntLiteral]) then
  begin
    AList.Add(LName);
    if Assigned(ANode.ParentNode) and (ANode.ParentNode.Typ = ntGeneric) and
       (Length(ANode.ParentNode.ChildNodes) > 0) and (ANode.ParentNode.ChildNodes[0] = ANode) then
      AList[AList.Count - 1] := AList[AList.Count - 1] + '<T>';
  end;
  
  for LChild in ANode.ChildNodes do
    FindAllIdentifiers(LChild, AList);
end;

function TDelphiASTSyntaxTree.ExtractNodeName(ANode: TSyntaxNode): string;
var
  LChild: TSyntaxNode;
begin
  if not Assigned(ANode) then
  begin
    Result := EmptyStr;
    Exit;
  end;

  Result := ANode.GetAttribute(anName);
  if not Result.IsEmpty then
    Exit;

  if ANode is TValuedSyntaxNode then
  begin
    Result := TValuedSyntaxNode(ANode).Value;
    if not Result.IsEmpty then
      Exit;
  end;

  LChild := ANode.FindNode(ntName);
  if Assigned(LChild) then
  begin
    Result := ExtractNodeName(LChild);
    if not Result.IsEmpty then
      Exit;
  end;

  LChild := ANode.FindNode(ntIdentifier);
  if Assigned(LChild) then
  begin
    Result := ExtractNodeName(LChild);
  end;
end;

function TDelphiASTSyntaxTree.CanExportNode(ANode: TSyntaxNode; AInsideTypeDecl, AInsideHelper: Boolean): Boolean;
begin
  Result := False;
  if ANode.Typ in [ntUnit, ntUses, ntType] then
    Exit;
    
  if AInsideTypeDecl and not AInsideHelper then
  begin
    if ANode.Typ = ntElement then
    begin
      Result := True;
      Exit;
    end;
    
    if (ANode.Typ = ntIdentifier) and Assigned(ANode.ParentNode) and 
       (ANode.ParentNode.Typ = ntType) and (ANode.ParentNode.GetAttribute(anName) = 'enum') then
    begin
      Result := True;
      Exit;
    end;
    
    Exit;
  end;
  
  if ANode.Typ = ntIdentifier then
    Exit;
    
  Result := True;
end;

function TDelphiASTSyntaxTree.IsHelperNode(ANode: TSyntaxNode): Boolean;
begin
  Result := Assigned(ANode.FindNode(ntHelper));
  if not Result and (ANode.Typ = ntTypeDecl) then
    Result := Assigned(ANode.FindNode([ntType, ntHelper]));
end;

procedure TDelphiASTSyntaxTree.FindExportedIdentifiers(ANode: TSyntaxNode; AList: TList<string>; AInsideTypeDecl: Boolean = False; AInsideHelper: Boolean = False);
var
  LChild: TSyntaxNode;
  LIsTypeDecl: Boolean;
  LIsHelper: Boolean;
  LName: string;
begin
  if not Assigned(ANode) then
    Exit;
  
  if ANode.Typ = ntUses then
    Exit;
    
  LName := ExtractNodeName(ANode);
  
  if not LName.IsEmpty and CanExportNode(ANode, AInsideTypeDecl, AInsideHelper) then
    AList.Add(LName);
    
  LIsTypeDecl := AInsideTypeDecl or (ANode.Typ = ntTypeDecl);
  LIsHelper := AInsideHelper or (ANode.Typ = ntHelper);
  
  if (ANode.Typ in [ntTypeDecl, ntType]) and not LIsHelper then
    LIsHelper := IsHelperNode(ANode);
  
  for LChild in ANode.ChildNodes do
    FindExportedIdentifiers(LChild, AList, LIsTypeDecl, LIsHelper);
end;

function TDelphiASTSyntaxTree.GetUsesList(ANodeType: TSyntaxNodeType): TArray<string>;
var
  LNode: TSyntaxNode;
  LList: TList<string>;
begin
  Result := [];
  if not Assigned(FRoot) then
    Exit;
  
  LNode := FRoot.FindNode(ANodeType);
  if Assigned(LNode) then
  begin
    LList := TList<string>.Create;
    try
      FindAllUses(LNode, LList);
      Result := LList.ToArray;
    finally
      LList.Free;
    end;
  end;
end;

function TDelphiASTSyntaxTree.GetIdentifiersList(ANodeType: TSyntaxNodeType): TArray<string>;
var
  LNode: TSyntaxNode;
  LList: TList<string>;
begin
  Result := [];
  if not Assigned(FRoot) then
    Exit;
  
  LNode := FRoot.FindNode(ANodeType);
  if Assigned(LNode) then
  begin
    LList := TList<string>.Create;
    try
      FindAllIdentifiers(LNode, LList);
      Result := LList.ToArray;
    finally
      LList.Free;
    end;
  end;
end;

function TDelphiASTSyntaxTree.GetInterfaceUses: TArray<string>;
begin
  Result := GetUsesList(ntInterface);
end;

function TDelphiASTSyntaxTree.GetImplementationUses: TArray<string>;
begin
  Result := GetUsesList(ntImplementation);
end;

function TDelphiASTSyntaxTree.GetIdentifiersUsedInInterface: TArray<string>;
begin
  Result := GetIdentifiersList(ntInterface);
end;

function TDelphiASTSyntaxTree.GetIdentifiersUsedInImplementation: TArray<string>;
begin
  Result := GetIdentifiersList(ntImplementation);
end;

function TDelphiASTSyntaxTree.GetExportedIdentifiers: TArray<string>;
var
  LNode: TSyntaxNode;
  LList: TList<string>;
begin
  Result := [];
  if not Assigned(FRoot) then
    Exit;
  
  LNode := FRoot.FindNode(ntInterface);
  if Assigned(LNode) then
  begin
    LList := TList<string>.Create;
    try
      FindExportedIdentifiers(LNode, LList);
      Result := LList.ToArray;
    finally
      LList.Free;
    end;
  end;
end;

function TDelphiASTSyntaxTree.HasInitializationSection: Boolean;
begin
  Result := False;
  if Assigned(FRoot) then
    Result := Assigned(FRoot.FindNode(ntInitialization));
end;

end.

