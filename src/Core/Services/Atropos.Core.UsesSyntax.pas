unit Atropos.Core.UsesSyntax;

interface

uses Atropos.Core.Analysis, Atropos.Core.SourceTokens, System.Generics.Collections;

type
  TUsesOccurrence = record
    Name, Condition: string;
    Section: TUsesSection;
    StartOffset, EndOffset, Separator: Integer;
  end;
  TUsesClause = class
  public
    Section: TUsesSection;
    Keyword, Terminator, GuardStart, GuardEnd: Integer;
    Complete, HasDirectives: Boolean;
    Condition: string;
    Entries: TList<TUsesOccurrence>;
    constructor Create;
    destructor Destroy; override;
  end;
  TUsesSource = class
  private
    FTokens: TArray<TSourceToken>;
    function NextCode(AIndex: Integer; AClause: TUsesClause): Integer;
    function ReadEntry(var AIndex: Integer; AClause: TUsesClause): Boolean;
    procedure ReadClause(var AIndex: Integer; ASection: TUsesSection);
    procedure LocateGuard(AClause: TUsesClause);
  public
    Source: string;
    Clauses: TObjectList<TUsesClause>;
    SectionEnd: array[TUsesSection] of Integer;
    constructor Create(const ASource: string);
    destructor Destroy; override;
    function Find(const AName: string; ASection: TUsesSection;
      out AClause: TUsesClause; out AIndex: Integer): Boolean;
    function SectionClause(ASection: TUsesSection): TUsesClause;
    function Comments(AStart, AEnd: Integer): string;
    function HasDirectivesIn(AStart, AEnd: Integer): Boolean;
    function HasHeaderInclude(ASection: TUsesSection): Boolean;
    function LineBreak: string;
  end;

implementation

uses System.SysUtils;

constructor TUsesClause.Create;
begin
  inherited;
  Entries := TList<TUsesOccurrence>.Create;
end;

destructor TUsesClause.Destroy;
begin
  Entries.Free;
  inherited;
end;

constructor TUsesSource.Create(const ASource: string);
var LLexer: TSourceTokenizer; I: Integer; LSection: TUsesSection; LStarted: Boolean;
begin
  inherited Create;
  Source := ASource;
  Clauses := TObjectList<TUsesClause>.Create(True);
  LLexer := TSourceTokenizer.Create;
  try
    FTokens := LLexer.Read(Source);
  finally
    LLexer.Free;
  end;
  I := 0;
  LStarted := False;
  LSection := usInterface;
  while I < Length(FTokens) do
  begin
    if not LStarted and FTokens[I].IsWord('interface') then
    begin
      LStarted := True;
      SectionEnd[usInterface] := FTokens[I].EndOffset;
    end;
    if LStarted and (LSection = usInterface) and FTokens[I].IsWord('implementation') then
    begin
      LSection := usImplementation;
      SectionEnd[LSection] := FTokens[I].EndOffset;
    end;
    if LStarted and FTokens[I].IsWord('uses') then
      ReadClause(I, LSection);
    Inc(I);
  end;
end;

destructor TUsesSource.Destroy;
begin
  Clauses.Free;
  inherited;
end;

function TUsesSource.NextCode(AIndex: Integer; AClause: TUsesClause): Integer;
begin
  Result := AIndex;
  while Result < Length(FTokens) do
  begin
    if not (FTokens[Result].Kind in [stComment, stDirective]) then
      Exit;
    if FTokens[Result].Kind = stDirective then
      AClause.HasDirectives := True;
    Inc(Result);
  end;
end;

function TUsesSource.ReadEntry(var AIndex: Integer; AClause: TUsesClause): Boolean;
var LEntry: TUsesOccurrence; LLast: Integer;
begin
  Result := False;
  AIndex := NextCode(AIndex, AClause);
  if AIndex >= Length(FTokens) then
    Exit;
  if FTokens[AIndex].Kind <> stIdentifier then
    Exit;
  LEntry := Default(TUsesOccurrence);
  LEntry.Section := AClause.Section;
  LEntry.Name := FTokens[AIndex].Text;
  LEntry.StartOffset := FTokens[AIndex].StartOffset;
  LEntry.Condition := FTokens[AIndex].Condition;
  LLast := AIndex;
  AIndex := NextCode(AIndex + 1, AClause);
  while (AIndex < Length(FTokens)) and (FTokens[AIndex].Text = '.') do
  begin
    AIndex := NextCode(AIndex + 1, AClause);
    if (AIndex >= Length(FTokens)) or (FTokens[AIndex].Kind <> stIdentifier) then
      Exit;
    LEntry.Name := LEntry.Name + '.' + FTokens[AIndex].Text;
    LLast := AIndex;
    AIndex := NextCode(AIndex + 1, AClause);
  end;
  if (AIndex < Length(FTokens)) and FTokens[AIndex].IsWord('in') then
  begin
    AIndex := NextCode(AIndex + 1, AClause);
    if (AIndex >= Length(FTokens)) or (FTokens[AIndex].Kind <> stString) then
      Exit;
    LLast := AIndex;
    AIndex := NextCode(AIndex + 1, AClause);
  end;
  LEntry.EndOffset := FTokens[LLast].EndOffset;
  if AIndex >= Length(FTokens) then
    Exit;
  if not ((FTokens[AIndex].Text = ',') or (FTokens[AIndex].Text = ';')) then
  begin
    if (FTokens[AIndex].Kind <> stIdentifier) or LEntry.Condition.IsEmpty or
      not FTokens[AIndex].Condition.StartsWith(LEntry.Condition + ':') then
      Exit;
    // Mutually exclusive alternatives share the eventual comma/semicolon.
    // Their conditional entries remain immutable and have no physical separator here.
    LEntry.Separator := 0;
    AClause.Entries.Add(LEntry);
    Dec(AIndex);
    Exit(True);
  end;
  LEntry.Separator := FTokens[AIndex].StartOffset;
  AClause.Entries.Add(LEntry);
  Result := True;
