unit Atropos.Adapters.NativeSourcePreparer;

interface

uses System.Generics.Collections, Atropos.Core.Ports, Atropos.Core.Compilation, Atropos.Adapters.BuildService,
  Atropos.Adapters.CompilerPreparation, Atropos.Adapters.CompilerBranchTrace;

type
  TNativeSourcePreparer = class(TInterfacedObject, ICompilerSourcePreparer)
  private
    FContext: TProjectCompilationContext;
    FDelphiPath: string;
    FRunner: IBuildProcessRunner;
    FCancel: TCancellationCheck;
    FCache: TDictionary<string, TCompilerPreparedSource>;
    class function CopyPrepared(const ASource: TCompilerPreparedSource): TCompilerPreparedSource; static;
    class function CacheValid(const ASource: TCompilerPreparedSource): Boolean; static;
    function WriteSources(ATrace: TCompilerBranchTrace; const AFilePath, ADirectory: string): string;
    function PrepareIn(const AFilePath, AExpectedHash, ADirectory: string): TCompilerPreparedSource;
  public
    constructor Create(const AContext: TProjectCompilationContext; const ADelphiPath: string;
      const ARunner: IBuildProcessRunner = nil; const ACancel: TCancellationCheck = nil);
    destructor Destroy; override;
    function Prepare(const AFilePath, AExpectedHash: string): TCompilerPreparedSource;
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils,
  Atropos.Adapters.DelphiSource, Atropos.Adapters.CompilerInputs,
  Atropos.Adapters.CompilerTraceProcess, Atropos.Adapters.SourceSnapshot;

constructor TNativeSourcePreparer.Create(const AContext: TProjectCompilationContext;
  const ADelphiPath: string; const ARunner: IBuildProcessRunner; const ACancel: TCancellationCheck);
begin
  inherited Create;
  FCache := TDictionary<string, TCompilerPreparedSource>.Create;
  FContext := AContext;
  FContext.ProjectFiles := Copy(AContext.ProjectFiles);
  FContext.SearchPaths := Copy(AContext.SearchPaths);
  FContext.IncludePaths := Copy(AContext.IncludePaths);
  FDelphiPath := ADelphiPath;
  FRunner := ARunner;
  FCancel := ACancel;
end;

destructor TNativeSourcePreparer.Destroy;
begin
  FCache.Free;
  inherited;
end;

class function TNativeSourcePreparer.CopyPrepared(const ASource: TCompilerPreparedSource): TCompilerPreparedSource;
begin
  Result := ASource;
  Result.Includes := Copy(ASource.Includes);
  Result.Dependencies := Copy(ASource.Dependencies);
  Result.MissingPaths := Copy(ASource.MissingPaths);
end;

class function TNativeSourcePreparer.CacheValid(const ASource: TCompilerPreparedSource): Boolean;
var LSnapshot: TSourceSnapshot; LDependency: TSourceDependency; LPath: string;
begin
  LSnapshot := TSourceSnapshot.Create;
  try
    LSnapshot.BeginAnalysis;
    for LDependency in ASource.Dependencies do
      LSnapshot.RecordSource(LDependency.FilePath, LDependency.ContentHash);
    for LPath in ASource.MissingPaths do LSnapshot.RecordMissingSource(LPath);
    try
      LSnapshot.ValidateAnalysis;
      Result := True;
    except
      on E: EInvalidOperation do Result := False;
    end;
  finally
    LSnapshot.Free;
  end;
end;

function TNativeSourcePreparer.WriteSources(ATrace: TCompilerBranchTrace;
  const AFilePath, ADirectory: string): string;
var LInclude: TCompilerTraceInclude; LSourcePath, LHostName: string;
begin
  LSourcePath := TPath.Combine(ADirectory, TPath.GetFileName(AFilePath));
  TFile.WriteAllText(LSourcePath, ATrace.Instrument, TEncoding.UTF8);
  for LInclude in ATrace.InstrumentedIncludes do
    TFile.WriteAllText(TPath.Combine(ADirectory, LInclude.Name), LInclude.Content, TEncoding.UTF8);
  LHostName := 'AtroposTraceHost' + TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '').Replace('-', '');
  Result := TPath.Combine(ADirectory, LHostName + '.dpr');
  TFile.WriteAllText(Result, 'program ' + LHostName + '; uses ' +
    TPath.GetFileNameWithoutExtension(AFilePath) + ' in ' + QuotedStr(LSourcePath) + '; begin end.', TEncoding.UTF8);
