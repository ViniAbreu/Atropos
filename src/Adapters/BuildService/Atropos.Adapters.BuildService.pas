unit Atropos.Adapters.BuildService;

interface
uses
  Atropos.Core.Ports, System.Classes, Winapi.Windows;

type
  IBuildProcessRunner = interface
    ['{A44BDD56-4A86-46C5-A2B4-C95A6B2D54E2}']
    function Execute(const ACommand: string; ATimeoutMs: Cardinal;
      const AShouldCancel: TCancellationCheck; out AOutput: string;
      out AExitCode: Cardinal; out ATimedOut, ACancelled: Boolean): Boolean;
  end;

  IBuildCapabilityDetector = interface
    ['{82FD4B29-1B0D-44B7-BEE7-72B118BEE024}']
    function SupportsHeadlessMSBuild(const ADelphiPath: string): Boolean;
  end;

  TWin32BuildProcessRunner = class(TInterfacedObject, IBuildProcessRunner)
  private
    procedure DrainAvailableOutput(AReadPipe: THandle; AOutputStream: TStream);
  public
    function Execute(const ACommand: string; ATimeoutMs: Cardinal;
      const AShouldCancel: TCancellationCheck; out AOutput: string;
      out AExitCode: Cardinal; out ATimedOut, ACancelled: Boolean): Boolean;
  end;

  TBuildOutputParser = class
  private
    class function ContainsBuildError(const AOutput: string): Boolean; static;
    class function GetDiagnosticCount(const AOutput,
      ACodePrefix: string): Integer; static;
    class function GetBuildError(const AOutput: string): string; static;
    class function GetExecutableDirectory(const AOutput,
      AProjectPath: string): string; static;
    class function GetInlineHints(const AOutput,
      AProjectPath: string): TArray<TInlineHint>; static;
  public
    class function Parse(const AOutput, AProjectPath: string; AExitCode: Cardinal): TBuildMetrics; static;
  end;

  TBuildServiceAdapter = class(TInterfacedObject, IBuildService)
  private
    FEnvService: IDelphiEnvironmentService;
    FLogger: ILogger;
    FProcessRunner: IBuildProcessRunner;
    FTimeoutMs: Cardinal;
    FShouldCancel: TCancellationCheck;
    FCapabilityDetector: IBuildCapabilityDetector;
    function GetDelphiFriendlyName(const ADelphiPath: string): string;
    function ExecuteBuildCommand(const ACommand, AErrorFile, AProjectPath,
      ADelphiPath, AToolName: string; ARequiresOutputFile: Boolean): TBuildMetrics;
    function BuildProjectWithMSBuild(const AProjectPath,
      ADelphiPath: string): TBuildMetrics;
    function ShouldUseBdsFallback(const AMetrics: TBuildMetrics): Boolean;
  public
    constructor Create(AEnvService: IDelphiEnvironmentService; ALogger: ILogger = nil;
      AProcessRunner: IBuildProcessRunner = nil; ATimeoutMs: Cardinal = 600000;
      const AShouldCancel: TCancellationCheck = nil;
      const ACapabilityDetector: IBuildCapabilityDetector = nil);
    function BuildProject(const AProjectPath: string): TBuildMetrics;
    function BuildProjectForTarget(const AProjectPath: string;
      const ATarget: TBuildTarget): TBuildMetrics;
  end;

implementation
uses Atropos.Core.Profiling, System.Generics.Collections, System.IOUtils, System.Math,
  System.RegularExpressions, System.StrUtils, System.SysUtils;

constructor TBuildServiceAdapter.Create(AEnvService: IDelphiEnvironmentService; ALogger: ILogger;
  AProcessRunner: IBuildProcessRunner; ATimeoutMs: Cardinal;
  const AShouldCancel: TCancellationCheck;
  const ACapabilityDetector: IBuildCapabilityDetector);
begin
  FEnvService := AEnvService;
  FLogger := ALogger;
  FProcessRunner := AProcessRunner;
  if not Assigned(FProcessRunner) then
    FProcessRunner := TWin32BuildProcessRunner.Create;
  FTimeoutMs := ATimeoutMs;
  FShouldCancel := AShouldCancel;
  FCapabilityDetector := ACapabilityDetector;
end;

