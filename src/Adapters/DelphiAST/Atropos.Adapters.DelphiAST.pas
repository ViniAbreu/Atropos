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
  end;

  TDelphiASTAdapter = class(TInterfacedObject, IASTParser)
  public
    function ParseFile(const AFilePath: string): IUnitSyntaxTree;
  end;

implementation

uses
  DelphiAST,
  System.JSON,
  System.Net.HttpClient,
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  System.StrUtils;

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
begin
  if not Assigned(ANode) then
    Exit;

  if ANode.Typ = ntUses then
    Exit;
  
  if ANode.HasAttribute(anName) and (ANode.Typ in [ntType, ntIdentifier, ntAttribute]) then
  begin
    AList.Add(ANode.GetAttribute(anName));
    if Assigned(ANode.ParentNode) and (ANode.ParentNode.Typ = ntGeneric) and
       (Length(ANode.ParentNode.ChildNodes) > 0) and (ANode.ParentNode.ChildNodes[0] = ANode) then
      AList[AList.Count - 1] := AList[AList.Count - 1] + '<T>';
  end;
  
  for LChild in ANode.ChildNodes do
    FindAllIdentifiers(LChild, AList);
end;

procedure TDelphiASTSyntaxTree.FindExportedIdentifiers(ANode: TSyntaxNode; AList: TList<string>; AInsideTypeDecl: Boolean = False; AInsideHelper: Boolean = False);
var
  LChild: TSyntaxNode;
  LIsTypeDecl: Boolean;
  LIsHelper: Boolean;
begin
  if not Assigned(ANode) then
    Exit;
  
  if ANode.Typ = ntUses then
    Exit;
  
  if ANode.HasAttribute(anName) and not (ANode.Typ in [ntUnit, ntUses, ntIdentifier, ntType]) then
  begin
    if not (AInsideTypeDecl and not AInsideHelper and (ANode.Typ <> ntElement)) then
      AList.Add(ANode.GetAttribute(anName));
  end;
    
  LIsTypeDecl := AInsideTypeDecl or (ANode.Typ = ntTypeDecl);
  LIsHelper := AInsideHelper or (ANode.Typ = ntHelper);
  
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

end.

