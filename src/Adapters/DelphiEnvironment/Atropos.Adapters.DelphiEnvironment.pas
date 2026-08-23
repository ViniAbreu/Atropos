unit Atropos.Adapters.DelphiEnvironment;

interface
uses
  Atropos.Core.Ports,
  Xml.XMLIntf,
  System.Win.Registry;

type
  TDelphiEnvironmentAdapter = class(TInterfacedObject, IDelphiEnvironmentService)
  private
    function FindNodeRec(ANode: IXMLNode; const ANodeName: string; out AFoundNode: IXMLNode): Boolean;
    function TryReadRootDir(AReg: TRegistry; const AKeyPath: string; out ARootDir: string): Boolean;
    function GetHighestVersionFromNode(AReg: TRegistry; const ANodePath: string; out ARootDir: string): Boolean;
    function InternalGetBDSVersion(const ADprojPath: string): string;
    function GetBDSVersionFromDproj(const ADprojPath: string): string;
    function GetRootDirFromRegistry(const AVersion: string): string;
  public
    function ResolveDelphiPath(const ADprojPath: string): string;
  end;

implementation
uses System.Classes, System.SysUtils, Xml.XMLDoc, Winapi.ActiveX,
  Winapi.Windows;

function TDelphiEnvironmentAdapter.FindNodeRec(ANode: IXMLNode; const ANodeName: string; out AFoundNode: IXMLNode): Boolean;
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

function TDelphiEnvironmentAdapter.InternalGetBDSVersion(const ADprojPath: string): string;
var
  LDoc: IXMLDocument;
  LNode: IXMLNode;
begin
  Result := EmptyStr;
  try
    LDoc := LoadXMLDocument(ADprojPath);
    if FindNodeRec(LDoc.DocumentElement, 'ProjectVersion', LNode) then
    begin
      Result := LNode.Text;
      if Result.StartsWith('19.2') then
        Exit('22.0');
      if Result.StartsWith('19.1') then
        Exit('21.0');
      if Result.StartsWith('18.8') then
        Exit('20.0');
      if Result.StartsWith('18.4') then
        Exit('19.0');
      if Result.StartsWith('18.2') then
        Exit('18.0');
      if Result.StartsWith('18.1') then
        Exit('17.0');
      if Result.StartsWith('17.2') then
        Exit('16.0');
      if Result.StartsWith('16.1') then
        Exit('15.0');
      Exit(EmptyStr);
    end;
  except
    Result := EmptyStr;
  end;
end;

function TDelphiEnvironmentAdapter.GetBDSVersionFromDproj(const ADprojPath: string): string;
begin
  Result := EmptyStr;
  if not FileExists(ADprojPath) then
    Exit;

  CoInitialize(nil);
  try
    Result := InternalGetBDSVersion(ADprojPath);
  finally
    CoUninitialize;
  end;
end;

function TDelphiEnvironmentAdapter.TryReadRootDir(AReg: TRegistry; const AKeyPath: string; out ARootDir: string): Boolean;
begin
  Result := False;
  if AReg.OpenKeyReadOnly(AKeyPath) then
  begin
    ARootDir := AReg.ReadString('RootDir');
    AReg.CloseKey;
    Result := not ARootDir.IsEmpty;
  end;
end;

function TDelphiEnvironmentAdapter.GetHighestVersionFromNode(AReg: TRegistry; const ANodePath: string; out ARootDir: string): Boolean;
var
  LKeys: TStringList;
  i: Integer;
  LHighestVersion: Double;
  LCurrentVersion: Double;
  LBestKey: string;
begin
  Result := False;
  if not AReg.OpenKeyReadOnly(ANodePath) then
    Exit;

  LKeys := TStringList.Create;
  try
    AReg.GetKeyNames(LKeys);
    LHighestVersion := 0;
    LBestKey := EmptyStr;
    
    for i := 0 to LKeys.Count - 1 do
    begin
      if TryStrToFloat(LKeys[i], LCurrentVersion, TFormatSettings.Invariant) then
      begin
        if LCurrentVersion > LHighestVersion then
        begin
          LHighestVersion := LCurrentVersion;
          LBestKey := LKeys[i];
        end;
      end;
    end;
    
    if not LBestKey.IsEmpty then
    begin
      AReg.CloseKey;
      Result := TryReadRootDir(AReg, ANodePath + '\' + LBestKey, ARootDir);
    end;
  finally
    LKeys.Free;
  end;
end;

function TDelphiEnvironmentAdapter.GetRootDirFromRegistry(const AVersion: string): string;
var
  LReg: TRegistry;
begin
  Result := EmptyStr;
  LReg := TRegistry.Create;
  try
    LReg.RootKey := HKEY_LOCAL_MACHINE;
    LReg.Access := KEY_READ or KEY_WOW64_64KEY; 
    
    if not AVersion.IsEmpty and TryReadRootDir(LReg, 'Software\Embarcadero\BDS\' + AVersion, Result) then
      Exit;

    if GetHighestVersionFromNode(LReg, 'Software\Embarcadero\BDS', Result) then
      Exit;

    if GetHighestVersionFromNode(LReg, 'Software\WOW6432Node\Embarcadero\BDS', Result) then
      Exit;
  finally
    LReg.Free;
  end;
end;

function TDelphiEnvironmentAdapter.ResolveDelphiPath(const ADprojPath: string): string;
var
  LVersion: string;
begin
  LVersion := GetBDSVersionFromDproj(ADprojPath);
  Result := GetRootDirFromRegistry(LVersion);
  
  if Result.IsEmpty then
    Result := GetEnvironmentVariable('BDS');
end;

end.

