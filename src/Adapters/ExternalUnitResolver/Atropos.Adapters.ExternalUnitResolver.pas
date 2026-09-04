unit Atropos.Adapters.ExternalUnitResolver;

interface
uses
  System.Generics.Collections,
  Atropos.Core.Ports;

type
  TExternalUnitResolverAdapter = class(TInterfacedObject, IExternalUnitResolver)
  private
    FASTParser: IASTParser;
    FSearchPaths: TArray<string>;
    FDelphiPath: string;
    FProjectBasePath: string;
    FUnitPathCache: TDictionary<string, string>;
    FIsCacheBuilt: Boolean;
    
    procedure BuildCache;
    procedure ScanDirectoryForUnits(const ADirectory: string; ARecursive: Boolean);
    function ResolvePath(const ABasePath, ARelativePath: string): string;
  public
    constructor Create(const AASTParser: IASTParser);
    destructor Destroy; override;
    
    procedure Initialize(const ASearchPaths: TArray<string>; const ADelphiPath, AProjectBasePath: string);
    function TryResolveUnit(const AUnitName: string; out AExports: TArray<string>; out AHasInit: Boolean; out AIsNative: Boolean): Boolean;
  end;

implementation
uses System.IOUtils,
  System.SysUtils;

constructor TExternalUnitResolverAdapter.Create(const AASTParser: IASTParser);
begin
  FASTParser := AASTParser;
  FUnitPathCache := TDictionary<string, string>.Create;
  FIsCacheBuilt := False;
end;

procedure TExternalUnitResolverAdapter.Initialize(const ASearchPaths: TArray<string>; const ADelphiPath, AProjectBasePath: string);
begin
  FSearchPaths := ASearchPaths;
  FDelphiPath := ADelphiPath;
  FProjectBasePath := AProjectBasePath;
  FUnitPathCache.Clear;
  FIsCacheBuilt := False;
end;

destructor TExternalUnitResolverAdapter.Destroy;
begin
  FUnitPathCache.Free;
  inherited;
end;

function TExternalUnitResolverAdapter.ResolvePath(const ABasePath, ARelativePath: string): string;
var
  LPath: string;
begin
  LPath := ARelativePath.Replace('$(BDS)', FDelphiPath, [rfReplaceAll, rfIgnoreCase]);
  LPath := LPath.Replace('$(PROJECTDIR)', FProjectBasePath, [rfReplaceAll, rfIgnoreCase]);
  
  Result := LPath;
  if TPath.IsRelativePath(LPath) then
    Result := TPath.GetFullPath(TPath.Combine(ABasePath, LPath));
end;

procedure TExternalUnitResolverAdapter.ScanDirectoryForUnits(const ADirectory: string; ARecursive: Boolean);
var
  LFile: string;
  LFileName: string;
  LSearchOption: TSearchOption;
begin
  if not TDirectory.Exists(ADirectory) then
    Exit;

  LSearchOption := TSearchOption.soTopDirectoryOnly;
  if ARecursive then
    LSearchOption := TSearchOption.soAllDirectories;

  try
    for LFile in TDirectory.GetFiles(ADirectory, '*.pas', LSearchOption) do
    begin
      LFileName := TPath.GetFileNameWithoutExtension(LFile).ToLower;
      if not FUnitPathCache.ContainsKey(LFileName) then
        FUnitPathCache.Add(LFileName, LFile);
    end;
  except
    
  end;
end;

procedure TExternalUnitResolverAdapter.BuildCache;
var
  LPath: string;
  LResolvedPath: string;
begin
  if FIsCacheBuilt then
    Exit;
  
  for LPath in FSearchPaths do
  begin
    try
      LResolvedPath := ResolvePath(FProjectBasePath, LPath);
      ScanDirectoryForUnits(LResolvedPath, False);
    except
      
    end;
  end;

  try
    if (not FDelphiPath.IsEmpty) and TDirectory.Exists(FDelphiPath) then
    begin
      LResolvedPath := TPath.Combine(FDelphiPath, 'source');
      ScanDirectoryForUnits(LResolvedPath, True);
    end;
  except
    
  end;
  
  FIsCacheBuilt := True;
end;

function TExternalUnitResolverAdapter.TryResolveUnit(const AUnitName: string; out AExports: TArray<string>; out AHasInit: Boolean; out AIsNative: Boolean): Boolean;
var
  LLowerName: string;
  LFilePath: string;
  LSyntaxTree: IUnitSyntaxTree;
begin
  Result := False;
  AExports := [];
  AHasInit := False;
  AIsNative := False;
  
  BuildCache;
  
  LLowerName := AUnitName.ToLower;
  if FUnitPathCache.TryGetValue(LLowerName, LFilePath) then
  begin
    if (not FDelphiPath.IsEmpty) and LFilePath.ToLower.StartsWith(FDelphiPath.ToLower) then
      AIsNative := True;
      
    try
      LSyntaxTree := FASTParser.ParseFile(LFilePath);
      if Assigned(LSyntaxTree) then
      begin
        AExports := LSyntaxTree.GetExportedIdentifiers;
        AHasInit := LSyntaxTree.HasInitializationSection;
        Result := True;
      end;
    except
      on E: Exception do
        Writeln('WARNING: Failed to parse external unit ', AUnitName, ' at ', LFilePath, ' - Error: ', E.Message);
    end;
  end;
end;

end.
