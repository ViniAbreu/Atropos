unit Atropos.Adapters.CompilerTraceProcess;

interface

uses Atropos.Core.Ports, Atropos.Core.Compilation, Atropos.Adapters.BuildService,
  Atropos.Adapters.CompilerDependencies;

type
  TCompilerTraceProcess = class
  private
    FRunner: IBuildProcessRunner;
    FCancel: TCancellationCheck;
    class function Request(const AContext: TProjectCompilationContext;
      const ASourcePath, AOutputPath: string; AProgram: Boolean): string; static;
    function Execute(const AContext: TProjectCompilationContext;
      const ADelphiPath, ASourcePath, AOutputPath: string; AProgram: Boolean): string;
  public
    constructor Create(const ARunner: IBuildProcessRunner;
      const ACancel: TCancellationCheck);
    // Caller owns a fresh output directory and instrumented source files.
    function Compile(const AContext: TProjectCompilationContext;
      const ADelphiPath, ASourcePath, AOutputPath: string): string;
    function DiscoverDependencies(const AContext: TProjectCompilationContext;
      const ADelphiPath, AProgramPath, AOutputPath: string): TArray<string>;
    function CompileProgram(const AContext: TProjectCompilationContext;
      const ADelphiPath, AProgramPath, AOutputPath: string;
      out ADependencies: TArray<string>): string;
    function CompileProgramEntries(const AContext: TProjectCompilationContext;
      const ADelphiPath, AProgramPath, AOutputPath: string;
      out ADependencies: TArray<TCompilerDependency>): string;
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  Atropos.Adapters.DelphiPowerShell, Atropos.Adapters.CompilerTraceScript;

constructor TCompilerTraceProcess.Create(const ARunner: IBuildProcessRunner;
  const ACancel: TCancellationCheck);
begin
  inherited Create;
  FRunner := ARunner;
  if not Assigned(FRunner) then FRunner := TWin32BuildProcessRunner.Create;
  FCancel := ACancel;
end;

class function TCompilerTraceProcess.Request(const AContext: TProjectCompilationContext;
  const ASourcePath, AOutputPath: string; AProgram: Boolean): string;
var LRequest, LInput: TJSONObject; LFiles: TJSONArray; LFile: TSourceDependency; LExtension: string;
begin
  if not AContext.Target.IsValid then
    raise EArgumentException.Create('Compiler preparation requires an explicit target.');
  if not SameText(AContext.Target.Platform, 'Win32') and
    not SameText(AContext.Target.Platform, 'Win64') then
    raise EArgumentException.Create('Compiler preparation supports Win32 and Win64.');
  LRequest := TJSONObject.Create;
  try
    LRequest.AddPair('projectPath', TPath.GetFullPath(AContext.ProjectPath));
    LRequest.AddPair('configuration', AContext.Target.Configuration);
    LRequest.AddPair('platform', AContext.Target.Platform);
    LRequest.AddPair('compilerContextHash', AContext.CompilerContextHash);
    LRequest.AddPair('sourcePath', TPath.GetFullPath(ASourcePath));
    LRequest.AddPair('outputPath', TPath.GetFullPath(AOutputPath));
    LExtension := '.dcu';
    if AProgram then LExtension := '.exe';
    LRequest.AddPair('artifactName', TPath.GetFileNameWithoutExtension(ASourcePath) + LExtension);
    LRequest.AddPair('collectDependencies', TJSONBool.Create(AProgram));
    LFiles := TJSONArray.Create;
    LRequest.AddPair('projectFiles', LFiles);
    for LFile in AContext.ProjectFiles do
    begin
      LInput := TJSONObject.Create;
      LFiles.AddElement(LInput);
      LInput.AddPair('filePath', LFile.FilePath);
      LInput.AddPair('contentHash', LFile.ContentHash);
    end;
    Result := LRequest.ToJSON;
  finally
    LRequest.Free;
  end;
end;

function TCompilerTraceProcess.Compile(const AContext: TProjectCompilationContext;
  const ADelphiPath, ASourcePath, AOutputPath: string): string;
begin
  Result := Execute(AContext, ADelphiPath, ASourcePath, AOutputPath, False);
