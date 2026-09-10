unit Atropos.Adapters.ProjectContext;

interface

uses System.JSON, Atropos.Core.Ports, Atropos.Core.Compilation,
  Atropos.Adapters.BuildService;

type
  TMsBuildProjectContext = class(TInterfacedObject, IProjectContextProvider)
  private
    FRunner: IBuildProcessRunner;
    FShouldCancel: TCancellationCheck;
    function CreateRequest(const AProjectPath: string;
      const ATarget: TBuildTarget): string;
    function RunEvaluation(const AScript, ADelphiPath: string): string;
    function CreateCommand(const AScriptPath, ADelphiPath: string): string;
    class procedure ValidateCommandPath(const APath: string); static;
    class function ReadStrings(AObject: TJSONObject;
      const AName: string): TArray<string>; static;
    class function ReadOptions(AObject: TJSONObject): TArray<TCompilerOption>; static;
    class function ReadProjectFiles(AObject: TJSONObject): TArray<TSourceDependency>; static;
    class function Decode(const AOutput: string): TProjectCompilationContext; static;
  public
    constructor Create(const ARunner: IBuildProcessRunner = nil;
      const AShouldCancel: TCancellationCheck = nil);
    function EvaluateProject(const AProjectPath, ADelphiPath: string;
      const ATarget: TBuildTarget): TProjectCompilationContext;
  end;

implementation

uses System.SysUtils, System.Classes, System.IOUtils, System.NetEncoding,
  Atropos.Adapters.ProjectEvaluationScript;

constructor TMsBuildProjectContext.Create(const ARunner: IBuildProcessRunner;
  const AShouldCancel: TCancellationCheck);
begin
  inherited Create;
  FRunner := ARunner;
  if not Assigned(FRunner) then
    FRunner := TWin32BuildProcessRunner.Create;
  FShouldCancel := AShouldCancel;
end;

function TMsBuildProjectContext.CreateRequest(const AProjectPath: string;
  const ATarget: TBuildTarget): string;
var
  LRequest: TJSONObject;
begin
  if not (ATarget.Configuration.IsEmpty and ATarget.Platform.IsEmpty) and
    not ATarget.IsValid then
    raise EArgumentException.Create('Invalid compilation context target.');
  LRequest := TJSONObject.Create;
  try
    LRequest.AddPair('projectPath', TPath.GetFullPath(AProjectPath));
    LRequest.AddPair('configuration', ATarget.Configuration);
    LRequest.AddPair('platform', ATarget.Platform);
    Result := LRequest.ToJSON;
  finally
    LRequest.Free;
  end;
end;

class procedure TMsBuildProjectContext.ValidateCommandPath(const APath: string);
var
  LCharacter: Char;
