unit Atropos.Adapters.ProjectParser;

interface
uses
  System.Generics.Collections,
  Xml.XMLIntf,
  Atropos.Core.Ports;

type
  TDprojParserAdapter = class(TInterfacedObject, IProjectParser)
  private
    FConfiguration: string;
    FPlatform: string;
    function ExpandProperties(const AValue: string; AProperties: TDictionary<string, string>): string;
    function ConditionMatches(const ACondition: string; AProperties: TDictionary<string, string>): Boolean;
    function LoadProperties(const ARoot: IXMLNode): TDictionary<string, string>;
  public
    constructor Create(const AConfiguration: string = ''; const APlatform: string = '');
    function GetSearchPaths(const ADprojPath: string): TArray<string>;
    function GetProjectUnits(const ADprojPath: string): TArray<string>;
  private
    function InternalGetSearchPaths(const ADprojPath: string): TArray<string>;
    function InternalGetProjectUnits(const ADprojPath: string): TArray<string>;
  end;

implementation
uses System.SysUtils, System.RegularExpressions, Xml.XMLDoc,
  Winapi.ActiveX;

constructor TDprojParserAdapter.Create(const AConfiguration, APlatform: string);
begin
  inherited Create;
  FConfiguration := AConfiguration;
  FPlatform := APlatform;
end;

function TDprojParserAdapter.ExpandProperties(const AValue: string;
  AProperties: TDictionary<string, string>): string;
var
  LPair: TPair<string, string>;
  I: Integer;
begin
  Result := AValue;
  for I := 1 to 5 do
    for LPair in AProperties do
      Result := Result.Replace('$(' + LPair.Key + ')', LPair.Value,
        [rfReplaceAll, rfIgnoreCase]);
end;

function TDprojParserAdapter.ConditionMatches(const ACondition: string;
  AProperties: TDictionary<string, string>): Boolean;
var
  LCondition: string;
  LMatch: TMatch;
  LPart: string;
begin
  if ACondition.Trim.IsEmpty then
    Exit(True);
  LCondition := ExpandProperties(ACondition, AProperties).Trim;
  if LCondition.StartsWith('(') and LCondition.EndsWith(')') then
    Exit(ConditionMatches(LCondition.Substring(1, LCondition.Length - 2), AProperties));
  if TRegEx.IsMatch(LCondition, '\s+or\s+', [roIgnoreCase]) then
  begin
    Result := False;
    for LPart in TRegEx.Split(LCondition, '\s+or\s+', [roIgnoreCase]) do
      if ConditionMatches(LPart, AProperties) then
        Exit(True);
    Exit;
  end;
  if TRegEx.IsMatch(LCondition, '\s+and\s+', [roIgnoreCase]) then
  begin
    Result := True;
    for LPart in TRegEx.Split(LCondition, '\s+and\s+', [roIgnoreCase]) do
      if not ConditionMatches(LPart, AProperties) then
        Exit(False);
    Exit;
  end;
  LMatch := TRegEx.Match(LCondition,
    '^\s*''([^'']*)''\s*(==|!=)\s*''([^'']*)''\s*$', [roIgnoreCase]);
  if not LMatch.Success then
    Exit(False);
  Result := SameText(LMatch.Groups[1].Value, LMatch.Groups[3].Value);
  if LMatch.Groups[2].Value = '!=' then
    Result := not Result;
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
      LValue := ExpandProperties(LProperty.Text, Result);
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

  CoInitialize(nil);
  try
    Result := InternalGetProjectUnits(ADprojPath);
  finally
    CoUninitialize;
  end;
end;

end.

