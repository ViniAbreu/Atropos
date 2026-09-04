unit Atropos.Adapters.BuildService;

interface
uses
  Atropos.Core.Ports;

type
  IBuildProcessRunner = interface
    ['{A44BDD56-4A86-46C5-A2B4-C95A6B2D54E2}']
    function Execute(const ACommand: string; ATimeoutMs: Cardinal;
      const AShouldCancel: TCancellationCheck; out AOutput: string;
      out AExitCode: Cardinal; out ATimedOut, ACancelled: Boolean): Boolean;
  end;

  IBuildProfileCleaner = interface
    ['{80823598-223C-4A44-B8BD-191842BEE019}']
    procedure Cleanup(const AProfileName: string);
  end;

  TWindowsBuildProfileCleaner = class(TInterfacedObject, IBuildProfileCleaner)
  public
    procedure Cleanup(const AProfileName: string);
  end;

  TWin32BuildProcessRunner = class(TInterfacedObject, IBuildProcessRunner)
  public
    function Execute(const ACommand: string; ATimeoutMs: Cardinal;
      const AShouldCancel: TCancellationCheck; out AOutput: string;
      out AExitCode: Cardinal; out ATimedOut, ACancelled: Boolean): Boolean;
  end;

  TBuildOutputParser = class
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
    FProfileCleaner: IBuildProfileCleaner;
    function GetDelphiFriendlyName(const ADelphiPath: string): string;
  public
    constructor Create(AEnvService: IDelphiEnvironmentService; ALogger: ILogger = nil;
      AProcessRunner: IBuildProcessRunner = nil; ATimeoutMs: Cardinal = 600000;
      const AShouldCancel: TCancellationCheck = nil;
      AProfileCleaner: IBuildProfileCleaner = nil);
    function BuildProject(const AProjectPath: string): TBuildMetrics;
  end;

implementation
uses System.Classes, System.Generics.Collections, System.IOUtils, System.Math, System.RegularExpressions, System.Win.Registry, Winapi.Windows,
  System.SysUtils;

constructor TBuildServiceAdapter.Create(AEnvService: IDelphiEnvironmentService; ALogger: ILogger;
  AProcessRunner: IBuildProcessRunner; ATimeoutMs: Cardinal;
  const AShouldCancel: TCancellationCheck; AProfileCleaner: IBuildProfileCleaner);
begin
  FEnvService := AEnvService;
  FLogger := ALogger;
  FProcessRunner := AProcessRunner;
  if not Assigned(FProcessRunner) then
    FProcessRunner := TWin32BuildProcessRunner.Create;
  FTimeoutMs := ATimeoutMs;
  FShouldCancel := AShouldCancel;
  FProfileCleaner := AProfileCleaner;
  if not Assigned(FProfileCleaner) then
    FProfileCleaner := TWindowsBuildProfileCleaner.Create;
end;

procedure TWindowsBuildProfileCleaner.Cleanup(const AProfileName: string);
var
  LRegistryPath: string;
  LRegistry: TRegistry;
begin
  if AProfileName.IsEmpty then
    Exit;
  LRegistryPath := 'Software\Embarcadero\' + AProfileName;
  LRegistry := TRegistry.Create(KEY_ALL_ACCESS);
  try
    LRegistry.RootKey := HKEY_CURRENT_USER;
    LRegistry.DeleteKey(LRegistryPath);
  finally
    LRegistry.Free;
  end;
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
  LBuffer: array[0..4095] of AnsiChar;
  LBytesRead: DWORD;
  LBytesAvailable: DWORD;
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
          while PeekNamedPipe(LReadPipe, nil, 0, nil, @LBytesAvailable, nil) and
            (LBytesAvailable > 0) do
          begin
            if not ReadFile(LReadPipe, LBuffer, Min(Cardinal(SizeOf(LBuffer) - 1), LBytesAvailable), LBytesRead, nil) then
              Break;
            LOutputStream.WriteBuffer(LBuffer, LBytesRead);
          end;
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
        while ReadFile(LReadPipe, LBuffer, SizeOf(LBuffer) - 1, LBytesRead, nil) and (LBytesRead > 0) do
          LOutputStream.WriteBuffer(LBuffer, LBytesRead);
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

class function TBuildOutputParser.Parse(const AOutput, AProjectPath: string; AExitCode: Cardinal): TBuildMetrics;
var
  LMatch: TMatch;
  LExeDir: string;
  LExePath: string;
  LHintsList: TList<TInlineHint>;
  LHint: TInlineHint;
  LRegexPattern: string;
  LProjDir: string;
