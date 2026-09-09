unit Atropos.Adapters.DelphiEnvironment;

interface
uses
  Atropos.Core.Ports, Xml.XMLIntf, System.Win.Registry, Winapi.Windows;

type
  TDelphiVersionMap = class
  public
    // ProjectVersion is a file-format hint, not a product or compiler version.
    class function FromProjectVersion(const AProjectVersion: string): string; static;
    class function IsAmbiguous(const AProjectVersion: string): Boolean; static;
  end;

  TDelphiInstallation = record
    Version: string;
    RootDir: string;
  end;

  TDelphiEnvironmentAdapter = class(TInterfacedObject, IDelphiEnvironmentService)
  private
    function FindNodeRec(ANode: IXMLNode; const ANodeName: string; out AFoundNode: IXMLNode): Boolean;
    function InternalGetProjectVersion(const ADprojPath: string): string;
    function GetProjectVersionFromDproj(const ADprojPath: string): string;
    function ReadInstallationRoot(ARegistry: TRegistry): string;
  protected
    function GetRegistryBaseKey: string; virtual;
    function GetRegisteredInstallations: TArray<TDelphiInstallation>; virtual;
    function GetConfiguredBDSPath: string; virtual;
  public
    class function UsableRoot(const APath: string): string; static;
    function ResolveDelphiPath(const ADprojPath: string): string;
  end;

implementation
uses System.Classes, System.SysUtils, System.IOUtils,
  System.Generics.Collections, Xml.XMLDoc, Winapi.ActiveX;

class function TDelphiVersionMap.FromProjectVersion(const AProjectVersion: string): string;
begin
  Result := EmptyStr;
  if AProjectVersion = '20.4' then Exit('37.0');
  if (AProjectVersion = '20.1') or (AProjectVersion = '20.2') or
    (AProjectVersion = '20.3') then Exit('23.0');
  if (AProjectVersion = '19.3') or (AProjectVersion = '19.4') or
    (AProjectVersion = '19.5') then Exit('22.0');
  if (AProjectVersion = '19.0') or (AProjectVersion = '19.1') or
    (AProjectVersion = '19.2') then Exit('21.0');
  if (AProjectVersion = '18.5') or (AProjectVersion = '18.6') or
    (AProjectVersion = '18.7') or (AProjectVersion = '18.8') then Exit('20.0');
  if (AProjectVersion = '18.3') or (AProjectVersion = '18.4') then Exit('19.0');
  if AProjectVersion = '18.2' then Exit('18.0');
  if (AProjectVersion = '18.0') or (AProjectVersion = '18.1') then Exit('17.0');
  if (AProjectVersion = '17.1') or (AProjectVersion = '17.2') then Exit('16.0');
  if (AProjectVersion = '16.0') or (AProjectVersion = '16.1') then Exit('15.0');
end;

class function TDelphiVersionMap.IsAmbiguous(const AProjectVersion: string): Boolean;
begin
  Result := (AProjectVersion = '20.3') or (AProjectVersion = '18.1') or
    (AProjectVersion = '18.2');
end;

class function TDelphiEnvironmentAdapter.UsableRoot(const APath: string): string;
var LRoot: string;
begin
  Result := EmptyStr;
  LRoot := APath.Trim.Trim(['"']);
  if LRoot.IsEmpty then Exit;
  try
    LRoot := ExcludeTrailingPathDelimiter(TPath.GetFullPath(LRoot));
    if TFile.Exists(TPath.Combine(LRoot,'bin\bds.exe')) or
      TFile.Exists(TPath.Combine(LRoot,'bin64\bds.exe')) or
      (TFile.Exists(TPath.Combine(LRoot,'bin\rsvars.bat')) and
       TFile.Exists(TPath.Combine(LRoot,'bin\dcc32.exe')) and
       TFile.Exists(TPath.Combine(LRoot,'bin\CodeGear.Delphi.Targets'))) then
      Result := LRoot;
  except
    // Malformed/stale environment and registry values must not stop discovery.
    Result := EmptyStr;
  end;
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

