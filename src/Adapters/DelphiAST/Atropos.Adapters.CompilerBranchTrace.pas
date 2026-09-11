unit Atropos.Adapters.CompilerBranchTrace;

interface

uses System.SysUtils, System.Generics.Collections, Atropos.Core.SourceTokens;

type
  TCompilerTraceIncludeReader = reference to function(const AParent, AName: string;
    out AContent, APath: string): Boolean;
  TCompilerTraceInclude = record
    Name, ParentPath, SourcePath, Content: string;
  end;
  TCompilerTraceSource = class
  public
    Text, Path, CloneName: string;
    Tokens: TArray<TSourceToken>;
    BranchIds, EntryIds, ExitIds: TArray<Integer>;
    Children: TArray<TCompilerTraceSource>;
    IncludeNames: TArray<string>;
  end;
  TCompilerTraceBranch = record
    ParentActive, Taken, ElseSeen: Boolean;
  end;

  TCompilerBranchTrace = class
  private
    FPrefix: string;
    FRoot: TCompilerTraceSource;
    FSources: TObjectList<TCompilerTraceSource>;
    FLoading: TList<string>;
    FPreparedIncludes: TList<TCompilerTraceInclude>;
    FReadInclude: TCompilerTraceIncludeReader;
    FCount: Integer;
    FSelected: TDictionary<Integer, Boolean>;
    FBranches: TList<TCompilerTraceBranch>;
    FActive: Boolean;
    class function DirectiveName(const AText: string): string; static;
    class function IsBranch(const AName: string): Boolean; static;
    class function Blank(const AText: string): string; static;
    function Marker(AId: Integer): string;
    function NextId: Integer;
    function Consume(AId: Integer): Boolean;
    function BuildSource(const ASource, APath: string): TCompilerTraceSource;
    procedure BuildInclude(ASource: TCompilerTraceSource; AIndex: Integer);
    function InstrumentSource(ASource: TCompilerTraceSource): string;
    function ReplaySource(ASource: TCompilerTraceSource): string;
    procedure ReplayInclude(ASource: TCompilerTraceSource; AIndex: Integer);
    procedure ReadTrace(const AOutput: string; ACount: Integer);
    procedure OpenBranch(ASelected: Boolean);
    procedure NextBranch(const AName: string; ASelected: Boolean);
    procedure CloseBranch(ASelected: Boolean);
    procedure ApplyBranch(const AName: string; AId: Integer);
  public
    constructor Create(const ASource: string; const APath: string = '';
      const AReadInclude: TCompilerTraceIncludeReader = nil);
    destructor Destroy; override;
    function Instrument: string;
    // Caller must establish successful compilation and stable compiler inputs.
    function Replay(const ACompilerOutput: string): string;
    function InstrumentedIncludes: TArray<TCompilerTraceInclude>;
    function PreparedIncludes: TArray<TCompilerTraceInclude>;
    property Prefix: string read FPrefix;
  end;

implementation

uses System.Classes, System.Character, System.RegularExpressions;

constructor TCompilerBranchTrace.Create(const ASource, APath: string;
  const AReadInclude: TCompilerTraceIncludeReader);
begin
  inherited Create;
  FPrefix := 'ATROPOS_TRACE_' + TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '').Replace('-', '') + '_';
  FSelected := TDictionary<Integer, Boolean>.Create;
  FBranches := TList<TCompilerTraceBranch>.Create;
  FSources := TObjectList<TCompilerTraceSource>.Create(True);
  FLoading := TList<string>.Create;
  FPreparedIncludes := TList<TCompilerTraceInclude>.Create;
  FReadInclude := AReadInclude;
  FRoot := BuildSource(ASource, APath);
end;

function TCompilerBranchTrace.NextId: Integer;
begin
  Inc(FCount);
  Result := FCount;
end;