function TWin32BuildProcessRunner.Execute(const ACommand: string; ATimeoutMs: Cardinal;
  const AShouldCancel: TCancellationCheck; out AOutput: string; out AExitCode: Cardinal;
  out ATimedOut, ACancelled: Boolean): Boolean;
var
  LSecurityAttributes: TSecurityAttributes;
  LReadPipe: THandle;
  LWritePipe: THandle;
  LStartupInfo: TStartupInfo;
  LProcessInfo: TProcessInformation;
  LOutputStream: TStringStream;
  LMutableCmd: string;
  LStartTick: UInt64;
  LWaitResult: DWORD;
  LJob: THandle;
  LJobInfo: TJobObjectExtendedLimitInformation;
begin
  Result := False;
  AOutput := EmptyStr;
  AExitCode := Cardinal(-1);
  ATimedOut := False;
  ACancelled := False;
  LJob := 0;

  LSecurityAttributes.nLength := SizeOf(TSecurityAttributes);
  LSecurityAttributes.bInheritHandle := True;
  LSecurityAttributes.lpSecurityDescriptor := nil;

  if not CreatePipe(LReadPipe, LWritePipe, @LSecurityAttributes, 0) then
    Exit;

  try
    FillChar(LStartupInfo, SizeOf(TStartupInfo), 0);
    LStartupInfo.cb := SizeOf(TStartupInfo);
    LStartupInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    LStartupInfo.wShowWindow := SW_HIDE;
    LStartupInfo.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    LStartupInfo.hStdOutput := LWritePipe;
    LStartupInfo.hStdError := LWritePipe;

  LMutableCmd := ACommand;
    UniqueString(LMutableCmd);
    if CreateProcess(nil, PChar(LMutableCmd), nil, nil, True,
      CREATE_NO_WINDOW or CREATE_SUSPENDED, nil, nil, LStartupInfo, LProcessInfo) then
    begin
      LJob := CreateJobObject(nil, nil);
      if LJob = 0 then
      begin
        TerminateProcess(LProcessInfo.hProcess, ERROR_NOT_ENOUGH_MEMORY);
        CloseHandle(LProcessInfo.hProcess);
        CloseHandle(LProcessInfo.hThread);
        Exit;
      end;
      FillChar(LJobInfo, SizeOf(LJobInfo), 0);
      LJobInfo.BasicLimitInformation.LimitFlags := JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
      if not SetInformationJobObject(LJob, JobObjectExtendedLimitInformation,
        @LJobInfo, SizeOf(LJobInfo)) or
        not AssignProcessToJobObject(LJob, LProcessInfo.hProcess) then
      begin
        TerminateProcess(LProcessInfo.hProcess, ERROR_ACCESS_DENIED);
        CloseHandle(LProcessInfo.hProcess);
        CloseHandle(LProcessInfo.hThread);
        CloseHandle(LJob);
        LJob := 0;
        Exit;
      end;
      ResumeThread(LProcessInfo.hThread);
      CloseHandle(LWritePipe); 
      LWritePipe := 0;

      LOutputStream := TStringStream.Create('');
      try
        LStartTick := GetTickCount64;
        repeat
        begin
          DrainAvailableOutput(LReadPipe, LOutputStream);
          LWaitResult := WaitForSingleObject(LProcessInfo.hProcess, 10);
          if LWaitResult = WAIT_OBJECT_0 then
            Break;
          if Assigned(AShouldCancel) and AShouldCancel() then
          begin
            ACancelled := True;
            TerminateJobObject(LJob, ERROR_CANCELLED);
            WaitForSingleObject(LProcessInfo.hProcess, 5000);
            Break;
          end;
          if (ATimeoutMs > 0) and (GetTickCount64 - LStartTick >= ATimeoutMs) then
          begin
            ATimedOut := True;
            TerminateJobObject(LJob, ERROR_TIMEOUT);
            WaitForSingleObject(LProcessInfo.hProcess, 5000);
            Break;
          end;
        end
        until False;
        DrainAvailableOutput(LReadPipe, LOutputStream);
        AOutput := LOutputStream.DataString;
      finally
        LOutputStream.Free;
      end;

      if GetExitCodeProcess(LProcessInfo.hProcess, AExitCode) then
        Result := not (ATimedOut or ACancelled);
      CloseHandle(LProcessInfo.hProcess);
      CloseHandle(LProcessInfo.hThread);
      CloseHandle(LJob);
      LJob := 0;
    end;
  finally
    if LJob <> 0 then CloseHandle(LJob);
    if LWritePipe <> 0 then CloseHandle(LWritePipe);
    CloseHandle(LReadPipe);
  end;
