unit Atropos.Adapters.BuildService;

interface
uses
  Atropos.Core.Ports, System.SysUtils;

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
uses System.Classes, System.Generics.Collections, System.IOUtils, System.RegularExpressions,
  Winapi.Windows;

constructor TBuildServiceAdapter.Create(AEnvService: IDelphiEnvironmentService; ALogger: ILogger = nil);
begin
  FEnvService := AEnvService;
  FLogger := ALogger;
end;

function TBuildServiceAdapter.RunCmdAndCaptureOutput(const ACmd: string; out AOutput: string): Boolean;
var
  LSecurityAttributes: TSecurityAttributes;
  LReadPipe: THandle;
  LWritePipe: THandle;
  LStartupInfo: TStartupInfo;
  LProcessInfo: TProcessInformation;
  LBuffer: array[0..4095] of AnsiChar;
  LBytesRead: DWORD;
  LOutputStream: TStringStream;
  LMutableCmd: string;
begin
  Result := False;
  AOutput := EmptyStr;

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

  Result.Success :=
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
  LRegEntry := '$atropos-ce-tmp\' + TGuid.NewGuid.ToString;
  LBdsCmd := Format('"%s" -b -ns -o"%s" -r"%s" "%s"', [LBdsExe, LErrFile, LRegEntry, AProjectPath]);

  if Assigned(FLogger) then FLogger.Log('Executing Build via bds.exe (Universal Compiler): ' + LBdsCmd);

  LStartTick := GetTickCount64;
  if not RunCmdAndCaptureOutput(LBdsCmd, LOutput) then
  begin
    Result.Success := False;
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
  TFile.Delete(LErrFile);
  Result := ParseBuildOutput(LOutput, AProjectPath);
  Result.DelphiVersion := GetDelphiFriendlyName(LDelphiPath);
  Result.CompileTimeMs := Int64(GetTickCount64 - LStartTick);
end;

end.