function TCompilerBranchTrace.BuildSource(const ASource, APath: string): TCompilerTraceSource;
var LTokenizer: TSourceTokenizer; I: Integer; LName: string;
begin
  Result := TCompilerTraceSource.Create;
  FSources.Add(Result);
  Result.Text := ASource;
  Result.Path := APath;
  LTokenizer := TSourceTokenizer.Create;
  try
    Result.Tokens := LTokenizer.Read(ASource);
  finally
    LTokenizer.Free;
  end;
  SetLength(Result.BranchIds, Length(Result.Tokens));
  SetLength(Result.EntryIds, Length(Result.Tokens));
  SetLength(Result.ExitIds, Length(Result.Tokens));
  SetLength(Result.Children, Length(Result.Tokens));
  SetLength(Result.IncludeNames, Length(Result.Tokens));
  FLoading.Add(APath);
  try
    for I := 0 to High(Result.Tokens) do
    begin
      if Result.Tokens[I].Kind <> stDirective then Continue;
      LName := DirectiveName(Result.Tokens[I].Text);
      if IsBranch(LName) then Result.BranchIds[I] := NextId;
      if (LName = 'I') or (LName = 'INCLUDE') then BuildInclude(Result, I);
    end;
  finally
    FLoading.Delete(FLoading.Count - 1);
  end;
end;

