unit Atropos.Adapters.SyntaxBuilder;

interface

uses DelphiAST, DelphiAST.Consts, SimpleParser.Lexer.Types;

type
  TAtroposSyntaxBuilder = class(TPasSyntaxTreeBuilder)
  private
    procedure RestoreSectionSource(AType: TSyntaxNodeType; const APath: string);
    procedure RestoreDeclarationSource(AType: TSyntaxNodeType; const APath: string);
  protected
    function GetTokenID: TptTokenKind; override;
    procedure Expected(Sym: TptTokenKind); override;
    procedure InitializationSection; override;
    procedure FinalizationSection; override;
    procedure CompoundStatement; override;
    procedure ClassMethodHeading; override;
    procedure ExportedHeading; override;
    procedure ProcedureDeclarationSection; override;
    procedure TypeDeclaration; override;
    procedure TypeSimple; override;
    procedure AttributeName; override;
  end;

implementation

uses DelphiAST.Classes, Atropos.Core.TypeNames;

function TAtroposSyntaxBuilder.GetTokenID: TptTokenKind;
begin
  Result := inherited;
  if Result = ptUnsafe then Result := ptIdentifier;
end;

procedure TAtroposSyntaxBuilder.Expected(Sym: TptTokenKind);
var LKind: TptTokenKind;
begin
  LKind := inherited GetTokenID;
  if (Sym = ptIdentifier) and (LKind = ptUnsafe) then
  begin
    NextToken;
    Exit;
  end;
  inherited;
end;

procedure TAtroposSyntaxBuilder.TypeSimple;
var LParent, LType, LArguments: TSyntaxNode; LChildren: TArray<TSyntaxNode>;
begin
  inherited;
  LParent := FStack.Peek;
  LChildren := LParent.ChildNodes;
  if Length(LChildren) = 0 then
    Exit;
  LType := LChildren[High(LChildren)];
  LArguments := LType.FindNode(ntTypeArgs);
  if not Assigned(LArguments) then
    Exit;
  LType.SetAttribute(anName, LType.GetAttribute(anName) +
    TTypeName.Parameters(Length(LArguments.ChildNodes)));
  // The upstream TypeId flattening only copies arguments from the first segment.
  if LType <> LParent.FindNode(ntType) then
    LParent.AddChild(LArguments.Clone);
end;

procedure TAtroposSyntaxBuilder.AttributeName;
var LName: string; LNode: TValuedSyntaxNode;
begin
  if TokenID <> ptIdentifier then
  begin
    inherited;
    Exit;
  end;
  LNode := TValuedSyntaxNode(FStack.AddValuedChild(ntName, Lexer.Token));
  LName := Lexer.Token;
  Expected(ptIdentifier);
  while TokenID = ptPoint do
  begin
    NextToken;
    LName := LName + '.' + Lexer.Token;
    Expected(ptIdentifier);
  end;
  LNode.Value := LName;
end;

procedure TAtroposSyntaxBuilder.RestoreDeclarationSource(AType: TSyntaxNodeType;
  const APath: string);
var LChildren: TArray<TSyntaxNode>; I: Integer;
begin
  LChildren := FStack.Peek.ChildNodes;
  for I := High(LChildren) downto 0 do
    if LChildren[I].Typ = AType then
    begin
      LChildren[I].FileName := APath;
      Exit;
    end;
end;

procedure TAtroposSyntaxBuilder.ClassMethodHeading;
var LPath: string;
begin
  LPath := Lexer.FileName;
  inherited;
  RestoreDeclarationSource(ntMethod, LPath);
end;

procedure TAtroposSyntaxBuilder.ExportedHeading;
var LPath: string;
begin
  LPath := Lexer.FileName;
  inherited;
  RestoreDeclarationSource(ntMethod, LPath);
end;

procedure TAtroposSyntaxBuilder.ProcedureDeclarationSection;
var LPath: string;
begin
  LPath := Lexer.FileName;
  inherited;
  RestoreDeclarationSource(ntMethod, LPath);
end;

procedure TAtroposSyntaxBuilder.TypeDeclaration;
var LPath: string;
begin
  LPath := Lexer.FileName;
  inherited;
  RestoreDeclarationSource(ntTypeDecl, LPath);
end;

procedure TAtroposSyntaxBuilder.RestoreSectionSource(AType: TSyntaxNodeType;
  const APath: string);
var LNode: TSyntaxNode;
begin
  LNode := FStack.Peek.FindNode(AType);
  if Assigned(LNode) then
    LNode.FileName := APath;
end;

procedure TAtroposSyntaxBuilder.InitializationSection;
var LPath: string;
begin
  LPath := Lexer.FileName;
  inherited;
  RestoreSectionSource(ntInitialization, LPath);
end;

procedure TAtroposSyntaxBuilder.FinalizationSection;
var LPath: string;
begin
  LPath := Lexer.FileName;
  inherited;
  RestoreSectionSource(ntFinalization, LPath);
end;

procedure TAtroposSyntaxBuilder.CompoundStatement;
var LPath: string; LUnitBody: Boolean;
begin
  LUnitBody := Assigned(FStack.Peek.FindNode(ntInterface));
  LPath := Lexer.FileName;
  inherited;
  if LUnitBody then
    RestoreSectionSource(ntStatements, LPath);
end;

end.
