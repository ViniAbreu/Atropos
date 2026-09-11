unit Atropos.Adapters.CompilerInputs;

interface

uses System.Generics.Collections, Atropos.Core.Ports, Atropos.Core.Compilation,
  Atropos.Adapters.SourceSnapshot, Atropos.Adapters.SourceIncludes,
  Atropos.Adapters.DelphiSource, Atropos.Adapters.CompilerDependencies,
  Atropos.Adapters.CompilerSourceInputs;

type
  TCompilerInputs = class
  private
    FSnapshot: TSourceSnapshot;
    FIncludes: TSourceIncludeResolver;
    FRootPath: string;
    FSearchPaths: TArray<string>;
    FSourceInputs: TCompilerSourceInputs;
    FGenerated: TDictionary<string, Boolean>;
    FCancel: TCancellationCheck;
    procedure CaptureFile(const APath: string);
    procedure CaptureCandidates(const ADependency: string);
    function IsGenerated(const APath, AOutputPath: string): Boolean;
    procedure CaptureGenerated(const AEntry: TCompilerDependency);
  public
    constructor Create(const ARootPath: string; const AContext: TProjectCompilationContext;
      const ADelphiPath: string; const ACancel: TCancellationCheck = nil);
    destructor Destroy; override;
    function ReadRoot: TDelphiSourceContent;
    function ReadInclude(const AParent, AName: string; out AContent, APath: string): Boolean;
    procedure CaptureDependencies(const APaths: TArray<TCompilerDependency>; const AOutputPath: string);
    procedure ValidateDependencies(const APaths: TArray<TCompilerDependency>; const AOutputPath: string);
    procedure Validate;
    function Dependencies: TArray<TSourceDependency>;
    function MissingPaths: TArray<string>;
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils, System.Hash;

constructor TCompilerInputs.Create(const ARootPath: string;
  const AContext: TProjectCompilationContext; const ADelphiPath: string;
  const ACancel: TCancellationCheck);
var LFile: TSourceDependency; LTool, LCompiler: string;
begin
  inherited Create;
  FCancel := ACancel;
  FRootPath := TPath.GetFullPath(ARootPath);
  FSearchPaths := [TPath.GetDirectoryName(FRootPath), TPath.GetDirectoryName(AContext.ProjectPath)] +
    AContext.SearchPaths;
  FSnapshot := TSourceSnapshot.Create;
  FSnapshot.BeginAnalysis;
  FIncludes := TSourceIncludeResolver.Create(FRootPath, AContext.IncludePaths, FSnapshot);
  FSourceInputs := TCompilerSourceInputs.Create(FSnapshot, FIncludes, AContext, ACancel);
  FGenerated := TDictionary<string, Boolean>.Create;
  for LFile in AContext.ProjectFiles do FSnapshot.RecordSource(LFile.FilePath, LFile.ContentHash);
  LCompiler := 'dcc32.exe';
  if SameText(AContext.Target.Platform, 'Win64') then LCompiler := 'dcc64.exe';
  for LTool in ['bin\' + LCompiler, 'bin64\' + LCompiler,
    'bin\Borland.Build.Tasks.Delphi.dll', 'bin\Borland.Build.Tasks.Shared.dll'] do
    CaptureFile(TPath.Combine(ADelphiPath, LTool));
end;

destructor TCompilerInputs.Destroy;
begin
  FGenerated.Free;
  FSourceInputs.Free;
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

function TCompilerInputs.IsGenerated(const APath, AOutputPath: string): Boolean;
begin
  Result := TPath.GetFullPath(APath).StartsWith(IncludeTrailingPathDelimiter(TPath.GetFullPath(AOutputPath)), True);
end;

procedure TCompilerInputs.CaptureGenerated(const AEntry: TCompilerDependency);
var LSource: string;
begin
  if SameText(TPath.GetFileName(AEntry.FilePath), TPath.GetFileNameWithoutExtension(FRootPath) + '.dcu') then Exit;
  LSource := TPath.ChangeExtension(AEntry.ReportedPath, '.pas');
  if not TFile.Exists(LSource) then
    raise EInvalidOperation.Create('Compiler dependency has no identifiable source: ' + AEntry.ReportedPath);
  FSourceInputs.Capture(LSource);
  CaptureCandidates(AEntry.ReportedPath);
  FGenerated.AddOrSetValue(AEntry.ReportedPath.ToLowerInvariant, True);
end;

procedure TCompilerInputs.CaptureDependencies(const APaths: TArray<TCompilerDependency>; const AOutputPath: string);
var LEntry: TCompilerDependency;
begin
  for LEntry in APaths do
  begin
    if Assigned(FCancel) then
      if FCancel() then raise EAbort.Create('Compiler dependency capture cancelled.');
    if IsGenerated(LEntry.FilePath, AOutputPath) then
    begin
      CaptureGenerated(LEntry);
      Continue;
    end;
    CaptureFile(LEntry.FilePath);
    CaptureCandidates(LEntry.FilePath);
  end;
end;

procedure TCompilerInputs.ValidateDependencies(const APaths: TArray<TCompilerDependency>; const AOutputPath: string);
var LEntry: TCompilerDependency;
begin
  for LEntry in APaths do
  begin
    if IsGenerated(LEntry.FilePath, AOutputPath) then
    begin
      if SameText(TPath.GetFileName(LEntry.FilePath), TPath.GetFileNameWithoutExtension(FRootPath) + '.dcu') then Continue;
      if not FGenerated.ContainsKey(LEntry.ReportedPath.ToLowerInvariant) then
        raise EInvalidOperation.Create('Compiler regenerated an uncaptured source: ' + LEntry.ReportedPath);
      Continue;
    end;
    if not FSnapshot.ContainsSource(LEntry.FilePath) then
      raise EInvalidOperation.Create('Compiler used an uncaptured dependency: ' + LEntry.FilePath);
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