end;

procedure TWin32BuildProcessRunner.DrainAvailableOutput(AReadPipe: THandle;
  AOutputStream: TStream);
const
  BufferSize = 4096;
var
  LBuffer: array[0..BufferSize - 1] of AnsiChar;
  LBytesAvailable: DWORD;
  LBytesRead: DWORD;
begin
  repeat
    if not PeekNamedPipe(AReadPipe, nil, 0, nil, @LBytesAvailable, nil) then
      Exit;
    if LBytesAvailable = 0 then
      Exit;
    if not ReadFile(AReadPipe, LBuffer, Min(DWORD(BufferSize), LBytesAvailable),
      LBytesRead, nil) then
      Exit;
    if LBytesRead = 0 then
      Exit;
    AOutputStream.WriteBuffer(LBuffer, LBytesRead);
  until False;
end;

class function TBuildOutputParser.Parse(const AOutput, AProjectPath: string; AExitCode: Cardinal): TBuildMetrics;
var
  LMatch: TMatch;
  LExeDir: string;
  LExePath: string;
begin
  Result := Default(TBuildMetrics);
  Result.DiagnosticOutput := AOutput;
  Result.Hints := GetDiagnosticCount(AOutput, 'H');
  Result.Warnings := GetDiagnosticCount(AOutput, 'W');
  Result.InlineHints := GetInlineHints(AOutput, AProjectPath);

  Result.Success := (AExitCode = 0) and
    not ContainsBuildError(AOutput);
  if not Result.Success then
    Result.ErrorMessage := GetBuildError(AOutput);

  LMatch := TRegEx.Match(AOutput, '(?:Time Elapsed|Elapsed time:)\s*([0-9:\.]+)');
  if LMatch.Success then
    Result.CompileTimeMs := 0;

  LExeDir := GetExecutableDirectory(AOutput, AProjectPath);

  LExePath := TPath.Combine(LExeDir, TPath.GetFileNameWithoutExtension(AProjectPath) + '.exe');
  Result.ExeSizeBytes := 0;
  if TFile.Exists(LExePath) then
    Result.ExeSizeBytes := TFile.GetSize(LExePath);
end;

class function TBuildOutputParser.GetDiagnosticCount(const AOutput,
  ACodePrefix: string): Integer;
var
  LDiagnosticKeys: TDictionary<string, Byte>;
  LKey: string;
  LMatch: TMatch;
  LPattern: string;
begin
  LPattern := '(?im)^(?:\s*\[dcc[^\]]+\]\s*)?' +
    '(?<file>[^\r\n]*?\.pas)\((?<location>\d+(?:,\d+)?)\)\s*:\s*' +
    '(?:hint\s+)?(?:warning\s+)?(?<code>' + ACodePrefix +
    '\d{4})\s*:?\s*(?<message>.*?)(?:\s+\[[^\]\r\n]+\.dproj\])?\s*$';
  LDiagnosticKeys := TDictionary<string, Byte>.Create;
  try
    for LMatch in TRegEx.Matches(AOutput, LPattern) do
    begin
      LKey := LowerCase(LMatch.Groups['file'].Value.Trim + '|' +
        LMatch.Groups['location'].Value + '|' +
        LMatch.Groups['code'].Value + '|' +
        LMatch.Groups['message'].Value.Trim);
      LDiagnosticKeys.TryAdd(LKey, 0);
    end;
    Result := LDiagnosticKeys.Count;
  finally
    LDiagnosticKeys.Free;
  end;
end;

class function TBuildOutputParser.GetInlineHints(const AOutput,
  AProjectPath: string): TArray<TInlineHint>;
var
  LHint: TInlineHint;
  LHintKeys: TDictionary<string, Byte>;
  LHints: TList<TInlineHint>;
  LMatch: TMatch;
  LProjectDirectory: string;
