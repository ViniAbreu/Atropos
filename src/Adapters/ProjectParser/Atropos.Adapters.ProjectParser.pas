unit Atropos.Adapters.ProjectParser;

interface
uses
  System.Generics.Collections,
  Xml.XMLIntf,
  Atropos.Core.Ports;

type
  TDprojParserAdapter = class(TInterfacedObject, IProjectParser)
  private
    function FindNodeRec(ANode: IXMLNode; const ANodeName: string; out AFoundNode: IXMLNode): Boolean;
    procedure FindAllNodesRec(ANode: IXMLNode; const ANodeName: string; AList: TList<IXMLNode>);
  public
    function GetSearchPaths(const ADprojPath: string): TArray<string>;
    function GetProjectUnits(const ADprojPath: string): TArray<string>;
  private
    function InternalGetSearchPaths(const ADprojPath: string): TArray<string>;
    function InternalGetProjectUnits(const ADprojPath: string): TArray<string>;
  end;

implementation
uses System.SysUtils, Xml.XMLDoc,
  Winapi.ActiveX;

function TDprojParserAdapter.FindNodeRec(ANode: IXMLNode; const ANodeName: string; out AFoundNode: IXMLNode): Boolean;
var
  i: Integer;
begin
  Result := False;
  if not Assigned(ANode) then
    Exit;

  if SameText(ANode.LocalName, ANodeName) or SameText(ANode.NodeName, ANodeName) then
  begin
    AFoundNode := ANode;
    Exit(True);
  end;

  if ANode.HasChildNodes then
  begin
    for i := 0 to ANode.ChildNodes.Count - 1 do
    begin
      if FindNodeRec(ANode.ChildNodes[i], ANodeName, AFoundNode) then
        Exit(True);
    end;
  end;
end;

procedure TDprojParserAdapter.FindAllNodesRec(ANode: IXMLNode; const ANodeName: string; AList: TList<IXMLNode>);
var
  i: Integer;
begin
  if not Assigned(ANode) then
    Exit;

  if SameText(ANode.LocalName, ANodeName) or SameText(ANode.NodeName, ANodeName) then
    AList.Add(ANode);

  if ANode.HasChildNodes then
  begin
    for i := 0 to ANode.ChildNodes.Count - 1 do
      FindAllNodesRec(ANode.ChildNodes[i], ANodeName, AList);
  end;
end;

function TDprojParserAdapter.InternalGetSearchPaths(const ADprojPath: string): TArray<string>;
var
  LDoc: IXMLDocument;
  LPaths: TList<string>;
  LNode: IXMLNode;
  LPart: string;
begin
  Result := [];
  LPaths := TList<string>.Create;
  try
    LDoc := LoadXMLDocument(ADprojPath);
    if FindNodeRec(LDoc.DocumentElement, 'DCC_UnitSearchPath', LNode) then
    begin
      for LPart in LNode.Text.Split([';']) do
      begin
        if (not LPart.Trim.IsEmpty) and (not LPart.Contains('$(DCC_UnitSearchPath)')) then
          LPaths.Add(LPart.Trim);
      end;
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
  LNodes: TList<IXMLNode>;
  LNode: IXMLNode;
  LInclude: string;
begin
  Result := [];
  LUnits := TList<string>.Create;
  LNodes := TList<IXMLNode>.Create;
  try
    LDoc := LoadXMLDocument(ADprojPath);
    FindAllNodesRec(LDoc.DocumentElement, 'DCCReference', LNodes);
    for LNode in LNodes do
    begin
      if LNode.HasAttribute('Include') then
      begin
        LInclude := LNode.Attributes['Include'];
        if SameText(ExtractFileExt(LInclude), '.pas') then
          LUnits.Add(LInclude);
      end;
    end;
    Result := LUnits.ToArray;
  finally
    LNodes.Free;
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