end;

procedure TUsesSource.ReadClause(var AIndex: Integer; ASection: TUsesSection);
var LClause: TUsesClause; LCursor: Integer;
begin
  LClause := TUsesClause.Create;
  Clauses.Add(LClause);
  LClause.Section := ASection;
  LClause.Keyword := FTokens[AIndex].StartOffset;
  LClause.Condition := FTokens[AIndex].Condition;
  LCursor := AIndex + 1;
  while ReadEntry(LCursor, LClause) do
  begin
    if FTokens[LCursor].Text = ';' then
    begin
      LClause.Terminator := FTokens[LCursor].StartOffset;
      LClause.Complete := True;
      AIndex := LCursor;
      LocateGuard(LClause);
      Exit;
    end;
    Inc(LCursor);
  end;
end;

procedure TUsesSource.LocateGuard(AClause: TUsesClause);
var LToken: TSourceToken; LAfter: Boolean;
begin
  if AClause.Condition.IsEmpty or AClause.Condition.Contains('/') or
    AClause.Condition.Contains(':') or AClause.HasDirectives then
    Exit;
  AClause.GuardStart := StrToIntDef(AClause.Condition, 0);
  LAfter := False;
  for LToken in FTokens do
  begin
    if LToken.StartOffset <= AClause.Terminator then
      Continue;
    if LToken.Kind = stComment then
      Continue;
    LAfter := (LToken.Kind = stDirective) and
      (LToken.Text.ToUpper.StartsWith('{$ENDIF') or LToken.Text.ToUpper.StartsWith('{$IFEND') or
       LToken.Text.ToUpper.StartsWith('(*$ENDIF') or LToken.Text.ToUpper.StartsWith('(*$IFEND'));
    if LAfter then
      AClause.GuardEnd := LToken.EndOffset;
    Exit;
  end;
end;

function TUsesSource.Find(const AName: string; ASection: TUsesSection;
  out AClause: TUsesClause; out AIndex: Integer): Boolean;
var LClause: TUsesClause; I, LCount: Integer;
begin
  AClause := nil;
  AIndex := -1;
  LCount := 0;
  for LClause in Clauses do
    if LClause.Section = ASection then
      for I := 0 to LClause.Entries.Count - 1 do
        if SameText(LClause.Entries[I].Name, AName) then
        begin
          Inc(LCount);
          AClause := LClause;
          AIndex := I;
        end;
  Result := LCount = 1;
end;

function TUsesSource.SectionClause(ASection: TUsesSection): TUsesClause;
var LClause: TUsesClause;
begin
  Result := nil;
  for LClause in Clauses do
    if LClause.Section = ASection then
    begin
      if Assigned(Result) then
        Exit(nil);
      Result := LClause;
    end;
end;

function TUsesSource.LineBreak: string;
var I: Integer;
begin
  for I := 1 to Length(Source) do
  begin
    if Source[I] = #10 then
      Exit(#10);
    if Source[I] = #13 then
    begin
      if (I < Length(Source)) and (Source[I + 1] = #10) then
        Exit(#13#10);
      Exit(#13);
    end;
  end;
  Result := sLineBreak;
end;

function TUsesSource.Comments(AStart, AEnd: Integer): string;
var LToken: TSourceToken;
begin
  Result := '';
  for LToken in FTokens do
    if (LToken.StartOffset >= AStart) and (LToken.EndOffset <= AEnd) and
      (LToken.Kind = stComment) then
    begin
      Result := Result + LToken.Text;
      if LToken.Text.StartsWith('//') then
        Result := Result + LineBreak;
      if not LToken.Text.StartsWith('//') then
        Result := Result + ' ';
    end;
end;

function TUsesSource.HasDirectivesIn(AStart, AEnd: Integer): Boolean;
var LToken: TSourceToken;
begin
  for LToken in FTokens do
    if (LToken.Kind = stDirective) and (LToken.StartOffset < AEnd) and
      (LToken.EndOffset > AStart) then
      Exit(True);
  Result := False;
end;

function TUsesSource.HasHeaderInclude(ASection: TUsesSection): Boolean;
var LToken: TSourceToken; LName: string;
begin
  for LToken in FTokens do
  begin
    if LToken.StartOffset < SectionEnd[ASection] then
      Continue;
    if not (LToken.Kind in [stComment, stDirective]) then
      Exit(False);
    if LToken.Kind <> stDirective then
      Continue;
    LName := LToken.Text.Replace('(*$', '').Replace('{$', '').ToUpper;
    LName := LName.Split([' ', #9, #10, #13, '}', '*'])[0];
    if (LName = 'I') or (LName = 'INCLUDE') then
      Exit(True);
  end;
  Result := False;
end;

end.