begin
  LProjectDirectory := TPath.GetDirectoryName(AProjectPath);
  LHintKeys := TDictionary<string, Byte>.Create;
  LHints := TList<TInlineHint>.Create;
  try
    for LMatch in TRegEx.Matches(AOutput,
      '([^\s\[\]][^\r\n\[\]]*?\.pas).*?(H2443|H2445).*?unit ''([^'']+)''') do
    begin
      LHint.FilePath := LMatch.Groups[1].Value.Trim;
      if TPath.IsRelativePath(LHint.FilePath) then
        LHint.FilePath := TPath.GetFullPath(TPath.Combine(LProjectDirectory,
          LHint.FilePath));
      LHint.HintType := LMatch.Groups[2].Value;
      LHint.UnitNeeded := LMatch.Groups[3].Value;
      if not LHintKeys.TryAdd(LowerCase(LHint.FilePath + '|' +
        LHint.HintType + '|' + LHint.UnitNeeded), 0) then
        Continue;
      LHints.Add(LHint);
    end;
    Result := LHints.ToArray;
  finally
    LHints.Free;
    LHintKeys.Free;
  end;
end;

class function TBuildOutputParser.ContainsBuildError(
  const AOutput: string): Boolean;
begin
  Result := TRegEx.IsMatch(AOutput, 'Build FAILED\.', [roIgnoreCase]);
  if Result then
    Exit;
  Result := TRegEx.IsMatch(AOutput,
    '\[dcc[a-zA-Z0-9]* (Error|Fatal Error)\]', [roIgnoreCase]);
  if Result then
    Exit;
  Result := TRegEx.IsMatch(AOutput,
    '^.*\berror\s+[A-Z]+[0-9]+\s*:[^\r\n]*$',
    [roIgnoreCase, roMultiLine]);
end;

class function TBuildOutputParser.GetBuildError(
  const AOutput: string): string;
var
  LMatch: TMatch;
begin
  LMatch := TRegEx.Match(AOutput,
    '\[dcc[a-zA-Z0-9]* (Error|Fatal Error)\][^\r\n]+', [roIgnoreCase]);
  if LMatch.Success then
    Exit(LMatch.Value.Trim);
  LMatch := TRegEx.Match(AOutput,
    '^.*\berror\s+[A-Z]+[0-9]+\s*:[^\r\n]*$',
    [roIgnoreCase, roMultiLine]);
  if LMatch.Success then
    Exit(LMatch.Value.Trim);
  Result := 'Unknown compilation error.';
end;

class function TBuildOutputParser.GetExecutableDirectory(const AOutput,
  AProjectPath: string): string;
var
  LMatch: TMatch;
  LOutputDirectory: string;
begin
  Result := TPath.GetDirectoryName(AProjectPath);
  LMatch := TRegEx.Match(AOutput, '-E(?:"([^"]+)"|([^\s]+))');
  if not LMatch.Success then
    Exit;
  LOutputDirectory := LMatch.Groups[1].Value;
  if LOutputDirectory.IsEmpty then
    LOutputDirectory := LMatch.Groups[2].Value;
  Result := TPath.GetFullPath(TPath.Combine(Result, LOutputDirectory.Trim));
end;

function TBuildServiceAdapter.GetDelphiFriendlyName(const ADelphiPath: string): string;
var
  LVersionNum: string;
begin
  LVersionNum := ExtractFileName(ExcludeTrailingPathDelimiter(ADelphiPath));
  if LVersionNum = '37.0' then
    Exit('13');
  if LVersionNum = '23.0' then
    Exit('12');
  if LVersionNum = '22.0' then
    Exit('11.0');
  if LVersionNum = '21.0' then
    Exit('10.4');
  if LVersionNum = '20.0' then
    Exit('10.3');
  if LVersionNum = '19.0' then
    Exit('10.2');
  if LVersionNum = '18.0' then
    Exit('10.1');
  if LVersionNum = '17.0' then
    Exit('10.0');
  Result := LVersionNum;
end;

function TBuildServiceAdapter.BuildProject(const AProjectPath: string): TBuildMetrics;
var
  LDelphiPath: string;
  LBdsExe: string;
  LBdsCmd: string;
  LErrFile: string;
