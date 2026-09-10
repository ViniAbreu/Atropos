unit Atropos.Adapters.ConditionalImports;

interface

uses SimpleParser.Lexer, System.Generics.Collections;

type
  TConditionalImportScanner = class
  private
    FLexer: TmwPasLex;
    FNames: TList<string>;
    FDepth: Integer;
    FInsideUses, FConditional: Boolean;
    FName: string;
    procedure Visit;
    procedure FinishName;
  public
    constructor Create;
    destructor Destroy; override;
    function Find(const ASource: string): TArray<string>;
  end;

implementation

uses System.SysUtils, System.Classes, SimpleParser.Lexer.Types;

constructor TConditionalImportScanner.Create;
begin
  inherited;
  FLexer := TmwPasLex.Create;
  FLexer.UseDefines := False;
  FNames := TList<string>.Create;
end;

destructor TConditionalImportScanner.Destroy;
begin
  FNames.Free;
  FLexer.Free;
  inherited;
end;

procedure TConditionalImportScanner.FinishName;
begin
  if FConditional and not FName.IsEmpty and not FNames.Contains(FName) then
    FNames.Add(FName);
  FName := '';
  FConditional := False;
end;

procedure TConditionalImportScanner.Visit;
begin
  if FLexer.TokenID in [ptIfDefDirect, ptIfNDefDirect, ptIfDirect, ptIfOptDirect] then
    Inc(FDepth);
  if (FLexer.TokenID in [ptEndIfDirect, ptIfEndDirect]) and (FDepth > 0) then
    Dec(FDepth);
  if FLexer.TokenID = ptUses then
  begin
    FInsideUses := True;
    Exit;
  end;
  if not FInsideUses then
    Exit;
  if FLexer.TokenID in [ptElseDirect, ptElseIfDirect] then
  begin
    if FName.Contains('.') then
      raise EInvalidOperation.Create('Conditional qualified import requires occurrence-aware editing.');
    FinishName;
  end;
  if FLexer.TokenID in [ptComma, ptSemiColon] then
    FinishName;
  if FLexer.TokenID = ptSemiColon then
    FInsideUses := False;
  if FLexer.TokenID = ptPoint then
  begin
    if FName.IsEmpty then
      raise EInvalidOperation.Create('Partial conditional unit name requires occurrence-aware editing.');
    FName := FName + '.';
  end;
  if FLexer.TokenID <> ptIdentifier then
    Exit;
  FName := FName + FLexer.Token;
  FConditional := FConditional or (FDepth > 0);
end;

function TConditionalImportScanner.Find(const ASource: string): TArray<string>;
begin
  FDepth := 0;
  FInsideUses := False;
  FConditional := False;
  FName := '';
  FNames.Clear;
  FLexer.Origin := ASource;
  while FLexer.TokenID <> ptNull do
  begin
    Visit;
    FLexer.Next;
  end;
  Result := FNames.ToArray;
end;

end.
