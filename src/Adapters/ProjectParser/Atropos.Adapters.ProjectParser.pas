unit Atropos.Adapters.ProjectParser;

interface
uses
  System.Generics.Collections,
  Xml.XMLIntf,
  Atropos.Core.Ports;

type
  TConditionEvaluation = (ceFalse, ceTrue, ceUnsupported);

  TDprojParserAdapter = class(TInterfacedObject, IProjectParser)
  private
    FConfiguration: string;
    FPlatform: string;
    FProjectDirectory: string;
    FWarnings: TList<string>;
    procedure AddWarning(const AMessage: string);
    function HasKnownPropertyReference(const AValue: string;
      AProperties: TDictionary<string, string>;
      const AIgnoredProperty: string = ''): Boolean;
    function HasWrappingParentheses(const ACondition: string): Boolean;
    function TrySplitLogicalCondition(const ACondition, AOperator: string;
      out AParts: TArray<string>): Boolean;
    function EvaluateCondition(const ACondition: string;
      AProperties: TDictionary<string, string>): TConditionEvaluation;
    function EvaluateExists(const ACondition: string;
      out AEvaluation: TConditionEvaluation): Boolean;
    function ExpandProperties(const AValue: string;
      AProperties: TDictionary<string, string>;
      const AIgnoredProperty: string = ''): string;
    function ExpandPropertyValue(const APropertyName, AValue: string;
      AProperties: TDictionary<string, string>): string;
    function ConditionMatches(const ACondition: string; AProperties: TDictionary<string, string>): Boolean;
    function LoadProperties(const ARoot: IXMLNode): TDictionary<string, string>;
  public
    constructor Create(const AConfiguration: string = ''; const APlatform: string = '');
    destructor Destroy; override;
    function TakeWarnings: TArray<string>;
    function GetSearchPaths(const ADprojPath: string): TArray<string>;
    function GetProjectUnits(const ADprojPath: string): TArray<string>;
  private
    function InternalGetSearchPaths(const ADprojPath: string): TArray<string>;
    function InternalGetProjectUnits(const ADprojPath: string): TArray<string>;
  end;

implementation
uses System.IOUtils, System.SysUtils, System.StrUtils,
  System.RegularExpressions, Xml.XMLDoc, Winapi.ActiveX;

constructor TDprojParserAdapter.Create(const AConfiguration, APlatform: string);
begin
  inherited Create;
  FConfiguration := AConfiguration;
  FPlatform := APlatform;
  FWarnings := TList<string>.Create;
end;

destructor TDprojParserAdapter.Destroy;
begin
  FWarnings.Free;
  inherited;
end;

procedure TDprojParserAdapter.AddWarning(const AMessage: string);
var
  LWarning: string;
begin
  LWarning := 'Project parser: ' + AMessage;
  if FWarnings.Contains(LWarning) then
    Exit;
  FWarnings.Add(LWarning);
end;

function TDprojParserAdapter.TakeWarnings: TArray<string>;
begin
  Result := FWarnings.ToArray;
  FWarnings.Clear;
end;

function TDprojParserAdapter.HasKnownPropertyReference(const AValue: string;
  AProperties: TDictionary<string, string>;
  const AIgnoredProperty: string): Boolean;
var
  LPair: TPair<string, string>;
begin
  Result := False;
  for LPair in AProperties do
  begin
    if SameText(LPair.Key, AIgnoredProperty) then
      Continue;
    if ContainsText(AValue, '$(' + LPair.Key + ')') then
      Exit(True);
  end;
end;

function TDprojParserAdapter.HasWrappingParentheses(
  const ACondition: string): Boolean;
var
  LIndex: Integer;
  LDepth: Integer;
  LInsideQuote: Boolean;
