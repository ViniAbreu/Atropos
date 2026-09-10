unit Atropos.Adapters.TargetResolver;

interface

uses System.Generics.Collections, Atropos.Core.Ports, Atropos.Core.Compilation, Atropos.Adapters.UnitDependencies;

type
  TCompleteProviderParser = class(TInterfacedObject, IASTParser)
  private
    FParser: IASTParser;
  public
    constructor Create(const AParser: IASTParser);
    function ParseFile(const AFilePath: string): IUnitSyntaxTree;
  end;

  TTargetUnitResolver = class(TInterfacedObject, IExternalUnitResolver, IUnitDependencyResolver)
  private
    FParser: IASTParser;
    FExternal: IExternalUnitResolver;
    FDependencies: TUnitDependencyCache;
    FContext: TProjectCompilationContext;
    FWarnings: TList<string>;
    function AliasFor(const AName: string): string;
    function ResolveName(const AName: string; out AExports: TArray<string>;
      out AHasInit, AIsNative: Boolean): Boolean;
  public
    constructor Create(const AParser: IASTParser;
      const AContext: TProjectCompilationContext; const ADelphiPath: string);
    destructor Destroy; override;
    procedure Initialize(const ASearchPaths: TArray<string>;
      const ADelphiPath, ABasePath: string);
    function TryGetUnitImports(const AUnitName: string; out AImports: TArray<string>): Boolean;
    function GetWarnings: TArray<string>;
    function TryResolveUnit(const AUnitName: string; out AExports: TArray<string>;
      out AHasInit, AIsNative: Boolean): Boolean;
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils,
  Atropos.Adapters.ExternalUnitResolver;

constructor TCompleteProviderParser.Create(const AParser: IASTParser);
begin
  inherited Create;
  FParser := AParser;
end;

function TCompleteProviderParser.ParseFile(const AFilePath: string): IUnitSyntaxTree;
var
  LDiagnostics: IUnitAnalysisDiagnostics;
  LReasons: TArray<string>;
begin
  Result := FParser.ParseFile(AFilePath);
  if not Supports(Result, IUnitAnalysisDiagnostics, LDiagnostics) then
    Exit;
  LReasons := LDiagnostics.GetIncompleteAnalysisReasons;
  if Length(LReasons) > 0 then
    raise EInvalidOperation.Create('Incomplete provider analysis: ' + string.Join('; ', LReasons));
end;

constructor TTargetUnitResolver.Create(const AParser: IASTParser;
  const AContext: TProjectCompilationContext; const ADelphiPath: string);
begin
  inherited Create;
  FWarnings := TList<string>.Create;
  FDependencies := TUnitDependencyCache.Create;
  FContext := AContext;
  FParser := TCompleteProviderParser.Create(AParser);
  FExternal := TExternalUnitResolverAdapter.Create(FParser);
  Initialize(AContext.SearchPaths, ADelphiPath, TPath.GetDirectoryName(AContext.ProjectPath));
end;

destructor TTargetUnitResolver.Destroy;
begin
  FDependencies.Free;
  FWarnings.Free;
  inherited;
end;

procedure TTargetUnitResolver.Initialize(const ASearchPaths: TArray<string>;
  const ADelphiPath, ABasePath: string);
begin
  FExternal.Initialize([ABasePath] + ASearchPaths, ADelphiPath, ABasePath);
  FDependencies.Clear;
  FWarnings.Clear;
end;

function TTargetUnitResolver.GetWarnings: TArray<string>;
begin
  Result := FWarnings.ToArray + FExternal.GetWarnings;
end;

function TTargetUnitResolver.AliasFor(const AName: string): string;
var
  LAlias: string;
  LParts: TArray<string>;
begin
  Result := AName;
  for LAlias in FContext.Aliases do
  begin
    LParts := LAlias.Split(['=']);
    if Length(LParts) <> 2 then
      raise EInvalidOperation.Create('Invalid unit alias: ' + LAlias);
    if SameText(LParts[0].Trim, AName) then
      Exit(LParts[1].Trim);
  end;
end;

function TTargetUnitResolver.ResolveName(const AName: string;
  out AExports: TArray<string>; out AHasInit, AIsNative: Boolean): Boolean;
var
  LPath: string;
  LTree: IUnitSyntaxTree;
  LWarningCount: Integer;
  LMapping: TUnitSourceMapping;
  LDependencies: IUnitDependencyResolver;
  LImports: TArray<string>;
begin
  for LMapping in FContext.SourceMappings do
  begin
    if not SameText(LMapping.UnitName, AName) then
      Continue;
    LTree := FParser.ParseFile(LMapping.FilePath);
    if not SameText(LTree.GetUnitName, AName) then
      raise EInvalidOperation.Create('Mapped source declares a different unit: ' + LMapping.FilePath);
    FDependencies.Capture(AName, LTree);
    AExports := LTree.GetExportedIdentifiers;
    AHasInit := LTree.HasInitializationSection;
    AIsNative := False;
    Exit(True);
  end;
  for LPath in FContext.UnitPaths do
  begin
    if not SameText(TPath.GetFileNameWithoutExtension(LPath), AName) then
      Continue;
    LTree := FParser.ParseFile(LPath);
    FDependencies.Capture(AName, LTree);
    AExports := LTree.GetExportedIdentifiers;
    AHasInit := LTree.HasInitializationSection;
    AIsNative := False;
    Exit(True);
  end;
  LWarningCount := Length(FExternal.GetWarnings);
  Result := FExternal.TryResolveUnit(AName, AExports, AHasInit, AIsNative);
  if Result and Supports(FExternal, IUnitDependencyResolver, LDependencies) then
    if LDependencies.TryGetUnitImports(AName, LImports) then
      FDependencies.RegisterImports(AName, LImports);
  if not Result and (Length(FExternal.GetWarnings) > LWarningCount) then
    raise EInvalidOperation.Create('Source lookup is incomplete for ' + AName);
end;

function TTargetUnitResolver.TryGetUnitImports(const AUnitName: string;
  out AImports: TArray<string>): Boolean;
begin
  Result := FDependencies.TryGet(AUnitName, AImports);
end;
function TTargetUnitResolver.TryResolveUnit(const AUnitName: string;
  out AExports: TArray<string>; out AHasInit, AIsNative: Boolean): Boolean;
var
  LName, LPrefix: string;
begin
  Result := False;
  AExports := [];
  AHasInit := False;
  AIsNative := False;
  try
    LName := AliasFor(AUnitName);
    if ResolveName(LName, AExports, AHasInit, AIsNative) then
    begin
      FDependencies.CopyName(LName, AUnitName);
      Exit(True);
    end;
    if LName.Contains('.') then
      Exit;
    for LPrefix in FContext.Namespaces do
      if ResolveName(LPrefix + '.' + LName, AExports, AHasInit, AIsNative) then
      begin
        FDependencies.CopyName(LPrefix + '.' + LName, AUnitName);
        Exit(True);
      end;
  except
    on E: Exception do
      FWarnings.Add(AUnitName + ': unknown provider: ' + E.Message);
  end;
end;

end.
