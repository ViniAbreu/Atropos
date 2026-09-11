unit Atropos.Adapters.ConditionalSource;

interface

uses System.SysUtils, System.Generics.Collections, SimpleParser.Lexer.Types,
  Atropos.Core.Compilation, Atropos.Core.Ports, Atropos.Core.SourceTokens,
  Atropos.Adapters.SourceIncludes, Atropos.Adapters.ConditionalExpression;

type
  TConditionalBranch = record
    ParentActive, Active, Taken, ElseSeen: Boolean;
  end;
  TPreparedInclude = record
    Content, FileName: string;
  end;
  TConditionalSource = class(TInterfacedObject, IIncludeHandler)
  private
    FInput: IIncludeHandler;
    FResolver: TSourceIncludeResolver;
    FBaseDefined: TFunc<string, Boolean>;
    FDefines, FSwitches: TDictionary<string, Boolean>;
    FBranches: TList<TConditionalBranch>;
    FIncludes: TDictionary<string, TPreparedInclude>;
    FExpression: TConditionalExpression;
    function Active: Boolean;
    function Defined(const AName: string): Boolean;
    function SwitchValue(const AText: string): Boolean;
    procedure SetSwitch(const AName, AValue: string);
    procedure ShortSwitches(const AText: string);
    procedure Branch(const AName, AArgument: string);
    function Directive(const AText, AFilePath: string): string;
    function IncludeSource(const AName, AFilePath: string): string;
    function Transform(const ASource, AFilePath: string): string;
    class function Blank(const AText: string): string; static;
    class function SwitchName(const AName: string): string; static;
  public
    constructor Create(AResolver: TSourceIncludeResolver;
      const ADefined: TFunc<string, Boolean>; const ACompilerVersion: string;
      const AOptions: TArray<TCompilerOption>; const ANumbers: TArray<TCompilerOption> = nil);
    destructor Destroy; override;
    function Prepare(const ASource, AFilePath: string): string;
    function GetIncludeFileContent(const ParentFileName, IncludeName: string;
      out Content, FileName: string): Boolean;
    function GetDependencies: TArray<TSourceDependency>;
  end;

implementation

uses System.Character;

constructor TConditionalSource.Create(AResolver: TSourceIncludeResolver;
  const ADefined: TFunc<string, Boolean>; const ACompilerVersion: string;
  const AOptions: TArray<TCompilerOption>; const ANumbers: TArray<TCompilerOption>);
var LOption: TCompilerOption; LLookup: TFunc<string, Boolean>;
begin
  inherited Create;
  FResolver := AResolver;
  FInput := AResolver;
  FBaseDefined := ADefined;
  FDefines := TDictionary<string, Boolean>.Create;
  FSwitches := TDictionary<string, Boolean>.Create;
  FBranches := TList<TConditionalBranch>.Create;
  FIncludes := TDictionary<string, TPreparedInclude>.Create;
  LLookup := function(AName: string): Boolean
    begin Result := Self.Defined(AName); end;
  FExpression := TConditionalExpression.Create(LLookup, ACompilerVersion, ANumbers);
  for LOption in AOptions do
    SetSwitch(SwitchName(LOption.Name), LOption.Value);
end;

destructor TConditionalSource.Destroy;
begin
  FExpression.Free;
  FIncludes.Free;
  FBranches.Free;
  FSwitches.Free;
  FDefines.Free;
  inherited;
end;

procedure TConditionalSource.ShortSwitches(const AText: string);
var LPart, LSwitch: string;
begin
  for LPart in AText.Split([',']) do
  begin
    LSwitch := LPart.Trim;
    if (Length(LSwitch) <> 2) or not CharInSet(LSwitch[2], ['+', '-']) then
      raise EInvalidOpException.Create('Unsupported compiler switch list: ' + AText);
    SetSwitch(LSwitch[1], LSwitch[2]);
  end;
end;

class function TConditionalSource.SwitchName(const AName: string): string;
begin
  Result := UpperCase(AName);
  if (Result = 'RANGECHECKING') or (Result = 'RANGECHECKS') then Exit('R');
  if (Result = 'OVERFLOWCHECKING') or (Result = 'OVERFLOWCHECKS') then Exit('Q');
  if (Result = 'ASSERTIONSATRUNTIME') or (Result = 'ASSERTIONS') then Exit('C');
  if (Result = 'COMPLETEBOOLEANEVAL') or (Result = 'BOOLEVAL') then Exit('B');
  if (Result = 'WRITABLECONSTANTS') or (Result = 'WRITEABLECONST') then Exit('J');
  if (Result = 'TYPEDATPARAMETER') or (Result = 'TYPEDADDRESS') then Exit('T');