begin
  Result := Default(TBuildMetrics);
  LProjDir := TPath.GetDirectoryName(AProjectPath);
  
  Result.Hints := 0;
  for LMatch in TRegEx.Matches(AOutput, '\[dcc[a-zA-Z0-9]* Hint\]') do
    Inc(Result.Hints);
  
  Result.Warnings := 0;
  for LMatch in TRegEx.Matches(AOutput, '\[dcc[a-zA-Z0-9]* Warning\]') do
    Inc(Result.Warnings);

  LHintsList := TList<TInlineHint>.Create;
  try
    LRegexPattern := '([^\s\[\]][^\r\n\[\]]*?\.pas).*?(H2443|H2445).*?unit ''([^'']+)''';
    for LMatch in TRegEx.Matches(AOutput, LRegexPattern) do
    begin
      LHint.FilePath := LMatch.Groups[1].Value.Trim;
      if TPath.IsRelativePath(LHint.FilePath) then
        LHint.FilePath := TPath.GetFullPath(TPath.Combine(LProjDir, LHint.FilePath));
      LHint.HintType := LMatch.Groups[2].Value;
      LHint.UnitNeeded := LMatch.Groups[3].Value;
      LHintsList.Add(LHint);
    end;
    Result.InlineHints := LHintsList.ToArray;
  finally
    LHintsList.Free;
  end;

  Result.Success := (AExitCode = 0) and
    not (TRegEx.IsMatch(AOutput, 'Build FAILED\.') or TRegEx.IsMatch(AOutput, '\[dcc[a-zA-Z0-9]* (Error|Fatal Error)\]'));
  if not Result.Success then
  begin
    LMatch := TRegEx.Match(AOutput, '\[dcc[a-zA-Z0-9]* (Error|Fatal Error)\][^\r\n]+');
    Result.ErrorMessage := 'Unknown compilation error.';
    if LMatch.Success then
      Result.ErrorMessage := LMatch.Value;
  end;

  LMatch := TRegEx.Match(AOutput, '(?:Time Elapsed|Elapsed time:)\s*([0-9:\.]+)');
  if LMatch.Success then
    Result.CompileTimeMs := 0;

  LExeDir := TPath.GetDirectoryName(AProjectPath);
  LMatch := TRegEx.Match(AOutput, '-E([^\s]+)');
  if LMatch.Success then
    LExeDir := TPath.GetFullPath(TPath.Combine(LExeDir, LMatch.Groups[1].Value.Trim));

  LExePath := TPath.Combine(LExeDir, TPath.GetFileNameWithoutExtension(AProjectPath) + '.exe');
  Result.ExeSizeBytes := 0;
  if TFile.Exists(LExePath) then
    Result.ExeSizeBytes := TFile.GetSize(LExePath);
end;

function TBuildServiceAdapter.GetDelphiFriendlyName(const ADelphiPath: string): string;
var
  LVersionNum: string;
begin
  LVersionNum := ExtractFileName(ExcludeTrailingPathDelimiter(ADelphiPath));
  if LVersionNum = '23.0' then
    Exit('12.1');
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
  LRegEntry: string;
  LOutput: string;
  LStartTick: UInt64;
  LExitCode: Cardinal;
  LTimedOut: Boolean;
  LCancelled: Boolean;
begin
  Result := Default(TBuildMetrics);
  if not Assigned(FEnvService) then
    raise Exception.Create('Delphi Environment Service is not assigned.');

  LDelphiPath := FEnvService.ResolveDelphiPath(AProjectPath);
  if LDelphiPath.IsEmpty then
  begin
    Result.Success := False;
    Result.ErrorMessage := 'Delphi path not found for project.';
    Exit;
  end;

  LBdsExe := TPath.Combine(LDelphiPath, 'bin\bds.exe');
  if not TFile.Exists(LBdsExe) then
  begin
    Result.Success := False;
    Result.ErrorMessage := 'bds.exe not found at ' + LBdsExe;
    Exit;
  end;

  LErrFile := TPath.Combine(TPath.GetTempPath, TGuid.NewGuid.ToString + '.err');
  LRegEntry := EmptyStr;
  LBdsCmd := Format('"%s" -b -ns -o"%s" "%s"', [LBdsExe, LErrFile, AProjectPath]);

  if Assigned(FLogger) then FLogger.Log('Executing Build via bds.exe (Universal Compiler): ' + LBdsCmd);

  LStartTick := GetTickCount64;
  try
    if not FProcessRunner.Execute(LBdsCmd, FTimeoutMs, FShouldCancel, LOutput,
      LExitCode, LTimedOut, LCancelled) then
    begin
      Result.Success := False;
      if LCancelled then
        Result.ErrorMessage := 'bds.exe build was cancelled.'
      else if LTimedOut then
        Result.ErrorMessage := Format('bds.exe build timed out after %d ms.', [FTimeoutMs])
      else
        Result.ErrorMessage := 'Failed to execute bds.exe process.';
      Exit;
    end;

    if not TFile.Exists(LErrFile) then
    begin
      Result.Success := False;
      Result.ErrorMessage := 'Failed to read bds.exe error file output.';
      Exit;
    end;

    LOutput := TFile.ReadAllText(LErrFile);
    Result := TBuildOutputParser.Parse(LOutput, AProjectPath, LExitCode);
    Result.DelphiVersion := GetDelphiFriendlyName(LDelphiPath);
    Result.CompileTimeMs := Int64(GetTickCount64 - LStartTick);
  finally
    if TFile.Exists(LErrFile) then
      TFile.Delete(LErrFile);
    FProfileCleaner.Cleanup(LRegEntry);
  end;
end;

end.