begin
  Result := Default(TBuildMetrics);
  if not Assigned(FEnvService) then
    raise Exception.Create('Delphi Environment Service is not assigned.');

  LDelphiPath := FEnvService.ResolveDelphiPath(AProjectPath);
  if Assigned(FLogger) then
    FLogger.Log('Resolved Delphi installation: ' + LDelphiPath);
  if LDelphiPath.IsEmpty then
  begin
    Result.Success := False;
    Result.ErrorMessage := 'Delphi path not found for project.';
    Exit;
  end;

  if Assigned(FCapabilityDetector) and
    FCapabilityDetector.SupportsHeadlessMSBuild(LDelphiPath) then
  begin
    Result := BuildProjectWithMSBuild(AProjectPath, LDelphiPath);
    if not ShouldUseBdsFallback(Result) then
      Exit;
    if Assigned(FLogger) then
      FLogger.Log('Headless MSBuild is unavailable for this installation; ' +
        'falling back to bds.exe.');
  end;

  LBdsExe := TPath.Combine(LDelphiPath, 'bin\bds.exe');
  if not TFile.Exists(LBdsExe) then
    LBdsExe := TPath.Combine(LDelphiPath, 'bin64\bds.exe');
  if not TFile.Exists(LBdsExe) then
  begin
    Result.Success := False;
    Result.ErrorMessage := 'bds.exe not found in bin or bin64 under ' + LDelphiPath;
    Exit;
  end;

  LErrFile := TPath.Combine(TPath.GetTempPath, TGuid.NewGuid.ToString + '.err');
  LBdsCmd := Format('"%s" -b -ns -o"%s" "%s"', [LBdsExe, LErrFile, AProjectPath]);

  if Assigned(FLogger) then FLogger.Log('Executing Build via bds.exe (Universal Compiler): ' + LBdsCmd);

  Result := ExecuteBuildCommand(LBdsCmd, LErrFile, AProjectPath, LDelphiPath,
    'bds.exe', True);
end;

function TBuildServiceAdapter.ShouldUseBdsFallback(
  const AMetrics: TBuildMetrics): Boolean;
var
  LFailureDetails: string;
begin
  LFailureDetails := AMetrics.DiagnosticOutput + sLineBreak +
    AMetrics.ErrorMessage;
  Result := not AMetrics.Success and
    (ContainsText(LFailureDetails, 'licen') or
     ContainsText(LFailureDetails, 'Community Edition') or
     ContainsText(LFailureDetails, 'command-line compiler') or
     ContainsText(LFailureDetails, 'Failed to execute MSBuild.exe'));
end;

function TBuildServiceAdapter.BuildProjectWithMSBuild(const AProjectPath,
  ADelphiPath: string): TBuildMetrics;
var
  LCommand: string;
  LCommandProcessorPath: string;
  LEnvironmentScriptPath: string;
  LErrorFile: string;
  LMSBuildPath: string;
begin
  LMSBuildPath := TPath.Combine(GetEnvironmentVariable('WINDIR'),
    'Microsoft.NET\Framework\v4.0.30319\MSBuild.exe');
  LEnvironmentScriptPath := TPath.Combine(ADelphiPath, 'bin\rsvars.bat');
  LCommandProcessorPath := GetEnvironmentVariable('ComSpec');
  LErrorFile := TPath.Combine(TPath.GetTempPath,
    TGuid.NewGuid.ToString + '.msbuild.log');
  LCommand := Format('"%s" /d /c ""%s" && "%s" "%s" ' +
    '/t:Build /nologo /v:minimal"', [LCommandProcessorPath,
    LEnvironmentScriptPath, LMSBuildPath, AProjectPath]);
  if Assigned(FLogger) then
    FLogger.Log('Executing default project build via headless MSBuild.');
  Result := ExecuteBuildCommand(LCommand, LErrorFile, AProjectPath,
    ADelphiPath, 'MSBuild.exe', False);
end;

function TBuildServiceAdapter.ExecuteBuildCommand(const ACommand, AErrorFile,
  AProjectPath, ADelphiPath, AToolName: string;
  ARequiresOutputFile: Boolean): TBuildMetrics;
var
  LOutput: string;
  LStartTick: UInt64;
  LExitCode: Cardinal;
  LTimedOut: Boolean;
  LCancelled: Boolean;
