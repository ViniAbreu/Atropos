unit Atropos.Adapters.ConditionalExpression;

interface

uses System.SysUtils, System.Generics.Collections, Atropos.Core.Compilation;

type
  ECompilerConditionRequired = class(EInvalidOpException);

  TConditionalValue = record
    Number: Extended;
    IntegerValue: Int64;
    IsBoolean, IsInteger: Boolean;
    class function BooleanValue(AValue: Boolean): TConditionalValue; static;
  end;
  TConditionalExpression = class
  private
    FText, FToken, FCompilerVersion: string;
    FPosition, FDepth: Integer;
    FDefined: TFunc<string, Boolean>;
    FNumbers: TArray<TCompilerOption>;
    FObservedNames: TDictionary<string, Boolean>;
    function KnownNumber(const AName: string): string;
    function NumericName(const AName: string): string;
    function SizeValue: TConditionalValue;
    procedure Next;
    procedure Require(const AToken: string);
    function Atom: TConditionalValue;
    function Unary: TConditionalValue;
    function Comparison: TConditionalValue;
    function Conjunction: TConditionalValue;
    function Disjunction: TConditionalValue;
    function AsBoolean(const AValue: TConditionalValue): Boolean;
    function CompareValues(const ALeft, ARight: TConditionalValue): Integer;
  public
    constructor Create(const ADefined: TFunc<string, Boolean>; const ACompilerVersion: string;
      const ANumbers: TArray<TCompilerOption> = nil);
    destructor Destroy; override;
    procedure ObserveIdentifier(const AName: string);
    function Evaluate(const AText: string): Boolean;
  end;

implementation

uses System.Character;

class function TConditionalValue.BooleanValue(AValue: Boolean): TConditionalValue;
begin
  Result.Number := Ord(AValue);
  Result.IntegerValue := Ord(AValue);
  Result.IsInteger := True;
  Result.IsBoolean := True;
end;

constructor TConditionalExpression.Create(const ADefined: TFunc<string, Boolean>;
  const ACompilerVersion: string; const ANumbers: TArray<TCompilerOption>);
begin
  inherited Create;
  FDefined := ADefined;
  FCompilerVersion := ACompilerVersion;
  FNumbers := Copy(ANumbers);
  FObservedNames := TDictionary<string, Boolean>.Create;
end;

destructor TConditionalExpression.Destroy;
begin
  FObservedNames.Free;
  inherited;
end;

procedure TConditionalExpression.ObserveIdentifier(const AName: string);
begin
  FObservedNames.AddOrSetValue(UpperCase(AName), True);
end;

function TConditionalExpression.KnownNumber(const AName: string): string;
var LOption: TCompilerOption;
begin
  for LOption in FNumbers do
    if SameText(LOption.Name, AName) then
      Exit(LOption.Value);
  raise ECompilerConditionRequired.Create('Unknown compiler numeric fact: ' + AName);
end;

function TConditionalExpression.SizeValue: TConditionalValue;
var LName: string;
begin
  Next;
  Require('(');
  LName := NumericName(FToken);
  Next;
  Require(')');
  Result := Default(TConditionalValue);
  Result.IsInteger := TryStrToInt64(KnownNumber('SIZEOF.' + LName), Result.IntegerValue);
  if not Result.IsInteger then
    raise EInvalidOpException.Create('Invalid compiler size fact: ' + LName);
  Result.Number := Result.IntegerValue;
end;

function TConditionalExpression.NumericName(const AName: string): string;
begin
  if AName.StartsWith('SYSTEM.') then
  begin
    if FObservedNames.ContainsKey('SYSTEM') then
      raise ECompilerConditionRequired.Create('Numeric qualifier requires declaration resolution: SYSTEM');
    Exit(Copy(AName, 8, MaxInt));
  end;
  if FObservedNames.ContainsKey(AName) or FObservedNames.ContainsKey('USES') then
    raise ECompilerConditionRequired.Create('Numeric name requires declaration resolution: ' + AName);
  Result := AName;
end;