end;

procedure TConditionalSource.SetSwitch(const AName, AValue: string);
var LValue: string;
begin
  if Length(AName) <> 1 then Exit;
  LValue := UpperCase(AValue.Trim);
  if LValue.IsEmpty then Exit;
  if (LValue <> '+') and (LValue <> 'ON') and (LValue <> 'TRUE') and
    (LValue <> '-') and (LValue <> 'OFF') and (LValue <> 'FALSE') then
    raise EInvalidOpException.Create('Unsupported compiler switch value: ' + AName + '=' + AValue);
  if (LValue = '+') or (LValue = 'ON') or (LValue = 'TRUE') then
    FSwitches.AddOrSetValue(AName, True);
  if (LValue = '-') or (LValue = 'OFF') or (LValue = 'FALSE') then
    FSwitches.AddOrSetValue(AName, False);
end;

function TConditionalSource.Active: Boolean;
begin
  if FBranches.Count = 0 then Exit(True);
  Result := FBranches.Last.Active;
end;

function TConditionalSource.Defined(const AName: string): Boolean;
begin
  if FDefines.TryGetValue(UpperCase(AName), Result) then Exit;
  Result := FBaseDefined(AName);
end;

function TConditionalSource.SwitchValue(const AText: string): Boolean;
var LText: string; LValue: Boolean;
begin
  LText := UpperCase(AText.Trim);
  if (Length(LText) <> 2) or not CharInSet(LText[2], ['+', '-']) then
    raise EInvalidOpException.Create('Unsupported IFOPT argument: ' + AText);
  if not FSwitches.TryGetValue(LText[1], LValue) then
    raise EInvalidOpException.Create('Compiler switch is unknown for IFOPT: ' + AText);
  Result := LValue = (LText[2] = '+');
end;

procedure TConditionalSource.Branch(const AName, AArgument: string);
var LBranch: TConditionalBranch; LValue: Boolean;
begin
  if (AName = 'IF') or (AName = 'IFDEF') or (AName = 'IFNDEF') or (AName = 'IFOPT') then
  begin
    LBranch := Default(TConditionalBranch);
    LBranch.ParentActive := Active;
    LValue := False;
    if Active and (AName = 'IF') then LValue := FExpression.Evaluate(AArgument);
    if Active and (AName = 'IFOPT') then LValue := SwitchValue(AArgument);
    if Active and (AName = 'IFDEF') then LValue := Defined(AArgument.Trim);
    if Active and (AName = 'IFNDEF') then LValue := not Defined(AArgument.Trim);
    LBranch.Active := LBranch.ParentActive and LValue;
    LBranch.Taken := LBranch.Active;
    FBranches.Add(LBranch);
    Exit;
  end;
  if FBranches.Count = 0 then
    raise EInvalidOpException.Create('Unmatched conditional directive: ' + AName);
  if (AName = 'ENDIF') or (AName = 'IFEND') then
  begin
    FBranches.Delete(FBranches.Count - 1);
    Exit;
  end;
  LBranch := FBranches.Last;
  if LBranch.ElseSeen then
    raise EInvalidOpException.Create('Conditional branch after ELSE.');
  LValue := LBranch.ParentActive and not LBranch.Taken;
  if LValue and (AName = 'ELSEIF') then LValue := FExpression.Evaluate(AArgument);
  LBranch.Active := LValue;
  LBranch.Taken := LBranch.Taken or LValue;
  LBranch.ElseSeen := AName = 'ELSE';
  FBranches[FBranches.Count - 1] := LBranch;
end;