begin
  Result := Default(TBuildMetrics);
  LStartTick := GetTickCount64;
  try
    if not FProcessRunner.Execute(ACommand, FTimeoutMs, FShouldCancel, LOutput,
      LExitCode, LTimedOut, LCancelled) then
    begin
      Result.Success := False;
      if LCancelled then
      begin
        Result.ErrorMessage := AToolName + ' build was cancelled.';
        Exit;
      end;
      if LTimedOut then
        Result.ErrorMessage := Format('%s build timed out after %d ms.',
          [AToolName, FTimeoutMs]);
      if not LTimedOut then
        Result.ErrorMessage := 'Failed to execute ' + AToolName + ' process.';
      Exit;
    end;

    if ARequiresOutputFile and not TFile.Exists(AErrorFile) then
    begin
      Result.Success := False;
      Result.ErrorMessage := 'Failed to read ' + AToolName + ' output.';
      Exit;
    end;

    if TFile.Exists(AErrorFile) then
      LOutput := TFile.ReadAllText(AErrorFile);
    Result := TBuildOutputParser.Parse(LOutput, AProjectPath, LExitCode);
    Result.DelphiVersion := GetDelphiFriendlyName(ADelphiPath);
    Result.CompileTimeMs := Int64(GetTickCount64 - LStartTick);
  finally
    if TFile.Exists(AErrorFile) then
      TFile.Delete(AErrorFile);
  end;
end;

function TBuildServiceAdapter.BuildProjectForTarget(const AProjectPath: string;
  const ATarget: TBuildTarget): TBuildMetrics;
var LProfileScope: IInterface;
  LDelphiPath: string;
  LMSBuildPath: string;
  LCommandProcessorPath: string;
  LEnvironmentScriptPath: string;
  LDelphiLibraryPath: string;
  LErrorFile: string;
  LCommand: string;
begin
  LProfileScope := TExecutionProfile.Measure('builds', AProjectPath);
  Result := Default(TBuildMetrics);
  if not Assigned(FEnvService) then
  begin
    Result.ErrorMessage := 'Delphi environment service is not available.';
    Exit;
  end;
  if not ATarget.IsValid then
  begin
    Result.ErrorMessage := 'Invalid build target.';
    Exit;
  end;
  LDelphiPath := FEnvService.ResolveDelphiPath(AProjectPath);
  if Assigned(FLogger) then
    FLogger.Log('Resolved Delphi installation: ' + LDelphiPath);
  if LDelphiPath.IsEmpty then
  begin
    Result.ErrorMessage := 'Delphi path not found for project.';
    Exit;
  end;
  LMSBuildPath := TPath.Combine(GetEnvironmentVariable('WINDIR'),
    'Microsoft.NET\Framework\v4.0.30319\MSBuild.exe');
  if not TFile.Exists(LMSBuildPath) then
  begin
    Result.ErrorMessage := 'MSBuild.exe not found at ' + LMSBuildPath;
    Exit;
  end;
  LErrorFile := TPath.Combine(TPath.GetTempPath,
    TGuid.NewGuid.ToString + '.msbuild.log');
  LCommandProcessorPath := GetEnvironmentVariable('ComSpec');
  LEnvironmentScriptPath := TPath.Combine(LDelphiPath, 'bin\rsvars.bat');
  LDelphiLibraryPath := TPath.Combine(LDelphiPath,
    Format('lib\%s\release', [ATarget.Platform]));
  if not TFile.Exists(LEnvironmentScriptPath) then
  begin
    Result.ErrorMessage := 'rsvars.bat not found at ' + LEnvironmentScriptPath;
    Exit;
  end;
  LCommand := Format(
    '"%s" /d /c ""%s" && "%s" "%s" /t:Build /p:Config="%s" ' +
    '/p:Platform="%s" /p:DelphiLibraryPath="%s" /nologo /v:minimal"',
    [LCommandProcessorPath, LEnvironmentScriptPath, LMSBuildPath,
     AProjectPath, ATarget.Configuration, ATarget.Platform,
     LDelphiLibraryPath]);
  if Assigned(FLogger) then
    FLogger.Log(Format('Executing target build %s|%s via MSBuild.',
      [ATarget.Configuration, ATarget.Platform]));
  Result := ExecuteBuildCommand(LCommand, LErrorFile, AProjectPath,
    LDelphiPath, 'MSBuild.exe', False);
end;

end.
