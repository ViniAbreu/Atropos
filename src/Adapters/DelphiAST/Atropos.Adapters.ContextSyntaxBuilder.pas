unit Atropos.Adapters.ContextSyntaxBuilder;

interface

uses Atropos.Adapters.SyntaxBuilder, SimpleParser.Lexer, System.Generics.Collections;

type
  TContextSyntaxBuilder = class(TAtroposSyntaxBuilder)
  private
    FReasons: TList<string>;
    procedure PreserveDirective(const ADirective: string);
  protected
    procedure HandlePtIfOptDirect(Sender: TmwBasePasLex); override;
    procedure HandlePtIfDirect(Sender: TmwBasePasLex); override;
    procedure HandlePtElseIfDirect(Sender: TmwBasePasLex); override;
    procedure MainUsedUnitExpression; override;
  public
    constructor Create; override;
    destructor Destroy; override;
    function IncompleteReasons: TArray<string>;
  end;

implementation

uses DelphiAST.Classes, DelphiAST.Consts;

procedure TContextSyntaxBuilder.MainUsedUnitExpression;
var LExpression: TSyntaxNode;
begin
  inherited;
  LExpression := FStack.Peek.FindNode(ntExpression);
  if not Assigned(LExpression) then
  begin
    PreserveDirective('Missing project source path');
    Exit;
  end;
  if Length(LExpression.ChildNodes) <> 1 then
  begin
    PreserveDirective('Compound project source path');
    Exit;
  end;
  if LExpression.ChildNodes[0].Typ <> ntLiteral then
    PreserveDirective('Nonliteral project source path');
end;
constructor TContextSyntaxBuilder.Create;
begin
  inherited;
  FReasons := TList<string>.Create;
end;

destructor TContextSyntaxBuilder.Destroy;
begin
  FReasons.Free;
  inherited;
end;

procedure TContextSyntaxBuilder.PreserveDirective(const ADirective: string);
var LReason: string;
begin
  LReason := ADirective + ' requires project-aware expression/switch evaluation.';
  if not FReasons.Contains(LReason) then
    FReasons.Add(LReason);
end;

procedure TContextSyntaxBuilder.HandlePtIfOptDirect(Sender: TmwBasePasLex);
begin
  PreserveDirective('IFOPT');
  inherited;
end;

procedure TContextSyntaxBuilder.HandlePtIfDirect(Sender: TmwBasePasLex);
begin
  PreserveDirective('IF');
  inherited;
end;

procedure TContextSyntaxBuilder.HandlePtElseIfDirect(Sender: TmwBasePasLex);
begin
  PreserveDirective('ELSEIF');
  inherited;
end;

function TContextSyntaxBuilder.IncompleteReasons: TArray<string>;
begin
  Result := FReasons.ToArray;
end;

end.