function TDelphiEnvironmentAdapter.ReadInstallationRoot(ARegistry: TRegistry): string;
var LName, LExecutable, LBin: string;
begin
  Result := EmptyStr;
  // App / App x64 also allow discovery when RootDir is absent or stale.
  for LName in ['RootDir','App','App x64'] do
  begin
    try
      if not ARegistry.ValueExists(LName) then Continue;
      LExecutable := ARegistry.ReadString(LName).Trim.Trim(['"']);
      if LName = 'RootDir' then Result := UsableRoot(LExecutable);
      if (LName <> 'RootDir') and TFile.Exists(LExecutable) and
        SameText(ExtractFileName(LExecutable),'bds.exe') then
      begin
        LBin := ExtractFileDir(LExecutable);
        if SameText(ExtractFileName(LBin),'bin') or
          SameText(ExtractFileName(LBin),'bin64') then
          Result := UsableRoot(ExtractFileDir(LBin));
      end;
      if not Result.IsEmpty then Exit;
    except
      // Ignore individual invalid registry value types, and try the next value.
      Result := EmptyStr;
    end;
  end;
end;

function TDelphiEnvironmentAdapter.GetRegisteredInstallations: TArray<TDelphiInstallation>;
var
  LRegistry: TRegistry;
  LKeys: TStringList;
  LInstallations: TList<TDelphiInstallation>;
  LInstallation: TDelphiInstallation;
  LHive: HKEY;
  LView: Cardinal;
  LKey, LNode: string;
  LVersion: Double;
begin
  LNode := GetRegistryBaseKey;
  LInstallations := TList<TDelphiInstallation>.Create;
  LKeys := TStringList.Create;
  try
    // Keep HKCU first only for equal versions. Search both views explicitly,
    // independent of whether Atropos itself is a Win32 or Win64 executable.
    for LHive in [HKEY_CURRENT_USER,HKEY_LOCAL_MACHINE] do
      for LView in [KEY_WOW64_64KEY,KEY_WOW64_32KEY] do
      begin
        LRegistry := TRegistry.Create(KEY_READ or LView);
        try
          LRegistry.RootKey := LHive;
          if not LRegistry.OpenKeyReadOnly(LNode) then Continue;
          LKeys.Clear;
          LRegistry.GetKeyNames(LKeys);
          LRegistry.CloseKey;
          for LKey in LKeys do
          begin
            // E.g. 37.0_x64 and alternate IDE profiles are not installations.
            if not TryStrToFloat(LKey,LVersion,TFormatSettings.Invariant) or
              (LVersion <= 0) then Continue;
            if not LRegistry.OpenKeyReadOnly(LNode+'\'+LKey) then Continue;
            try
              LInstallation.Version := LKey;
              LInstallation.RootDir := ReadInstallationRoot(LRegistry);
              if not LInstallation.RootDir.IsEmpty then LInstallations.Add(LInstallation);
            finally LRegistry.CloseKey; end;
          end;
        finally LRegistry.Free; end;
      end;
    Result := LInstallations.ToArray;
  finally LKeys.Free; LInstallations.Free; end;
end;

function TDelphiEnvironmentAdapter.GetRegistryBaseKey: string;
begin
  Result := 'Software\Embarcadero\BDS';
end;

function TDelphiEnvironmentAdapter.GetConfiguredBDSPath: string;
begin
  Result := GetEnvironmentVariable('BDS');
end;

function TDelphiEnvironmentAdapter.ResolveDelphiPath(const ADprojPath: string): string;
var
  LProjectVersion, LPreferredVersion, LRoot, LExactRoot: string;
  LMinimum, LVersion, LHighest: Double;
  LInstallation: TDelphiInstallation;
begin
  // An explicitly chosen, existing installation takes precedence over a file-
  // format heuristic. Do not change global environment variables or the registry.
  Result := UsableRoot(GetConfiguredBDSPath);
  if not Result.IsEmpty then Exit;
  LProjectVersion := GetProjectVersionFromDproj(ADprojPath);
  LPreferredVersion := TDelphiVersionMap.FromProjectVersion(LProjectVersion);
  LMinimum := 0;
  TryStrToFloat(LPreferredVersion,LMinimum,TFormatSettings.Invariant);
  LHighest := 0;
  LExactRoot := EmptyStr;
  for LInstallation in GetRegisteredInstallations do
  begin
    LRoot := UsableRoot(LInstallation.RootDir);
    if LRoot.IsEmpty or
      not TryStrToFloat(LInstallation.Version,LVersion,TFormatSettings.Invariant) or
      (LVersion < LMinimum) then Continue;
    if (LVersion = LMinimum) and LExactRoot.IsEmpty then LExactRoot := LRoot;
    if LVersion > LHighest then
    begin
      LHighest := LVersion;
      Result := LRoot;
    end;
  end;
  if not LExactRoot.IsEmpty and not TDelphiVersionMap.IsAmbiguous(LProjectVersion) then
    Result := LExactRoot;
end;

end.
