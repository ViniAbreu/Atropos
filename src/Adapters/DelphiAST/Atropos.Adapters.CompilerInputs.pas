unit Atropos.Adapters.CompilerInputs;

interface

uses Atropos.Core.Ports, Atropos.Core.Compilation,
  Atropos.Adapters.SourceSnapshot, Atropos.Adapters.SourceIncludes,
  Atropos.Adapters.DelphiSource;

type
  TCompilerInputs = class
  private
    FSnapshot: TSourceSnapshot;
    FIncludes: TSourceIncludeResolver;
    FRootPath: string;
    FSearchPaths: TArray<string>;
    procedure CaptureFile(const APath: string);
    procedure CaptureCandidates(const ADependency: string);
    function GeneratedRoot(const APath, AOutputPath: string): Boolean;
  public
    constructor Create(const ARootPath: string; const AContext: TProjectCompilationContext;
      const ADelphiPath: string);
    destructor Destroy; override;
    function ReadRoot: TDelphiSourceContent;
    function ReadInclude(const AParent, AName: string; out AContent, APath: string): Boolean;
    procedure CaptureDependencies(const APaths: TArray<string>; const AOutputPath: string);
    procedure ValidateDependencies(const APaths: TArray<string>; const AOutputPath: string);
    procedure Validate;
    function Dependencies: TArray<TSourceDependency>;
    function MissingPaths: TArray<string>;
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils, System.Hash;

constructor TCompilerInputs.Create(const ARootPath: string;
  const AContext: TProjectCompilationContext; const ADelphiPath: string);
var LFile: TSourceDependency; LTool, LCompiler: string;
begin
  inherited Create;
  FRootPath := TPath.GetFullPath(ARootPath);
  FSearchPaths := [TPath.GetDirectoryName(FRootPath), TPath.GetDirectoryName(AContext.ProjectPath)] +
    AContext.SearchPaths;
  FSnapshot := TSourceSnapshot.Create;
  FSnapshot.BeginAnalysis;
  FIncludes := TSourceIncludeResolver.Create(FRootPath, AContext.IncludePaths, FSnapshot);
  for LFile in AContext.ProjectFiles do FSnapshot.RecordSource(LFile.FilePath, LFile.ContentHash);
  LCompiler := 'dcc32.exe';
  if SameText(AContext.Target.Platform, 'Win64') then LCompiler := 'dcc64.exe';
  for LTool in ['bin\' + LCompiler, 'bin64\' + LCompiler,
    'bin\Borland.Build.Tasks.Delphi.dll', 'bin\Borland.Build.Tasks.Shared.dll'] do
    CaptureFile(TPath.Combine(ADelphiPath, LTool));
end;

destructor TCompilerInputs.Destroy;
begin
  FIncludes.Free;
  FSnapshot.Free;
  inherited;
end;

procedure TCompilerInputs.CaptureFile(const APath: string);
begin
  if FSnapshot.ContainsSource(APath) then Exit;
  if not TFile.Exists(APath) then
  begin
    FSnapshot.RecordMissingSource(APath);
    Exit;
  end;
  FSnapshot.RecordSource(APath, THashSHA2.GetHashStringFromFile(APath));
end;

function TCompilerInputs.ReadRoot: TDelphiSourceContent;
begin
  Result := TDelphiSourceReader.ReadRaw(FRootPath);
  FSnapshot.RecordSource(FRootPath, Result.ContentHash);
end;

function TCompilerInputs.ReadInclude(const AParent, AName: string;
  out AContent, APath: string): Boolean;
begin
  Result := FIncludes.GetRawIncludeFileContent(AParent, AName, AContent, APath);
end;

procedure TCompilerInputs.CaptureCandidates(const ADependency: string);
var LDirectory, LName, LStem, LShort: string; LDirectories: TArray<string>;
begin
  LStem := TPath.GetFileNameWithoutExtension(ADependency);
  LShort := Copy(LStem, LastDelimiter('.', LStem) + 1, MaxInt);
  LDirectories := FSearchPaths + [TPath.GetDirectoryName(ADependency)];
  for LDirectory in LDirectories do
    for LName in [LStem + '.dcu', LStem + '.pas', LShort + '.dcu', LShort + '.pas'] do
      CaptureFile(TPath.Combine(LDirectory, LName));
end;

function TCompilerInputs.GeneratedRoot(const APath, AOutputPath: string): Boolean;
begin
  Result := TPath.GetFullPath(APath).StartsWith(IncludeTrailingPathDelimiter(TPath.GetFullPath(AOutputPath)), True);
  if not Result then Exit;
  if not SameText(TPath.GetFileName(APath), TPath.GetFileNameWithoutExtension(FRootPath) + '.dcu') then
    raise EInvalidOperation.Create('Compiler regenerated a dependency without a source snapshot: ' + APath);
end;

procedure TCompilerInputs.CaptureDependencies(const APaths: TArray<string>; const AOutputPath: string);
var LPath: string;
begin
  for LPath in APaths do
  begin
    if GeneratedRoot(LPath, AOutputPath) then Continue;
    CaptureFile(LPath);
    CaptureCandidates(LPath);
  end;
end;

procedure TCompilerInputs.ValidateDependencies(const APaths: TArray<string>; const AOutputPath: string);
var LPath: string;
begin
  for LPath in APaths do
  begin
    if GeneratedRoot(LPath, AOutputPath) then Continue;
    if not FSnapshot.ContainsSource(LPath) then
      raise EInvalidOperation.Create('Compiler used an uncaptured dependency: ' + LPath);
  end;
  Validate;
end;

procedure TCompilerInputs.Validate;
begin
  FSnapshot.ValidateAnalysis;
end;

function TCompilerInputs.Dependencies: TArray<TSourceDependency>;
begin
  Result := FSnapshot.Dependencies;
end;

function TCompilerInputs.MissingPaths: TArray<string>;
begin
  Result := FSnapshot.MissingPaths;
end;

end.
