unit Atropos.Adapters.BuildService;

interface
uses
  Atropos.Core.Ports, System.SysUtils, System.Classes, Winapi.Windows, System.RegularExpressions, System.IOUtils;

type
  TBuildServiceAdapter = class(TInterfacedObject, IBuildService)
  private
    FEnvService: IDelphiEnvironmentService;
    FLogger: ILogger;
    function RunCmdAndCaptureOutput(const ACmd: string; out AOutput: string): Boolean;
    function ParseBuildOutput(const AOutput, AProjectPath: string): TBuildMetrics;
    function GetDelphiFriendlyName(const ADelphiPath: string): string;
  public
    constructor Create(AEnvService: IDelphiEnvironmentService; ALogger: ILogger = nil);
    function BuildProject(const AProjectPath: string): TBuildMetrics;
  end;

implementation

constructor TBuildServiceAdapter.Create(AEnvService: IDelphiEnvironmentService; ALogger: ILogger = nil);
begin
  FEnvService := AEnvService;
  FLogger := ALogger;
end;

function TBuildServiceAdapter.RunCmdAndCaptureOutput(const ACmd: string; out AOutput: string): Boolean;
var
  LSecurityAttributes: TSecurityAttributes;
  LReadPipe, LWritePipe: THandle;
  LStartupInfo: TStartupInfo;
  LProcessInfo: TProcessInformation;
  LBuffer: array[0..4095] of AnsiChar;
  LBytesRead: DWORD;
  LOutputStream: TStringStream;
  LMutableCmd: string;
begin
  Result := False;
  AOutput := '';

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

    LMutableCmd := ACmd;
    UniqueString(LMutableCmd);
    if CreateProcess(nil, PChar(LMutableCmd), nil, nil, True, CREATE_NO_WINDOW, nil, nil, LStartupInfo, LProcessInfo) then
    begin
      CloseHandle(LWritePipe); 
      LWritePipe := 0;

      LOutputStream := TStringStream.Create('');
      try
        while ReadFile(LReadPipe, LBuffer, SizeOf(LBuffer) - 1, LBytesRead, nil) and (LBytesRead > 0) do
        begin
          LBuffer[LBytesRead] := #0;
          LOutputStream.WriteBuffer(LBuffer, LBytesRead);
        end;
        AOutput := LOutputStream.DataString;
      finally
        LOutputStream.Free;
      end;

      WaitForSingleObject(LProcessInfo.hProcess, INFINITE);
      CloseHandle(LProcessInfo.hProcess);
      CloseHandle(LProcessInfo.hThread);
      Result := True;
    end;
  finally
    if LWritePipe <> 0 then CloseHandle(LWritePipe);
    CloseHandle(LReadPipe);
  end;
end;

function TBuildServiceAdapter.ParseBuildOutput(const AOutput, AProjectPath: string): TBuildMetrics;
var
  LMatch: TMatch;
begin
  Result := Default(TBuildMetrics);
  
  Result.Hints := 0;
  for LMatch in TRegEx.Matches(AOutput, '\[dcc32 Hint\]') do Inc(Result.Hints);
  
  Result.Warnings := 0;
  for LMatch in TRegEx.Matches(AOutput, '\[dcc32 Warning\]') do Inc(Result.Warnings);

  Result.Success := not (TRegEx.IsMatch(AOutput, 'Build FAILED\.') or TRegEx.IsMatch(AOutput, '\[dcc32 (Error|Fatal Error)\]'));
  if not Result.Success then
  begin
    LMatch := TRegEx.Match(AOutput, '\[dcc32 (Error|Fatal Error)\][^\r\n]+');
    if LMatch.Success then
      Result.ErrorMessage := LMatch.Value
    else
      Result.ErrorMessage := 'Unknown compilation error.';
  end;

  LMatch := TRegEx.Match(AOutput, '(?:Time Elapsed|Elapsed time:)\s*([0-9:\.]+)');
  if LMatch.Success then
  begin
    Result.CompileTimeMs := 0; 
  end;

  var LExeDir := TPath.GetDirectoryName(AProjectPath);
  LMatch := TRegEx.Match(AOutput, '-E([^\s]+)');
  if LMatch.Success then
    LExeDir := TPath.GetFullPath(TPath.Combine(LExeDir, Trim(LMatch.Groups[1].Value)));

  var LExePath := TPath.Combine(LExeDir, TPath.GetFileNameWithoutExtension(AProjectPath) + '.exe');
  if TFile.Exists(LExePath) then
    Result.ExeSizeBytes := TFile.GetSize(LExePath)
  else
    Result.ExeSizeBytes := 0;
end;

function TBuildServiceAdapter.GetDelphiFriendlyName(const ADelphiPath: string): string;
var
  LVersionNum: string;
begin
  LVersionNum := ExtractFileName(ExcludeTrailingPathDelimiter(ADelphiPath));
  if LVersionNum = '23.0' then Result := '12.1'
  else if LVersionNum = '22.0' then Result := '11.0'
  else if LVersionNum = '21.0' then Result := '10.4'
  else if LVersionNum = '20.0' then Result := '10.3'
  else if LVersionNum = '19.0' then Result := '10.2'
  else if LVersionNum = '18.0' then Result := '10.1'
  else if LVersionNum = '17.0' then Result := '10.0'
  else Result := LVersionNum;
end;

function TBuildServiceAdapter.BuildProject(const AProjectPath: string): TBuildMetrics;
var
  LDelphiPath: string;
  LBdsExe: string;
  LBdsCmd: string;
  LErrFile: string;
  LRegEntry: string;
  LOutput: string;
begin
  Result := Default(TBuildMetrics);
  if not Assigned(FEnvService) then
    raise Exception.Create('Delphi Environment Service is not assigned.');

  LDelphiPath := FEnvService.ResolveDelphiPath(AProjectPath);
  if LDelphiPath = '' then
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
  LRegEntry := '$atropos-ce-tmp\' + TGuid.NewGuid.ToString;
  LBdsCmd := Format('"%s" -b -ns -o"%s" -r"%s" "%s"', [LBdsExe, LErrFile, LRegEntry, AProjectPath]);

  if Assigned(FLogger) then FLogger.Log('Executing Build via bds.exe (Universal Compiler): ' + LBdsCmd);

  if RunCmdAndCaptureOutput(LBdsCmd, LOutput) then
  begin
    if TFile.Exists(LErrFile) then
    begin
      LOutput := TFile.ReadAllText(LErrFile);
      TFile.Delete(LErrFile);
      Result := ParseBuildOutput(LOutput, AProjectPath);
      Result.DelphiVersion := GetDelphiFriendlyName(LDelphiPath);
    end
    else
    begin
      Result.Success := False;
      Result.ErrorMessage := 'Failed to read bds.exe error file output.';
    end;
  end
  else
  begin
    Result.Success := False;
    Result.ErrorMessage := 'Failed to execute bds.exe process.';
  end;
end;

end.