procedure TCompilerBranchTrace.BuildInclude(ASource: TCompilerTraceSource; AIndex: Integer);
var LBody, LName, LContent, LPath, LLoading: string; I: Integer;
begin
  if not Assigned(FReadInclude) then
    raise EInvalidOpException.Create('Compiler branch trace requires include invocation tracking.');
  LBody := ASource.Tokens[AIndex].Text;
  if LBody.StartsWith('{$') then LBody := Copy(LBody, 3, Length(LBody) - 3);
  if LBody.StartsWith('(*$') then LBody := Copy(LBody, 4, Length(LBody) - 5);
  LBody := LBody.Trim;
  I := 1;
  while (I <= Length(LBody)) and not LBody[I].IsWhiteSpace do Inc(I);
  LName := Copy(LBody, I, MaxInt).Trim;
  if (Length(LName) >= 2) and CharInSet(LName[1], ['''', '"']) and
    (LName[Length(LName)] = LName[1]) then LName := Copy(LName, 2, Length(LName) - 2);
  ASource.IncludeNames[AIndex] := LName;
  ASource.EntryIds[AIndex] := NextId;
  if FReadInclude(ASource.Path, LName, LContent, LPath) then
  begin
    if FLoading.Count >= 64 then raise EInvalidOpException.Create('Compiler trace include nesting exceeds 64.');
    for LLoading in FLoading do
      if SameText(LLoading, LPath) then raise EInvalidOpException.Create('Recursive compiler trace include.');
    ASource.Children[AIndex] := BuildSource(LContent, LPath);
    ASource.Children[AIndex].CloneName := FPrefix.Replace('ATROPOS_TRACE_', 'ATROPOS_INCLUDE_') +
      IntToStr(ASource.EntryIds[AIndex]) + '.inc';
  end;
  ASource.ExitIds[AIndex] := NextId;
end;

destructor TCompilerBranchTrace.Destroy;
begin
  FPreparedIncludes.Free;
  FLoading.Free;
  FSources.Free;
  FBranches.Free;
  FSelected.Free;
  inherited;
end;

class function TCompilerBranchTrace.DirectiveName(const AText: string): string;
var LBody: string; I: Integer;
begin
  LBody := Copy(AText, 3, Length(AText) - 3);
  if AText.StartsWith('(*$') then LBody := Copy(AText, 4, Length(AText) - 5);
  LBody := LBody.Trim;
  I := 1;
  while (I <= Length(LBody)) and not LBody[I].IsWhiteSpace do Inc(I);
  Result := UpperCase(Copy(LBody, 1, I - 1));
end;

class function TCompilerBranchTrace.IsBranch(const AName: string): Boolean;
begin
  Result := (AName = 'IF') or (AName = 'IFDEF') or (AName = 'IFNDEF') or
    (AName = 'IFOPT') or (AName = 'ELSE') or (AName = 'ELSEIF') or
    (AName = 'ENDIF') or (AName = 'IFEND');
end;

class function TCompilerBranchTrace.Blank(const AText: string): string;
var I: Integer;
begin
  Result := AText;
  for I := 1 to Length(Result) do
    if not CharInSet(Result[I], [#10, #13]) then Result[I] := ' ';
end;

function TCompilerBranchTrace.Marker(AId: Integer): string;
begin
  Result := '{$HINTS ON}{$MESSAGE HINT ''' + FPrefix + IntToStr(AId) + '''}';
end;

function TCompilerBranchTrace.InstrumentSource(ASource: TCompilerTraceSource): string;
var LBuilder: TStringBuilder; LToken: TSourceToken; LPosition, I: Integer; LPart: string;
begin
  LBuilder := TStringBuilder.Create;
  try
    LPosition := 1;
    for I := 0 to High(ASource.Tokens) do
    begin
      LToken := ASource.Tokens[I];
      LBuilder.Append(Copy(ASource.Text, LPosition, LToken.StartOffset - LPosition));
      LPart := LToken.Text;
      if Assigned(ASource.Children[I]) then LPart := '{$I ' + ASource.Children[I].CloneName + '}';
      if ASource.EntryIds[I] > 0 then LBuilder.Append(Marker(ASource.EntryIds[I]));
      LBuilder.Append(LPart);
      if ASource.ExitIds[I] > 0 then LBuilder.Append(Marker(ASource.ExitIds[I]));
      LPosition := LToken.EndOffset;
      if ASource.BranchIds[I] > 0 then LBuilder.Append(Marker(ASource.BranchIds[I]));
    end;
    LBuilder.Append(Copy(ASource.Text, LPosition, MaxInt));
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

function TCompilerBranchTrace.Instrument: string;
begin
  Result := Marker(0) + InstrumentSource(FRoot);
end;

function TCompilerBranchTrace.InstrumentedIncludes: TArray<TCompilerTraceInclude>;
var LSource: TCompilerTraceSource; LInclude: TCompilerTraceInclude; LItems: TList<TCompilerTraceInclude>;
begin
  LItems := TList<TCompilerTraceInclude>.Create;
  try
    for LSource in FSources do
    begin
      if LSource.CloneName.IsEmpty then Continue;
      LInclude := Default(TCompilerTraceInclude);
      LInclude.Name := LSource.CloneName;
      LInclude.SourcePath := LSource.Path;
      LInclude.Content := InstrumentSource(LSource);
      LItems.Add(LInclude);
    end;
    Result := LItems.ToArray;
  finally
    LItems.Free;
  end;
end;

function TCompilerBranchTrace.PreparedIncludes: TArray<TCompilerTraceInclude>;
begin
  Result := FPreparedIncludes.ToArray;
end;

function TCompilerBranchTrace.Consume(AId: Integer): Boolean;
begin
  Result := FSelected.ContainsKey(AId);
  FSelected.Remove(AId);
end;

procedure TCompilerBranchTrace.ReadTrace(const AOutput: string; ACount: Integer);
var LMatch: TMatch; LId, LPrevious: Integer;
begin
  FSelected.Clear;
  LPrevious := -1;
  for LMatch in TRegEx.Matches(AOutput, FPrefix + '(\d+)(?=\s*(?:\r?\n|$))') do
  begin
    if not TryStrToInt(LMatch.Groups[1].Value, LId) then
      raise EInvalidOpException.Create('Invalid compiler branch marker.');
    if (LId <= LPrevious) or (LId > ACount) then
      raise EInvalidOpException.Create('Compiler branch markers are duplicated, unordered or out of range.');
    FSelected.Add(LId, True);
    LPrevious := LId;
  end;
  if not FSelected.ContainsKey(0) then
    raise EInvalidOpException.Create('Compiler branch trace has no start marker.');
end;

procedure TCompilerBranchTrace.OpenBranch(ASelected: Boolean);
var LBranch: TCompilerTraceBranch;
begin
  if ASelected and not FActive then raise EInvalidOpException.Create('Active branch has an inactive parent.');
  LBranch := Default(TCompilerTraceBranch);
  LBranch.ParentActive := FActive;
  LBranch.Taken := ASelected;
  FBranches.Add(LBranch);
  FActive := ASelected;
end;

procedure TCompilerBranchTrace.NextBranch(const AName: string; ASelected: Boolean);
var LBranch: TCompilerTraceBranch;
begin
  if FBranches.Count = 0 then raise EInvalidOpException.Create('Unmatched conditional alternative.');
  LBranch := FBranches.Last;
  if LBranch.ElseSeen then raise EInvalidOpException.Create('Conditional alternative follows ELSE.');
  if ASelected and (not LBranch.ParentActive or LBranch.Taken) then
    raise EInvalidOpException.Create('Compiler selected an impossible conditional alternative.');
  if (AName = 'ELSE') and LBranch.ParentActive and not LBranch.Taken and not ASelected then
    raise EInvalidOpException.Create('Compiler branch trace is missing ELSE.');
  LBranch.ElseSeen := AName = 'ELSE';
  LBranch.Taken := LBranch.Taken or ASelected;
  FBranches[FBranches.Count - 1] := LBranch;
  FActive := ASelected;
end;

procedure TCompilerBranchTrace.CloseBranch(ASelected: Boolean);
begin
  if FBranches.Count = 0 then raise EInvalidOpException.Create('Unmatched conditional end.');
  FActive := FBranches.Last.ParentActive;
  FBranches.Delete(FBranches.Count - 1);
  if ASelected <> FActive then raise EInvalidOpException.Create('Compiler branch trace is missing a conditional boundary.');
end;

procedure TCompilerBranchTrace.ApplyBranch(const AName: string; AId: Integer);
var LSelected: Boolean;
begin
  LSelected := Consume(AId);
  if (AName = 'ENDIF') or (AName = 'IFEND') then begin CloseBranch(LSelected); Exit end;
  if (AName = 'ELSE') or (AName = 'ELSEIF') then begin NextBranch(AName, LSelected); Exit end;
  OpenBranch(LSelected);
end;

procedure TCompilerBranchTrace.ReplayInclude(ASource: TCompilerTraceSource; AIndex: Integer);
var LInclude: TCompilerTraceInclude; LIndex: Integer;
begin
  if Consume(ASource.EntryIds[AIndex]) <> FActive then
    raise EInvalidOpException.Create('Compiler trace include entry is inconsistent.');
  if FActive then
  begin
    if not Assigned(ASource.Children[AIndex]) then
      raise EInvalidOpException.Create('Active compiler include was not instrumented.');
    LInclude := Default(TCompilerTraceInclude);
    LInclude.Name := ASource.IncludeNames[AIndex];
    LInclude.ParentPath := ASource.Path;
    LInclude.SourcePath := ASource.Children[AIndex].Path;
    LIndex := FPreparedIncludes.Add(LInclude);
    LInclude.Content := ReplaySource(ASource.Children[AIndex]);
    FPreparedIncludes[LIndex] := LInclude;
  end;
  if Consume(ASource.ExitIds[AIndex]) <> FActive then
    raise EInvalidOpException.Create('Compiler trace include exit is inconsistent.');
end;

function TCompilerBranchTrace.ReplaySource(ASource: TCompilerTraceSource): string;
var LToken: TSourceToken; LBuilder: TStringBuilder; I, LPosition: Integer; LPart: string;
begin
  LPosition := 1;
  LBuilder := TStringBuilder.Create;
  try
    for I := 0 to High(ASource.Tokens) do
    begin
      LToken := ASource.Tokens[I];
      LBuilder.Append(Copy(ASource.Text, LPosition, LToken.StartOffset - LPosition));
      LPart := LToken.Text;
      if not FActive then LPart := Blank(LPart);
      if ASource.BranchIds[I] > 0 then
      begin
        ApplyBranch(DirectiveName(LToken.Text), ASource.BranchIds[I]);
        LPart := Blank(LToken.Text);
      end;
      if ASource.EntryIds[I] > 0 then ReplayInclude(ASource, I);
      LBuilder.Append(LPart);
      LPosition := LToken.EndOffset;
    end;
    LBuilder.Append(Copy(ASource.Text, LPosition, MaxInt));
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

function TCompilerBranchTrace.Replay(const ACompilerOutput: string): string;
begin
  ReadTrace(ACompilerOutput, FCount);
  FSelected.Remove(0);
  FBranches.Clear;
  FPreparedIncludes.Clear;
  FActive := True;
  Result := ReplaySource(FRoot);
  if FBranches.Count <> 0 then raise EInvalidOpException.Create('Unterminated conditional in compiler branch trace.');
  if FSelected.Count <> 0 then raise EInvalidOpException.Create('Compiler trace contains unexpected active markers.');
end;

end.
