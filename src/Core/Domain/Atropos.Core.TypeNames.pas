unit Atropos.Core.TypeNames;

interface

type
  TTypeName = record
    Name: string;
    Arity: Integer;
    class function Read(const AText: string): TTypeName; static;
    class function FirstSegment(const AText: string): string; static;
    class function LastSegment(const AText: string): string; static;
    class function Parameters(ACount: Integer): string; static;
  end;

implementation

uses System.SysUtils;

class function TTypeName.Read(const AText: string): TTypeName;
var I, LDepth: Integer; LChar: Char;
begin
  Result := Default(TTypeName);
  Result.Name := AText.Trim.ToLower;
  LDepth := 0;
  for I := 1 to Length(AText) do
  begin
    LChar := AText[I];
    if LChar = '<' then
    begin
      if LDepth = 0 then
      begin
        Result.Name := Copy(AText, 1, I - 1).Trim.ToLower;
        Result.Arity := 1;
      end;
      Inc(LDepth);
    end;
    if (LChar = ',') and (LDepth = 1) then
      Inc(Result.Arity);
    if LChar = '>' then
      Dec(LDepth);
  end;
end;

class function TTypeName.FirstSegment(const AText: string): string;
var I, LDepth: Integer;
begin
  LDepth := 0;
  for I := 1 to Length(AText) do
  begin
    if AText[I] = '<' then
      Inc(LDepth);
    if AText[I] = '>' then
      Dec(LDepth);
    if (AText[I] = '.') and (LDepth = 0) then
      Exit(Copy(AText, 1, I - 1));
  end;
  Result := AText;
end;

class function TTypeName.LastSegment(const AText: string): string;
var I, LDepth, LStart: Integer;
begin
  LDepth := 0;
  LStart := 1;
  for I := 1 to Length(AText) do
  begin
    if AText[I] = '<' then
      Inc(LDepth);
    if AText[I] = '>' then
      Dec(LDepth);
    if (AText[I] = '.') and (LDepth = 0) then
      LStart := I + 1;
  end;
  Result := Copy(AText, LStart, MaxInt);
end;

class function TTypeName.Parameters(ACount: Integer): string;
begin
  if ACount <= 0 then
    Exit('');
  Result := '<T' + StringOfChar(',', ACount - 1) + '>';
end;

end.
