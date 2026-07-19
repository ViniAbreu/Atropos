unit Atropos.Adapters.DelphiEnvironment;

interface
uses
  Atropos.Core.Ports;

type
  TDelphiEnvironmentAdapter = class(TInterfacedObject, IDelphiEnvironmentService)
  private
    function InternalGetBDSVersion(const ADprojPath: string): string;
    function GetBDSVersionFromDproj(const ADprojPath: string): string;
    function GetRootDirFromRegistry(const AVersion: string): string;
  public
    function ResolveDelphiPath(const ADprojPath: string): string;
  end;

implementation
uses
  System.Classes, System.SysUtils, System.Win.Registry, Winapi.Windows, Xml.XMLIntf, Xml.XMLDoc, Winapi.ActiveX;



function TDelphiEnvironmentAdapter.InternalGetBDSVersion(const ADprojPath: string): string;
var
  LDoc: IXMLDocument;
  LNode: IXMLNode;
  
  function FindNodeRec(ANode: IXMLNode; const ANodeName: string; out AFoundNode: IXMLNode): Boolean;
  var
    i: Integer;
  begin
    Result := False;
    if not Assigned(ANode) then Exit;

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

begin
  Result := '';
  try
    LDoc := LoadXMLDocument(ADprojPath);
    if FindNodeRec(LDoc.DocumentElement, 'ProjectVersion', LNode) then
    begin
      Result := LNode.Text;
      if Result.StartsWith('19.2') then Result := '22.0'
      else if Result.StartsWith('19.1') then Result := '21.0'
      else if Result.StartsWith('18.8') then Result := '20.0'
      else if Result.StartsWith('18.4') then Result := '19.0'
      else if Result.StartsWith('18.2') then Result := '18.0'
      else if Result.StartsWith('18.1') then Result := '17.0'
      else if Result.StartsWith('17.2') then Result := '16.0'
      else if Result.StartsWith('16.1') then Result := '15.0'
      else Result := '';
    end;
  except
    Result := '';
  end;
end;

function TDelphiEnvironmentAdapter.GetBDSVersionFromDproj(const ADprojPath: string): string;
begin
  Result := '';
  if not FileExists(ADprojPath) then Exit;

  CoInitialize(nil);
  try
    Result := InternalGetBDSVersion(ADprojPath);
  finally
    CoUninitialize;
  end;
end;

function TDelphiEnvironmentAdapter.GetRootDirFromRegistry(const AVersion: string): string;
var
  LReg: TRegistry;
  LKeys: TStringList;
  i: Integer;
  LHighestVersion: Double;
  LCurrentVersion: Double;
  LBestKey: string;
begin
  Result := '';
  LReg := TRegistry.Create;
  try
    LReg.RootKey := HKEY_LOCAL_MACHINE;
    LReg.Access := KEY_READ or KEY_WOW64_64KEY; 
    
    
    if AVersion <> '' then
    begin
      if LReg.OpenKeyReadOnly('Software\Embarcadero\BDS\' + AVersion) then
      begin
        Result := LReg.ReadString('RootDir');
        LReg.CloseKey;
        if Result <> '' then Exit;
      end;
    end;

    
    if LReg.OpenKeyReadOnly('Software\Embarcadero\BDS') then
    begin
      LKeys := TStringList.Create;
      try
        LReg.GetKeyNames(LKeys);
        LHighestVersion := 0;
        LBestKey := '';
        
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
        
        if LBestKey <> '' then
        begin
          LReg.CloseKey;
          if LReg.OpenKeyReadOnly('Software\Embarcadero\BDS\' + LBestKey) then
          begin
            Result := LReg.ReadString('RootDir');
            LReg.CloseKey;
          end;
        end;
      finally
        LKeys.Free;
      end;
    end;

    
    if Result = '' then
    begin
      if LReg.OpenKeyReadOnly('Software\WOW6432Node\Embarcadero\BDS') then
      begin
        LKeys := TStringList.Create;
        try
          LReg.GetKeyNames(LKeys);
          LHighestVersion := 0;
          LBestKey := '';
          
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
          
          if LBestKey <> '' then
          begin
            LReg.CloseKey;
            if LReg.OpenKeyReadOnly('Software\WOW6432Node\Embarcadero\BDS\' + LBestKey) then
            begin
              Result := LReg.ReadString('RootDir');
              LReg.CloseKey;
            end;
          end;
        finally
          LKeys.Free;
        end;
      end;
    end;
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
  
  if Result = '' then
    Result := GetEnvironmentVariable('BDS');
end;

end.

