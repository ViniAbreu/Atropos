unit Atropos.Adapters.TracedIncludes;

interface

uses SimpleParser.Lexer.Types, Atropos.Adapters.CompilerBranchTrace;

type
  TTracedIncludes = class(TInterfacedObject, IIncludeHandler)
  private
    FRootPath: string;
    FIncludes: TArray<TCompilerTraceInclude>;
    FPosition: Integer;
  public
    constructor Create(const ARootPath: string; const AIncludes: TArray<TCompilerTraceInclude>);
    function GetIncludeFileContent(const ParentFileName, IncludeName: string;
      out Content, FileName: string): Boolean;
    procedure ValidateConsumed;
  end;

implementation

uses System.SysUtils;

constructor TTracedIncludes.Create(const ARootPath: string; const AIncludes: TArray<TCompilerTraceInclude>);
begin
  inherited Create;
  FRootPath := ARootPath;
  FIncludes := Copy(AIncludes);
end;

function TTracedIncludes.GetIncludeFileContent(const ParentFileName, IncludeName: string;
  out Content, FileName: string): Boolean;
var LParent: string; LInclude: TCompilerTraceInclude;
begin
  if FPosition >= Length(FIncludes) then
    raise EIncludeError.Create('Parser requested an include absent from the compiler trace.');
  LParent := ParentFileName;
  if LParent.IsEmpty then LParent := FRootPath;
  LInclude := FIncludes[FPosition];
  if not SameText(LParent, LInclude.ParentPath) or not SameText(IncludeName, LInclude.Name) then
    raise EIncludeError.Create('Parser include order differs from the compiler trace.');
  Inc(FPosition);
  Content := LInclude.Content;
  FileName := LInclude.SourcePath;
  Result := True;
end;

procedure TTracedIncludes.ValidateConsumed;
begin
  if FPosition <> Length(FIncludes) then
    raise EIncludeError.Create('Parser did not consume every active compiler include.');
end;

end.
