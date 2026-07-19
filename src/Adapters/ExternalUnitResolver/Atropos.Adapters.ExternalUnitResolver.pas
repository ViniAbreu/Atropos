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
    procedure ScanDirectoryForUnits(const ADirectory: string);
    function ResolvePath(const ABasePath, ARelativePath: string): string;
  public
    constructor Create(const AASTParser: IASTParser);
    destructor Destroy; override;
    
    procedure Initialize(const ASearchPaths: TArray<string>; const ADelphiPath, AProjectBasePath: string);
    function TryResolveUnit(const AUnitName: string; out AExports: TArray<string>): Boolean;
  end;

implementation
uses
  System.SysUtils, System.Types, System.IOUtils;



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
  LPath := ARelativePath;
  LPath := StringReplace(LPath, '$(BDS)', FDelphiPath, [rfReplaceAll, rfIgnoreCase]);
  
  if TPath.IsRelativePath(LPath) then
    Result := TPath.GetFullPath(TPath.Combine(ABasePath, LPath))
  else
    Result := LPath;
end;

procedure TExternalUnitResolverAdapter.ScanDirectoryForUnits(const ADirectory: string);
var
  LFiles: TStringDynArray;
  LFile: string;
  LFileName: string;
begin
  if not TDirectory.Exists(ADirectory) then
    Exit;
    
  try
    LFiles := TDirectory.GetFiles(ADirectory, '*.pas', TSearchOption.soAllDirectories);
    for LFile in LFiles do
    begin
      LFileName := LowerCase(TPath.GetFileNameWithoutExtension(LFile));
      if not FUnitPathCache.ContainsKey(LFileName) then
        FUnitPathCache.Add(LFileName, LFile);
    end;
  except
    
  end;
end;

procedure TExternalUnitResolverAdapter.BuildCache;
var
  LPath, LResolvedPath: string;
begin
  if FIsCacheBuilt then Exit;
  
  
  for LPath in FSearchPaths do
  begin
    try
      LResolvedPath := ResolvePath(FProjectBasePath, LPath);
      ScanDirectoryForUnits(LResolvedPath);
    except
      
    end;
  end;
  
  
  try
    if (FDelphiPath <> '') and TDirectory.Exists(FDelphiPath) then
    begin
      LResolvedPath := TPath.Combine(FDelphiPath, 'source');
      ScanDirectoryForUnits(LResolvedPath);
    end;
  except
    
  end;
  
  FIsCacheBuilt := True;
end;

function TExternalUnitResolverAdapter.TryResolveUnit(const AUnitName: string; out AExports: TArray<string>): Boolean;
var
  LLowerName: string;
  LFilePath: string;
  LSyntaxTree: IUnitSyntaxTree;
begin
  Result := False;
  AExports := [];
  
  BuildCache;
  
  LLowerName := LowerCase(AUnitName);
  if FUnitPathCache.TryGetValue(LLowerName, LFilePath) then
  begin
    try
      LSyntaxTree := FASTParser.ParseFile(LFilePath);
      if Assigned(LSyntaxTree) then
      begin
        AExports := LSyntaxTree.GetExportedIdentifiers;
        Result := True;
      end;
    except
      on E: Exception do
        Writeln('WARNING: Failed to parse external unit ', AUnitName, ' at ', LFilePath, ' - Error: ', E.Message);
    end;
  end;
end;

end.