end;

function TCompilerTraceProcess.DiscoverDependencies(const AContext: TProjectCompilationContext;
  const ADelphiPath, AProgramPath, AOutputPath: string): TArray<string>;
begin
  CompileProgram(AContext, ADelphiPath, AProgramPath, AOutputPath, Result);
end;

function TCompilerTraceProcess.CompileProgram(const AContext: TProjectCompilationContext;
  const ADelphiPath, AProgramPath, AOutputPath: string;
  out ADependencies: TArray<string>): string;
var LEntries: TArray<TCompilerDependency>; I: Integer;
begin
  Result := CompileProgramEntries(AContext, ADelphiPath, AProgramPath, AOutputPath, LEntries);
  SetLength(ADependencies, Length(LEntries));
  for I := 0 to High(LEntries) do ADependencies[I] := LEntries[I].FilePath;
end;

function TCompilerTraceProcess.CompileProgramEntries(const AContext: TProjectCompilationContext;
  const ADelphiPath, AProgramPath, AOutputPath: string;
  out ADependencies: TArray<TCompilerDependency>): string;
var LDependencies: string;
begin
  LDependencies := TPath.Combine(AOutputPath, TPath.GetFileNameWithoutExtension(AProgramPath) + '.d');
  if TFile.Exists(LDependencies) then
    raise EInvalidOperation.Create('Compiler preparation requires a fresh dependency list.');
  if Length(TDirectory.GetFiles(AOutputPath, '*.dcu')) > 0 then
    raise EInvalidOperation.Create('Dependency discovery requires an output directory without compiled units.');
  Result := Execute(AContext, ADelphiPath, AProgramPath, AOutputPath, True);
  ADependencies := TCompilerDependencies.ReadEntries(LDependencies, AOutputPath);
end;

function TCompilerTraceProcess.Execute(const AContext: TProjectCompilationContext;
  const ADelphiPath, ASourcePath, AOutputPath: string; AProgram: Boolean): string;
var LScriptPath, LCommand, LScript, LArtifact: string; LCode: Cardinal;
  LStarted, LTimedOut, LCancelled: Boolean; LSourceExtension, LArtifactExtension: string;
begin
  if Assigned(FCancel) then
    if FCancel() then raise EAbort.Create('Compiler preparation cancelled.');
  LSourceExtension := '.pas';
  LArtifactExtension := '.dcu';
  if AProgram then
  begin
    LSourceExtension := '.dpr';
    LArtifactExtension := '.exe';
  end;
  if not SameText(TPath.GetExtension(ASourcePath), LSourceExtension) or not TFile.Exists(ASourcePath) then
    raise EArgumentException.Create('Compiler preparation requires an existing ' + LSourceExtension + ' source.');
  LArtifact := TPath.Combine(AOutputPath, TPath.GetFileNameWithoutExtension(ASourcePath) + LArtifactExtension);
  if TFile.Exists(LArtifact) then
    raise EInvalidOperation.Create('Compiler preparation requires a fresh output artifact.');
  LScript := TCompilerTraceScript.Build(Request(AContext, ASourcePath, AOutputPath, AProgram));
  LScriptPath := TPath.Combine(AOutputPath, 'AtroposTrace-' + TGUID.NewGuid.ToString + '.ps1');
  LCommand := TDelphiPowerShell.Command(LScriptPath, ADelphiPath);
  TFile.WriteAllText(LScriptPath, LScript, TEncoding.UTF8);
  try
    LStarted := FRunner.Execute(LCommand, 60000, FCancel, Result,
      LCode, LTimedOut, LCancelled);
    if LCancelled then raise EAbort.Create('Compiler preparation cancelled.');
    if LTimedOut then raise EInvalidOperation.Create('Compiler preparation timed out.');
    if not LStarted or (LCode <> 0) then
      raise EInvalidOperation.Create('Compiler preparation failed: ' + Result);
    if not TFile.Exists(LArtifact) then
      raise EInvalidOperation.Create('Compiler preparation produced no output artifact.');
  finally
    TFile.Delete(LScriptPath);
  end;
end;

end.