procedure TConditionalExpression.Next;
var LStart: Integer; LChar: Char;
begin
  while (FPosition <= Length(FText)) and FText[FPosition].IsWhiteSpace do
    Inc(FPosition);
  FToken := '';
  if FPosition > Length(FText) then Exit;
  LStart := FPosition;
  LChar := FText[FPosition];
  Inc(FPosition);
  if LChar.IsLetterOrDigit or (LChar = '_') then
    while (FPosition <= Length(FText)) and
      (FText[FPosition].IsLetterOrDigit or CharInSet(FText[FPosition], ['_', '.'])) do
      Inc(FPosition);
  if CharInSet(LChar, ['<', '>']) and (FPosition <= Length(FText)) then
    if (FText[FPosition] = '=') or ((LChar = '<') and (FText[FPosition] = '>')) then
      Inc(FPosition);
  FToken := UpperCase(Copy(FText, LStart, FPosition - LStart));
end;

procedure TConditionalExpression.Require(const AToken: string);
begin
  if FToken <> AToken then
    raise EInvalidOpException.Create('Expected ' + AToken + ' in conditional expression: ' + FText);
  Next;
end;

function TConditionalExpression.AsBoolean(const AValue: TConditionalValue): Boolean;
begin
  if not AValue.IsBoolean then
    raise EInvalidOpException.Create('Non-Boolean conditional operand: ' + FText);
  Result := AValue.Number = 1;
end;

function TConditionalExpression.Atom: TConditionalValue;
var LName: string; LFormat: TFormatSettings; LChar: Char;
begin
  Inc(FDepth);
  try
    if FDepth > 128 then
      raise EInvalidOpException.Create('Conditional expression nesting exceeds 128.');
    if FToken = '(' then
    begin
      Next;
      Result := Comparison;
      Require(')');
      Exit;
    end;
    if FToken = 'DEFINED' then
    begin
      Next;
      Require('(');
      LName := FToken;
      if LName.IsEmpty or not (LName[1].IsLetter or (LName[1] = '_')) or LName.Contains('.') then
        raise EInvalidOpException.Create('Invalid DEFINED argument: ' + FText);
      Next;
      Require(')');
      Exit(TConditionalValue.BooleanValue(FDefined(LName)));
    end;
    if FToken = 'TRUE' then begin Next; Exit(TConditionalValue.BooleanValue(True)) end;
    if FToken = 'FALSE' then begin Next; Exit(TConditionalValue.BooleanValue(False)) end;
    if FToken = 'SIZEOF' then Exit(SizeValue);
    if FToken = 'DECLARED' then
      raise ECompilerConditionRequired.Create('DECLARED requires compiler declaration resolution.');
    LName := FToken;
    if LName = 'COMPILERVERSION' then LName := FCompilerVersion;
    if (LName = 'RTLVERSION') or (LName = 'SYSTEM.RTLVERSION') then
      LName := KnownNumber(NumericName(LName));
    LFormat := TFormatSettings.Invariant;
    Result.IsBoolean := False;
    Result.IsInteger := TryStrToInt64(LName, Result.IntegerValue);
    if Result.IsInteger then
    begin
      Result.Number := Result.IntegerValue;
      Next;
      Exit;
    end;
    if (Length(LName) > 16) or not LName.Contains('.') then
      raise EInvalidOpException.Create('Unsupported conditional numeric precision: ' + FToken);
    for LChar in LName do
      if not CharInSet(LChar, ['0'..'9', '.']) then
        raise EInvalidOpException.Create('Unsupported conditional operand: ' + FToken);
    if not TryStrToFloat(LName, Result.Number, LFormat) then
      raise EInvalidOpException.Create('Unsupported conditional operand: ' + FToken);
    Next;
  finally
    Dec(FDepth);
  end;
end;