begin
  Result := ACondition.StartsWith('(') and ACondition.EndsWith(')');
  if not Result then
    Exit;
  LDepth := 0;
  LInsideQuote := False;
  for LIndex := 1 to Length(ACondition) do
  begin
    if ACondition[LIndex] = '''' then
    begin
      LInsideQuote := not LInsideQuote;
      Continue;
    end;
    if LInsideQuote then
      Continue;
    if ACondition[LIndex] = '(' then
      Inc(LDepth);
    if ACondition[LIndex] = ')' then
      Dec(LDepth);
    if (LDepth = 0) and (LIndex < Length(ACondition)) then
      Exit(False);
  end;
  Result := LDepth = 0;
end;

function TDprojParserAdapter.TrySplitLogicalCondition(const ACondition,
  AOperator: string; out AParts: TArray<string>): Boolean;
var
  LCharacter: Char;
  LDepth: Integer;
  LIndex: Integer;
  LInsideQuote: Boolean;
  LParts: TList<string>;
  LStartIndex: Integer;
begin
  AParts := [];
  LParts := TList<string>.Create;
  try
    LDepth := 0;
    LInsideQuote := False;
    LStartIndex := 1;
    for LIndex := 1 to Length(ACondition) - Length(AOperator) + 1 do
    begin
      LCharacter := ACondition[LIndex];
      if LCharacter = '''' then
      begin
        LInsideQuote := not LInsideQuote;
        Continue;
      end;
      if LInsideQuote then
        Continue;
      if LCharacter = '(' then
        Inc(LDepth);
      if LCharacter = ')' then
        Dec(LDepth);
      if LDepth <> 0 then
        Continue;
      if not SameText(Copy(ACondition, LIndex, Length(AOperator)),
        AOperator) then
        Continue;
      if (LIndex = 1) or not CharInSet(ACondition[LIndex - 1],
        [#9, #10, #13, ' ']) then
        Continue;
      if (LIndex + Length(AOperator) > Length(ACondition)) or
        not CharInSet(ACondition[LIndex + Length(AOperator)],
        [#9, #10, #13, ' ']) then
        Continue;
      LParts.Add(Copy(ACondition, LStartIndex, LIndex - LStartIndex));
      LStartIndex := LIndex + Length(AOperator);
    end;
    Result := LParts.Count > 0;
    if not Result then
      Exit;
    LParts.Add(Copy(ACondition, LStartIndex, MaxInt));
    AParts := LParts.ToArray;
  finally
    LParts.Free;
  end;
end;

function TDprojParserAdapter.ExpandProperties(const AValue: string;
  AProperties: TDictionary<string, string>;
  const AIgnoredProperty: string): string;
var
  LPair: TPair<string, string>;
  LPrevious: string;
  LPass: Integer;
begin
  Result := AValue;
  for LPass := 0 to AProperties.Count do
  begin
    LPrevious := Result;
    for LPair in AProperties do
    begin
      if SameText(LPair.Key, AIgnoredProperty) then
        Continue;
      Result := Result.Replace('$(' + LPair.Key + ')', LPair.Value,
        [rfReplaceAll, rfIgnoreCase]);
    end;
    if Result = LPrevious then
      Break;
  end;
  if HasKnownPropertyReference(Result, AProperties, AIgnoredProperty) then
    AddWarning('cyclic property expansion detected in: ' + AValue);
end;

function TDprojParserAdapter.ExpandPropertyValue(const APropertyName,
  AValue: string; AProperties: TDictionary<string, string>): string;
var
  LPreviousValue: string;
begin
  Result := AValue;
  if AProperties.TryGetValue(APropertyName, LPreviousValue) then
    Result := Result.Replace('$(' + APropertyName + ')', LPreviousValue,
      [rfReplaceAll, rfIgnoreCase]);
  Result := ExpandProperties(Result, AProperties, APropertyName);
end;

function TDprojParserAdapter.EvaluateExists(const ACondition: string;
  out AEvaluation: TConditionEvaluation): Boolean;
var
  LMatch: TMatch;
  LPath: string;
  LExists: Boolean;
  LNegated: Boolean;
begin
  LMatch := TRegEx.Match(ACondition,
    '^\s*(!?)Exists\(\s*''([^'']*)''\s*\)\s*$', [roIgnoreCase]);
  Result := LMatch.Success;
  if not Result then
    Exit;
  LNegated := LMatch.Groups[1].Value = '!';
  LPath := LMatch.Groups[2].Value;
  if TPath.IsRelativePath(LPath) then
    LPath := TPath.Combine(FProjectDirectory, LPath);
  LExists := TFile.Exists(LPath) or TDirectory.Exists(LPath);
  if LNegated then
    LExists := not LExists;
  AEvaluation := ceFalse;
  if LExists then
    AEvaluation := ceTrue;
end;

function TDprojParserAdapter.EvaluateCondition(const ACondition: string;
  AProperties: TDictionary<string, string>): TConditionEvaluation;
var
  LCondition: string;
  LMatch: TMatch;
  LPart: string;
  LParts: TArray<string>;
  LEvaluation: TConditionEvaluation;
begin
  if ACondition.Trim.IsEmpty then
    Exit(ceTrue);
  LCondition := ExpandProperties(ACondition, AProperties).Trim;
  if HasWrappingParentheses(LCondition) then
    Exit(EvaluateCondition(LCondition.Substring(1, LCondition.Length - 2),
      AProperties));
  if TrySplitLogicalCondition(LCondition, 'or', LParts) then
  begin
    Result := ceFalse;
    for LPart in LParts do
    begin
      LEvaluation := EvaluateCondition(LPart, AProperties);
      if LEvaluation = ceTrue then
        Exit(ceTrue);
      if LEvaluation = ceUnsupported then
        Result := ceUnsupported;
    end;
    Exit;
  end;
  if TrySplitLogicalCondition(LCondition, 'and', LParts) then
  begin
    Result := ceTrue;
    for LPart in LParts do
    begin
      LEvaluation := EvaluateCondition(LPart, AProperties);
      if LEvaluation = ceFalse then
        Exit(ceFalse);
      if LEvaluation = ceUnsupported then
        Result := ceUnsupported;
    end;
    Exit;
  end;
  if EvaluateExists(LCondition, Result) then
    Exit;
  LMatch := TRegEx.Match(LCondition,
    '^\s*''([^'']*)''\s*(==|!=)\s*''([^'']*)''\s*$', [roIgnoreCase]);
  if not LMatch.Success then
    Exit(ceUnsupported);
  Result := ceFalse;
  if SameText(LMatch.Groups[1].Value, LMatch.Groups[3].Value) then
    Result := ceTrue;
  if LMatch.Groups[2].Value = '!=' then
  begin
    if Result = ceTrue then
      Exit(ceFalse);
    Result := ceTrue;
  end;
end;

function TDprojParserAdapter.ConditionMatches(const ACondition: string;
  AProperties: TDictionary<string, string>): Boolean;
var
  LEvaluation: TConditionEvaluation;
begin
  LEvaluation := EvaluateCondition(ACondition, AProperties);
  Result := LEvaluation = ceTrue;
  if LEvaluation = ceUnsupported then
    AddWarning('unsupported MSBuild condition ignored: ' + ACondition.Trim);
end;

function TDprojParserAdapter.LoadProperties(const ARoot: IXMLNode): TDictionary<string, string>;
var
  I, J: Integer;
  LGroup, LProperty: IXMLNode;
  LCondition: string;
  LValue: string;
begin
  Result := TDictionary<string, string>.Create;
  if not FConfiguration.IsEmpty then
    Result.AddOrSetValue('Config', FConfiguration);
  if not FPlatform.IsEmpty then
    Result.AddOrSetValue('Platform', FPlatform);

  for I := 0 to ARoot.ChildNodes.Count - 1 do
  begin
    LGroup := ARoot.ChildNodes[I];
    if not SameText(LGroup.LocalName, 'PropertyGroup') then
      Continue;
    LCondition := '';
    if LGroup.HasAttribute('Condition') then
      LCondition := LGroup.Attributes['Condition'];
    if not ConditionMatches(LCondition, Result) then
      Continue;
    for J := 0 to LGroup.ChildNodes.Count - 1 do
    begin
      LProperty := LGroup.ChildNodes[J];
      LCondition := '';
      if LProperty.HasAttribute('Condition') then
        LCondition := LProperty.Attributes['Condition'];
      if not ConditionMatches(LCondition, Result) then
        Continue;
      LValue := ExpandPropertyValue(LProperty.LocalName, LProperty.Text,
        Result);
      Result.AddOrSetValue(LProperty.LocalName, LValue);
    end;
  end;
end;

function TDprojParserAdapter.InternalGetSearchPaths(const ADprojPath: string): TArray<string>;
var
  LDoc: IXMLDocument;
  LPaths: TList<string>;
  LProperties: TDictionary<string, string>;
  LPathValue: string;
  LPart: string;
begin
  Result := [];
  LPaths := TList<string>.Create;
  try
    LDoc := LoadXMLDocument(ADprojPath);
    LProperties := LoadProperties(LDoc.DocumentElement);
    try
      if LProperties.TryGetValue('DCC_UnitSearchPath', LPathValue) then
        for LPart in LPathValue.Split([';']) do
          if (not LPart.Trim.IsEmpty) and
            not LPart.Contains('$(DCC_UnitSearchPath)') then
            LPaths.Add(LPart.Trim);
    finally
      LProperties.Free;
    end;
    Result := LPaths.ToArray;
  finally
    LPaths.Free;
  end;
end;

function TDprojParserAdapter.GetSearchPaths(const ADprojPath: string): TArray<string>;
begin
  Result := [];
  if not FileExists(ADprojPath) then
    Exit;

  FProjectDirectory := TPath.GetDirectoryName(TPath.GetFullPath(ADprojPath));

  CoInitialize(nil);
  try
    Result := InternalGetSearchPaths(ADprojPath);
  finally
    CoUninitialize;
  end;
end;

function TDprojParserAdapter.InternalGetProjectUnits(const ADprojPath: string): TArray<string>;
var
  LDoc: IXMLDocument;
  LUnits: TList<string>;
  LProperties: TDictionary<string, string>;
  LGroup, LNode: IXMLNode;
  LInclude: string;
  LCondition: string;
  I, J: Integer;
begin
  Result := [];
  LUnits := TList<string>.Create;
  try
    LDoc := LoadXMLDocument(ADprojPath);
    LProperties := LoadProperties(LDoc.DocumentElement);
    try
      for I := 0 to LDoc.DocumentElement.ChildNodes.Count - 1 do
      begin
        LGroup := LDoc.DocumentElement.ChildNodes[I];
        if not SameText(LGroup.LocalName, 'ItemGroup') then
          Continue;
        LCondition := '';
        if LGroup.HasAttribute('Condition') then
          LCondition := LGroup.Attributes['Condition'];
        if not ConditionMatches(LCondition, LProperties) then
          Continue;
        for J := 0 to LGroup.ChildNodes.Count - 1 do
        begin
          LNode := LGroup.ChildNodes[J];
          if not SameText(LNode.LocalName, 'DCCReference') or
            not LNode.HasAttribute('Include') then
            Continue;
          LCondition := '';
          if LNode.HasAttribute('Condition') then
            LCondition := LNode.Attributes['Condition'];
          if not ConditionMatches(LCondition, LProperties) then
            Continue;
          LInclude := ExpandProperties(LNode.Attributes['Include'], LProperties);
          if SameText(ExtractFileExt(LInclude), '.pas') then
            LUnits.Add(LInclude);
        end;
      end;
    finally
      LProperties.Free;
    end;
    Result := LUnits.ToArray;
  finally
    LUnits.Free;
  end;
end;

function TDprojParserAdapter.GetProjectUnits(const ADprojPath: string): TArray<string>;
begin
  Result := [];
  if not FileExists(ADprojPath) then
    Exit;

  FProjectDirectory := TPath.GetDirectoryName(TPath.GetFullPath(ADprojPath));

  CoInitialize(nil);
  try
    Result := InternalGetProjectUnits(ADprojPath);
  finally
    CoUninitialize;
  end;
end;

end.