begin
  for LCharacter in APath do
    if CharInSet(LCharacter, ['"', '%', '!', '&', '|', '<', '>', '^', #10, #13]) then
      raise EArgumentException.Create('Unsupported character in evaluation tool path.');
end;

function TMsBuildProjectContext.CreateCommand(const AScriptPath,
  ADelphiPath: string): string;
var
  LEnvironment, LWindows, LShell, LPowerShell: string;
begin
  LEnvironment := TPath.Combine(ADelphiPath, 'bin\rsvars.bat');
  LWindows := GetEnvironmentVariable('SystemRoot');
  LShell := TPath.Combine(LWindows, 'System32\cmd.exe');
  LPowerShell := TPath.Combine(LWindows, 'System32\WindowsPowerShell\v1.0\powershell.exe');
  ValidateCommandPath(LEnvironment);
  ValidateCommandPath(AScriptPath);
  ValidateCommandPath(LShell);
  ValidateCommandPath(LPowerShell);
  if not TFile.Exists(LEnvironment) then
    raise EFileNotFoundException.Create('Delphi environment script not found: ' + LEnvironment);
  if not TFile.Exists(LPowerShell) then
    raise EFileNotFoundException.Create('Windows PowerShell is unavailable.');
  Result := Format('"%s" /d /c ""%s" && "%s" -NoProfile -NonInteractive -File "%s""',
    [LShell, LEnvironment, LPowerShell, AScriptPath]);
end;

function TMsBuildProjectContext.RunEvaluation(const AScript,
  ADelphiPath: string): string;
var
  LPath, LCommand: string;
  LExitCode: Cardinal;
  LTimedOut, LCancelled, LStarted: Boolean;
begin
  LPath := TPath.Combine(TPath.GetTempPath, 'Atropos-Context-' + TGuid.NewGuid.ToString + '.ps1');
  LCommand := CreateCommand(LPath, ADelphiPath);
  TFile.WriteAllText(LPath, AScript, TEncoding.UTF8);
  try
    LStarted := FRunner.Execute(LCommand, 60000, FShouldCancel, Result,
      LExitCode, LTimedOut, LCancelled);
    if LCancelled then
      raise EAbort.Create('Project context evaluation cancelled.');
    if LTimedOut then
      raise EInvalidOperation.Create('Project context evaluation timed out.');
    if not LStarted or (LExitCode <> 0) then
      raise EInvalidOperation.Create('Project context evaluation failed: ' + Result);
  finally
    TFile.Delete(LPath);
  end;
end;

class function TMsBuildProjectContext.ReadStrings(AObject: TJSONObject;
  const AName: string): TArray<string>;
var
  LItems: TJSONArray;
  LIndex: Integer;
begin
  LItems := AObject.GetValue<TJSONArray>(AName);
  SetLength(Result, LItems.Count);
  for LIndex := 0 to LItems.Count - 1 do
    Result[LIndex] := LItems.Items[LIndex].Value;
end;

class function TMsBuildProjectContext.ReadOptions(
  AObject: TJSONObject): TArray<TCompilerOption>;
var
  LOptions: TJSONObject;
  LIndex: Integer;
begin
  LOptions := AObject.GetValue<TJSONObject>('options');
  SetLength(Result, LOptions.Count);
  for LIndex := 0 to LOptions.Count - 1 do
  begin
    Result[LIndex].Name := LOptions.Pairs[LIndex].JsonString.Value;
    Result[LIndex].Value := LOptions.Pairs[LIndex].JsonValue.Value;
  end;
end;

class function TMsBuildProjectContext.ReadProjectFiles(
  AObject: TJSONObject): TArray<TSourceDependency>;
var
  LFiles: TJSONArray;
  LIndex: Integer;
begin
  LFiles := AObject.GetValue<TJSONArray>('projectFiles');
  SetLength(Result, LFiles.Count);
  for LIndex := 0 to LFiles.Count - 1 do
  begin
    Result[LIndex].FilePath := LFiles.Items[LIndex].GetValue<string>('path');
    Result[LIndex].ContentHash := LFiles.Items[LIndex].GetValue<string>('sha256');
  end;
end;

class function TMsBuildProjectContext.Decode(
  const AOutput: string): TProjectCompilationContext;
const
  CMarker = 'ATROPOS_CONTEXT=';
var
  LLine, LPayload: string;
  LValue: TJSONValue;
  LData: TJSONObject;
begin
  LPayload := '';
  for LLine in AOutput.Split([#10]) do
    if LLine.StartsWith(CMarker) then
      LPayload := LLine.Substring(Length(CMarker)).Trim;
  if LPayload.IsEmpty then
    raise EInvalidOperation.Create('Project evaluator returned no context.');
  LValue := TJSONObject.ParseJSONValue(TNetEncoding.Base64.Decode(LPayload));
  try
    if not (LValue is TJSONObject) then
      raise EInvalidOperation.Create('Invalid project context response.');
    LData := TJSONObject(LValue);
    Result.ProjectPath := LData.GetValue<string>('projectPath');
    Result.Target := TBuildTarget.Create(LData.GetValue<string>('configuration'),
      LData.GetValue<string>('platform'));
    Result.MainSource := LData.GetValue<string>('mainSource');
    Result.ApplicationType := LData.GetValue<string>('applicationType');
    Result.CompilerPath := LData.GetValue<string>('compilerPath');
    Result.CompilerFileVersion := LData.GetValue<string>('compilerFileVersion');
    Result.Defines := ReadStrings(LData, 'defines');
    Result.UnitPaths := ReadStrings(LData, 'unitPaths');
    Result.SearchPaths := ReadStrings(LData, 'searchPaths');
    Result.IncludePaths := ReadStrings(LData, 'includePaths');
    Result.Namespaces := ReadStrings(LData, 'namespaces');
    Result.Aliases := ReadStrings(LData, 'aliases');
    Result.Options := ReadOptions(LData);
    Result.ProjectFiles := ReadProjectFiles(LData);
    Result.DeferredProperties := ReadStrings(LData, 'deferredProperties');
  finally
    LValue.Free;
  end;
end;

function TMsBuildProjectContext.EvaluateProject(const AProjectPath,
  ADelphiPath: string; const ATarget: TBuildTarget): TProjectCompilationContext;
begin
  Result := Decode(RunEvaluation(TProjectEvaluationScript.Build(
    CreateRequest(AProjectPath, ATarget)), ADelphiPath));
end;

end.