function TConditionalExpression.Unary: TConditionalValue;
var LOperator: string;
begin
  LOperator := FToken;
  if (LOperator <> 'NOT') and (LOperator <> '-') and (LOperator <> '+') then Exit(Atom);
  Inc(FDepth);
  try
    if FDepth > 128 then raise EInvalidOpException.Create('Conditional unary nesting exceeds 128.');
    Next;
    Result := Unary;
    if LOperator = 'NOT' then Exit(TConditionalValue.BooleanValue(not AsBoolean(Result)));
    if Result.IsBoolean then raise EInvalidOpException.Create('Numeric conditional operand expected.');
    if LOperator = '-' then
    begin
      Result.Number := -Result.Number;
      if Result.IsInteger then Result.IntegerValue := -Result.IntegerValue;
    end;
  finally
    Dec(FDepth);
  end;
end;

function TConditionalExpression.CompareValues(const ALeft, ARight: TConditionalValue): Integer;
begin
  if ALeft.IsBoolean <> ARight.IsBoolean then
    raise EInvalidOpException.Create('Incompatible conditional comparison operands.');
  Result := 0;
  if ALeft.IsInteger and ARight.IsInteger then
  begin
    if ALeft.IntegerValue < ARight.IntegerValue then Exit(-1);
    if ALeft.IntegerValue > ARight.IntegerValue then Exit(1);
    Exit;
  end;
  if (ALeft.IsInteger and (Abs(ALeft.IntegerValue) > 9007199254740991)) or
    (ARight.IsInteger and (Abs(ARight.IntegerValue) > 9007199254740991)) then
    raise EInvalidOpException.Create('Mixed conditional numeric precision is unsupported.');
  if ALeft.Number < ARight.Number then Exit(-1);
  if ALeft.Number > ARight.Number then Exit(1);
end;

function TConditionalExpression.Comparison: TConditionalValue;
var LOperator: string; LRight: TConditionalValue; LValue: Boolean; LOrder: Integer;
begin
  Result := Disjunction;
  LOperator := FToken;
  if (LOperator <> '=') and (LOperator <> '<>') and (LOperator <> '<') and
    (LOperator <> '<=') and (LOperator <> '>') and (LOperator <> '>=') then Exit;
  Next;
  LRight := Disjunction;
  LOrder := CompareValues(Result, LRight);
  LValue := False;
  if LOperator = '=' then LValue := LOrder = 0;
  if LOperator = '<>' then LValue := LOrder <> 0;
  if LOperator = '<' then LValue := LOrder < 0;
  if LOperator = '<=' then LValue := LOrder <= 0;
  if LOperator = '>' then LValue := LOrder > 0;
  if LOperator = '>=' then LValue := LOrder >= 0;
  Result := TConditionalValue.BooleanValue(LValue);
end;

function TConditionalExpression.Conjunction: TConditionalValue;
var LRight: TConditionalValue; LLeftBoolean, LRightBoolean: Boolean;
begin
  Result := Unary;
  while FToken = 'AND' do
  begin
    Next;
    LRight := Unary;
    LLeftBoolean := AsBoolean(Result);
    LRightBoolean := AsBoolean(LRight);
    Result := TConditionalValue.BooleanValue(LLeftBoolean and LRightBoolean);
  end;
end;

function TConditionalExpression.Disjunction: TConditionalValue;
var LOperator: string; LRight: TConditionalValue; LLeftBoolean, LRightBoolean: Boolean;
begin
  Result := Conjunction;
  while (FToken = 'OR') or (FToken = 'XOR') do
  begin
    LOperator := FToken;
    Next;
    LRight := Conjunction;
    LLeftBoolean := AsBoolean(Result);
    LRightBoolean := AsBoolean(LRight);
    Result := TConditionalValue.BooleanValue(LLeftBoolean or LRightBoolean);
    if LOperator = 'XOR' then Result := TConditionalValue.BooleanValue(LLeftBoolean xor LRightBoolean);
  end;
end;

function TConditionalExpression.Evaluate(const AText: string): Boolean;
begin
  FText := AText;
  FPosition := 1;
  FDepth := 0;
  Next;
  Result := AsBoolean(Comparison);
  if not FToken.IsEmpty then
    raise EInvalidOpException.Create('Unsupported conditional expression suffix: ' + FToken);
end;

end.
