unit Atropos.Adapters.DelphiEnvironment;

interface
uses
  Atropos.Core.Ports,
  Xml.XMLIntf,
  System.Win.Registry;

type
  TDelphiVersionMap = class
  public
    class function FromProjectVersion(const AProjectVersion: string): string; static;
  end;

  TDelphiEnvironmentAdapter = class(TInterfacedObject, IDelphiEnvironmentService)
  private
    function FindNodeRec(ANode: IXMLNode; const ANodeName: string; out AFoundNode: IXMLNode): Boolean;
    function TryReadRootDir(AReg: TRegistry; const AKeyPath: string; out ARootDir: string): Boolean;
    function GetHighestVersionFromNode(AReg: TRegistry; const ANodePath: string; out ARootDir: string): Boolean;
    function InternalGetProjectVersion(const ADprojPath: string): string;
    function GetProjectVersionFromDproj(const ADprojPath: string): string;
  protected
    function GetRootDirFromRegistry(const AVersion: string): string; virtual;
    function GetConfiguredBDSPath: string; virtual;
  public
    function ResolveDelphiPath(const ADprojPath: string): string;
  end;

implementation
uses System.Classes, System.SysUtils, Xml.XMLDoc, Winapi.ActiveX,
  Winapi.Windows;

class function TDelphiVersionMap.FromProjectVersion(const AProjectVersion: string): string;
begin
  if AProjectVersion.StartsWith('20.') then
    Exit('23.0');
  if AProjectVersion.StartsWith('19.2') then
    Exit('22.0');
  if AProjectVersion.StartsWith('19.1') then
    Exit('21.0');
  if AProjectVersion.StartsWith('18.8') then
    Exit('20.0');
  if AProjectVersion.StartsWith('18.4') then
    Exit('19.0');
  if AProjectVersion.StartsWith('18.2') then
    Exit('18.0');
  if AProjectVersion.StartsWith('18.1') then
    Exit('17.0');
  if AProjectVersion.StartsWith('17.2') then
    Exit('16.0');
  if AProjectVersion.StartsWith('16.1') then
    Exit('15.0');
  Result := EmptyStr;
end;

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

function TDelphiEnvironmentAdapter.InternalGetProjectVersion(
  const ADprojPath: string): string;
var
  LDoc: IXMLDocument;
  LNode: IXMLNode;
begin
  Result := EmptyStr;
  try
    LDoc := LoadXMLDocument(ADprojPath);
    if FindNodeRec(LDoc.DocumentElement, 'ProjectVersion', LNode) then
      Result := LNode.Text.Trim;
  except
    Result := EmptyStr;
  end;
end;

function TDelphiEnvironmentAdapter.GetProjectVersionFromDproj(
  const ADprojPath: string): string;
begin
  Result := EmptyStr;
  if not FileExists(ADprojPath) then
    Exit;

  CoInitialize(nil);
  try
    Result := InternalGetProjectVersion(ADprojPath);
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
    
    if not AVersion.IsEmpty then
    begin
      if TryReadRootDir(LReg, 'Software\Embarcadero\BDS\' + AVersion,
        Result) then
        Exit;
      TryReadRootDir(LReg, 'Software\WOW6432Node\Embarcadero\BDS\' +
        AVersion, Result);
      Exit;
    end;

    if GetHighestVersionFromNode(LReg, 'Software\Embarcadero\BDS', Result) then
      Exit;

    if GetHighestVersionFromNode(LReg, 'Software\WOW6432Node\Embarcadero\BDS', Result) then
      Exit;
  finally
    LReg.Free;
  end;
end;

function TDelphiEnvironmentAdapter.GetConfiguredBDSPath: string;
begin
  Result := GetEnvironmentVariable('BDS');
end;

function TDelphiEnvironmentAdapter.ResolveDelphiPath(const ADprojPath: string): string;
var
  LBDSVersion: string;
  LProjectVersion: string;
begin
  LProjectVersion := GetProjectVersionFromDproj(ADprojPath);
  LBDSVersion := TDelphiVersionMap.FromProjectVersion(LProjectVersion);
  Result := GetRootDirFromRegistry(LBDSVersion);
  
  if Result.IsEmpty then
    Result := GetConfiguredBDSPath;
end;

end.

