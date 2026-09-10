unit Atropos.Core.SourceTokens;

interface

type
  TSourceTokenKind = (stIdentifier, stSymbol, stString, stComment, stDirective);
  TSourceToken = record
    Kind: TSourceTokenKind;
    Text, Condition: string;
    StartOffset, EndOffset: Integer;
    function IsWord(const AWord: string): Boolean;
  end;
  TSourceTokenizer = class
  private
    FSource: string;
    FPosition: Integer;
    function Current: Char;
    procedure Quoted;
    procedure BlockComment(const AClose: string);
    procedure SkipToken;
  public
    function Read(const ASource: string): TArray<TSourceToken>;
  end;

implementation

uses System.SysUtils, System.Character, System.Generics.Collections;

function TSourceToken.IsWord(const AWord: string): Boolean;
begin
  Result := (Kind = stIdentifier) and SameText(Text, AWord);
end;

function TSourceTokenizer.Current: Char;
begin
  Result := #0;
  if FPosition <= Length(FSource) then
    Result := FSource[FPosition];
end;

procedure TSourceTokenizer.Quoted;
var LQuotes, LStart, LCount: Integer;
begin
  LStart := FPosition;
  while Current = '''' do
    Inc(FPosition);
  LQuotes := FPosition - LStart;
  // Odd runs of three or more quotes followed by a line break open multiline text.
  if (LQuotes >= 3) and Odd(LQuotes) then
  begin
    while CharInSet(Current, [#9, ' ']) do
      Inc(FPosition);
    if CharInSet(Current, [#10, #13]) then
    begin
      while FPosition <= Length(FSource) do
      begin
        LCount := 0;
        while Current = '''' do
        begin
          Inc(LCount);
          Inc(FPosition);
        end;
        if LCount >= LQuotes then
          Exit;
        Inc(FPosition);
      end;
      Exit;
    end;
  end;
  FPosition := LStart + 1;
  while FPosition <= Length(FSource) do
  begin
    if Current <> '''' then
    begin
      Inc(FPosition);
      Continue;
    end;
    Inc(FPosition);
    if Current <> '''' then
      Exit;
    Inc(FPosition);
  end;
end;

procedure TSourceTokenizer.BlockComment(const AClose: string);
begin
  while FPosition <= Length(FSource) do
  begin
    if Copy(FSource, FPosition, Length(AClose)) = AClose then
    begin
      Inc(FPosition, Length(AClose));
      Exit;
    end;
    Inc(FPosition);
  end;
end;

procedure TSourceTokenizer.SkipToken;
begin
  Inc(FPosition);
  while (FPosition <= Length(FSource)) and
    (Current.IsLetterOrDigit or (Current = '_')) do
    Inc(FPosition);
end;

function TSourceTokenizer.Read(const ASource: string): TArray<TSourceToken>;
var LTokens: TList<TSourceToken>; LToken: TSourceToken;
  LConditions: TList<string>; LDirective: string; LBranch: Integer;
begin
  FSource := ASource;
  FPosition := 1;
  LBranch := 0;
  LTokens := TList<TSourceToken>.Create;
  LConditions := TList<string>.Create;
  try
    while FPosition <= Length(FSource) do
    begin
      if Current.IsWhiteSpace or (Current = #$FEFF) then
      begin
        Inc(FPosition);
        Continue;
      end;
      LToken := Default(TSourceToken);
      LToken.StartOffset := FPosition;
      LToken.Kind := stSymbol;
      LToken.Condition := string.Join('/', LConditions.ToArray);
      case Current of
        '''': begin LToken.Kind := stString; Quoted end;
        '{': begin LToken.Kind := stComment; Inc(FPosition); BlockComment('}') end;
        '(': begin
          Inc(FPosition);
          if Current = '*' then
          begin LToken.Kind := stComment; Inc(FPosition); BlockComment('*)') end;
        end;
        '/': begin
          Inc(FPosition);
          if Current = '/' then
          begin
            LToken.Kind := stComment;
            while (FPosition <= Length(FSource)) and not CharInSet(Current, [#10, #13]) do
              Inc(FPosition);
          end;
        end;
      end;
      if FPosition = LToken.StartOffset then
      begin
        if Current.IsLetter or CharInSet(Current, ['_', '&']) then
        begin LToken.Kind := stIdentifier; SkipToken end;
        if LToken.Kind = stSymbol then
          Inc(FPosition);
      end;
      LToken.EndOffset := FPosition;
      LToken.Text := Copy(FSource, LToken.StartOffset, FPosition - LToken.StartOffset);
      if LToken.Text.StartsWith('{$') or LToken.Text.StartsWith('(*$') then
      begin
        LToken.Kind := stDirective;
        LDirective := LToken.Text.Replace('(*$', '').Replace('{$', '').ToUpper;
        LDirective := LDirective.Split([' ', #9, #10, #13, '}', '*'])[0];
        if (LDirective = 'IF') or (LDirective = 'IFDEF') or
          (LDirective = 'IFNDEF') or (LDirective = 'IFOPT') then
          LConditions.Add(IntToStr(LToken.StartOffset));
        if ((LDirective = 'ENDIF') or (LDirective = 'IFEND')) and (LConditions.Count > 0) then
          LConditions.Delete(LConditions.Count - 1);
        if ((LDirective = 'ELSE') or (LDirective = 'ELSEIF')) and (LConditions.Count > 0) then
        begin
          Inc(LBranch);
          LConditions[LConditions.Count - 1] := LConditions.Last + ':' + IntToStr(LBranch);
        end;
      end;
      LTokens.Add(LToken);
    end;
    Result := LTokens.ToArray;
  finally
    LConditions.Free;
    LTokens.Free;
  end;
end;

end.
