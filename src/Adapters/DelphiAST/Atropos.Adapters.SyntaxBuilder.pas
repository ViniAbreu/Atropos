unit Atropos.Adapters.SyntaxBuilder;

interface

uses DelphiAST, DelphiAST.Consts;

type
  TAtroposSyntaxBuilder = class(TPasSyntaxTreeBuilder)
  private
    procedure RestoreSectionSource(AType: TSyntaxNodeType; const APath: string);
    procedure RestoreDeclarationSource(AType: TSyntaxNodeType; const APath: string);
  protected
    procedure InitializationSection; override;
    procedure FinalizationSection; override;
    procedure CompoundStatement; override;
    procedure ClassMethodHeading; override;
    procedure ExportedHeading; override;
    procedure ProcedureDeclarationSection; override;
    procedure TypeDeclaration; override;
  end;

implementation

uses DelphiAST.Classes;

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
