unit Atropos.Adapters.ExternalUnitResolver;

interface
uses
  System.Generics.Collections,
  Atropos.Core.Ports, Atropos.Adapters.UnitDependencies;

type
  TExternalUnitResolverAdapter = class(TInterfacedObject, IExternalUnitResolver, IUnitDependencyResolver, IUnitImplicitEffectResolver, IUnitExportFactResolver)
  private
    FASTParser: IASTParser;
    FDependencies: TUnitDependencyCache;
    FSearchPaths: TArray<string>;
    FDelphiPath: string;
    FProjectBasePath: string;
    FUnitPathCache: TDictionary<string, string>;
    FWarnings: TList<string>;
    FLogger: ILogger;
    FIsCacheBuilt: Boolean;
    procedure AddWarning(const AMessage: string);
    procedure BuildCache;
    procedure ScanDirectoryForUnits(const ADirectory: string; ARecursive: Boolean);
    function ResolvePath(const ABasePath, ARelativePath: string): string;
  public
    constructor Create(const AASTParser: IASTParser; const ALogger: ILogger = nil);
    destructor Destroy; override;
    
    procedure Initialize(const ASearchPaths: TArray<string>; const ADelphiPath, AProjectBasePath: string);
    function TryGetUnitImports(const AUnitName: string; out AImports: TArray<string>): Boolean;
    function TryGetImplicitEffects(const AUnitName: string; out AEffects: TArray<TImplicitEffect>): Boolean;
    function TryGetExportFacts(const AUnitName: string; out AFacts: TArray<TExportedSymbol>): Boolean;
    function GetWarnings: TArray<string>;
    function TryResolveUnit(const AUnitName: string; out AExports: TArray<string>; out AHasInit: Boolean; out AIsNative: Boolean): Boolean;
  end;

implementation
uses System.IOUtils,
  System.SysUtils;

constructor TExternalUnitResolverAdapter.Create(const AASTParser: IASTParser;
  const ALogger: ILogger);
begin
  FASTParser := AASTParser;
  FDependencies := TUnitDependencyCache.Create;
  FLogger := ALogger;
  FUnitPathCache := TDictionary<string, string>.Create;
  FWarnings := TList<string>.Create;
  FIsCacheBuilt := False;
end;

procedure TExternalUnitResolverAdapter.Initialize(const ASearchPaths: TArray<string>; const ADelphiPath, AProjectBasePath: string);
begin
  FSearchPaths := ASearchPaths;
  FDelphiPath := ADelphiPath;
  FProjectBasePath := AProjectBasePath;
  FDependencies.Clear;
  FUnitPathCache.Clear;
  FWarnings.Clear;
  FIsCacheBuilt := False;
end;

destructor TExternalUnitResolverAdapter.Destroy;
begin
  FWarnings.Free;
  FDependencies.Free;
  FUnitPathCache.Free;
  inherited;
end;

procedure TExternalUnitResolverAdapter.AddWarning(const AMessage: string);
var
  LWarning: string;
begin
  LWarning := 'External unit resolver: ' + AMessage;
  FWarnings.Add(LWarning);
  if Assigned(FLogger) then
    FLogger.Log('WARNING: ' + LWarning);
end;

function TExternalUnitResolverAdapter.GetWarnings: TArray<string>;
begin
  Result := FWarnings.ToArray;
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
  begin
    AddWarning('directory not found: ' + ADirectory);
    Exit;
  end;

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
    on E: Exception do
      AddWarning(Format('failed to scan directory %s: %s', [ADirectory,
        E.Message]));
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
      on E: Exception do
        AddWarning(Format('failed to resolve search path %s: %s', [LPath,
          E.Message]));
    end;
  end;

  try
    if (not FDelphiPath.IsEmpty) and TDirectory.Exists(FDelphiPath) then
    begin
      LResolvedPath := TPath.Combine(FDelphiPath, 'source');
      ScanDirectoryForUnits(LResolvedPath, True);
    end;
  except
    on E: Exception do
      AddWarning('failed to scan the Delphi source directory: ' + E.Message);
  end;
  
  FIsCacheBuilt := True;
end;

function TExternalUnitResolverAdapter.TryGetExportFacts(const AUnitName: string;
  out AFacts: TArray<TExportedSymbol>): Boolean;
begin
  Result := FDependencies.TryGetExports(AUnitName, AFacts);
end;
function TExternalUnitResolverAdapter.TryGetImplicitEffects(const AUnitName: string;
  out AEffects: TArray<TImplicitEffect>): Boolean;
begin
  Result := FDependencies.TryGetEffects(AUnitName, AEffects);
end;

function TExternalUnitResolverAdapter.TryGetUnitImports(const AUnitName: string;
  out AImports: TArray<string>): Boolean;
begin
  Result := FDependencies.TryGet(AUnitName, AImports);
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
        FDependencies.Capture(AUnitName, LSyntaxTree);
        AExports := LSyntaxTree.GetExportedIdentifiers;
        AHasInit := LSyntaxTree.HasInitializationSection;
        Result := True;
      end;
    except
      on E: Exception do
        AddWarning(Format('failed to parse unit %s at %s: %s', [AUnitName,
          LFilePath, E.Message]));
    end;
  end;
end;

end.