end;

function TNativeSourcePreparer.PrepareIn(const AFilePath, AExpectedHash,
  ADirectory: string): TCompilerPreparedSource;
var LInputs: TCompilerInputs; LTrace: TCompilerBranchTrace; LCompiler: TCompilerTraceProcess;
  LSource: TDelphiSourceContent; LProgram, LDiscovery, LValidation, LOutput: string;
  LDependencies: TArray<string>; LIndex: Integer;
begin
  LInputs := TCompilerInputs.Create(AFilePath, FContext, FDelphiPath);
  try
    LSource := LInputs.ReadRoot;
    if not SameText(LSource.ContentHash, AExpectedHash) then
      raise EInvalidOperation.Create('Source changed before compiler preparation: ' + AFilePath);
    LTrace := TCompilerBranchTrace.Create(LSource.Text, AFilePath,
      function(const AParent, AName: string; out AContent, APath: string): Boolean
      begin Result := LInputs.ReadInclude(AParent, AName, AContent, APath) end);
    try
      LProgram := WriteSources(LTrace, AFilePath, ADirectory);
      LDiscovery := TPath.Combine(ADirectory, 'discovery');
      LValidation := TPath.Combine(ADirectory, 'validation');
      TDirectory.CreateDirectory(LDiscovery);
      TDirectory.CreateDirectory(LValidation);
      LCompiler := TCompilerTraceProcess.Create(FRunner, FCancel);
      try
        LDependencies := LCompiler.DiscoverDependencies(FContext, FDelphiPath, LProgram, LDiscovery);
        LInputs.CaptureDependencies(LDependencies, LDiscovery);
        LInputs.Validate;
        LOutput := LCompiler.CompileProgram(FContext, FDelphiPath, LProgram, LValidation, LDependencies);
        LInputs.ValidateDependencies(LDependencies, LValidation);
        Result.Text := TDelphiSourceReader.Normalize(LTrace.Replay(LOutput));
        Result.SourceHash := LSource.ContentHash;
        Result.Includes := LTrace.PreparedIncludes;
        for LIndex := 0 to High(Result.Includes) do
          Result.Includes[LIndex].Content := TDelphiSourceReader.Normalize(Result.Includes[LIndex].Content);
        Result.Dependencies := LInputs.Dependencies;
        Result.MissingPaths := LInputs.MissingPaths;
      finally
        LCompiler.Free;
      end;
    finally
      LTrace.Free;
    end;
  finally
    LInputs.Free;
  end;
end;

function TNativeSourcePreparer.Prepare(const AFilePath, AExpectedHash: string): TCompilerPreparedSource;
var LDirectory, LKey: string; LCached: TCompilerPreparedSource;
begin
  if not SameText(TPath.GetExtension(AFilePath), '.pas') then
    raise EInvalidOperation.Create('Compiler source preparation requires a Pascal unit.');
  if Assigned(FCancel) then
    if FCancel() then raise EAbort.Create('Compiler preparation cancelled.');
  LKey := TPath.GetFullPath(AFilePath).ToLowerInvariant + #0 + AExpectedHash.ToLowerInvariant;
  if FCache.TryGetValue(LKey, LCached) then
  begin
    if CacheValid(LCached) then Exit(CopyPrepared(LCached));
    FCache.Remove(LKey);
  end;
  LDirectory := TPath.Combine(TPath.GetTempPath, 'Atropos-Prepared-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(LDirectory);
  try
    Result := PrepareIn(AFilePath, AExpectedHash, LDirectory);
  finally
    TDirectory.Delete(LDirectory, True);
  end;
  FCache.AddOrSetValue(LKey, CopyPrepared(Result));
end;

end.