class function TConditionalSource.Blank(const AText: string): string;
var I: Integer;
begin
  Result := AText;
  for I := 1 to Length(Result) do
    if not CharInSet(Result[I], [#10, #13]) then Result[I] := ' ';
end;

function TConditionalSource.IncludeSource(const AName, AFilePath: string): string;
var LName, LKey: string; LInclude: TPreparedInclude;
begin
  LName := AName.Trim;
  if (Length(LName) >= 2) and CharInSet(LName[1], ['''', '"']) and
    (LName[Length(LName)] = LName[1]) then
    LName := Copy(LName, 2, Length(LName) - 2);
  FInput.GetIncludeFileContent(AFilePath, LName, LInclude.Content, LInclude.FileName);
  LInclude.Content := Transform(LInclude.Content, LInclude.FileName);
  LKey := '__atropos_prepared_' + IntToStr(FIncludes.Count) + '.inc';
  FIncludes.Add(LKey, LInclude);
  Result := '{$I ' + LKey + '}';
end;

function TConditionalSource.Directive(const AText, AFilePath: string): string;
var LBody, LName, LArgument: string; I: Integer;
begin
  LBody := Copy(AText, 3, Length(AText) - 3);
  if AText.StartsWith('(*$') then LBody := Copy(AText, 4, Length(AText) - 5);
  LBody := LBody.Trim;
  I := 1;
  while (I <= Length(LBody)) and not LBody[I].IsWhiteSpace do Inc(I);
  LName := UpperCase(Copy(LBody, 1, I - 1));
  LArgument := Copy(LBody, I, MaxInt).Trim;
  Result := Blank(AText);
  if (LName = 'IF') or (LName = 'IFDEF') or (LName = 'IFNDEF') or
    (LName = 'IFOPT') or (LName = 'ELSE') or (LName = 'ELSEIF') or
    (LName = 'ENDIF') or (LName = 'IFEND') then
  begin
    Branch(LName, LArgument);
    Exit;
  end;
  if not Active then Exit;
  if (LName = 'PUSH') or (LName = 'POP') then
    raise EInvalidOpException.Create('Unsupported compiler option directive: ' + LName);
  if (LName = 'DEFINE') or (LName = 'UNDEF') then
  begin
    FDefines.AddOrSetValue(UpperCase(LArgument), LName = 'DEFINE');
    Exit;
  end;
  if (LName = 'I') or (LName = 'INCLUDE') then
    Exit(IncludeSource(LArgument, AFilePath) + Blank(AText));
  if (Length(LName) >= 2) and CharInSet(LName[2], ['+', '-']) then
    ShortSwitches(UpperCase(LBody));
  if Length(LName) > 1 then
    SetSwitch(SwitchName(LName), LArgument);
  Result := AText;
end;

function TConditionalSource.Transform(const ASource, AFilePath: string): string;
var LLexer: TSourceTokenizer; LToken: TSourceToken; LTokens: TArray<TSourceToken>;
  LPosition: Integer; LPart: string; LOutput: TStringBuilder;
begin
  LLexer := TSourceTokenizer.Create;
  LOutput := TStringBuilder.Create;
  try
    LTokens := LLexer.Read(ASource);
    LPosition := 1;
    for LToken in LTokens do
    begin
      LOutput.Append(Copy(ASource, LPosition, LToken.StartOffset - LPosition));
      LPart := LToken.Text;
      if Active and (LToken.Kind = stIdentifier) then
        FExpression.ObserveIdentifier(LToken.Text);
      if not Active then LPart := Blank(LPart);
      if LToken.Kind = stDirective then LPart := Directive(LToken.Text, AFilePath);
      LOutput.Append(LPart);
      LPosition := LToken.EndOffset;
    end;
    LOutput.Append(Copy(ASource, LPosition, MaxInt));
    Result := LOutput.ToString;
  finally
    LOutput.Free;
    LLexer.Free;
  end;
end;

function TConditionalSource.Prepare(const ASource, AFilePath: string): string;
begin
  Result := Transform(ASource, AFilePath);
  if FBranches.Count <> 0 then
    raise EInvalidOpException.Create('Unterminated conditional directive.');
end;

function TConditionalSource.GetIncludeFileContent(const ParentFileName, IncludeName: string;
  out Content, FileName: string): Boolean;
var LInclude: TPreparedInclude;
begin
  if not FIncludes.TryGetValue(IncludeName, LInclude) then
    raise EInvalidOpException.Create('Include was not prepared: ' + IncludeName);
  Content := LInclude.Content;
  FileName := LInclude.FileName;
  Result := True;
end;

function TConditionalSource.GetDependencies: TArray<TSourceDependency>;
begin
  Result := FResolver.GetDependencies;
end;

end.
