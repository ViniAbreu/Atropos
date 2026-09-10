unit Atropos.Adapters.ContextSyntaxBuilder;

interface

uses DelphiAST, SimpleParser.Lexer, System.Generics.Collections;

type
  TContextSyntaxBuilder = class(TPasSyntaxTreeBuilder)
  private
    FReasons: TList<string>;
    procedure PreserveDirective(const ADirective: string);
  protected
    procedure HandlePtIfOptDirect(Sender: TmwBasePasLex); override;
    procedure HandlePtIfDirect(Sender: TmwBasePasLex); override;
    procedure HandlePtElseIfDirect(Sender: TmwBasePasLex); override;
  public
    constructor Create; override;
    destructor Destroy; override;
    function IncompleteReasons: TArray<string>;
  end;

implementation

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