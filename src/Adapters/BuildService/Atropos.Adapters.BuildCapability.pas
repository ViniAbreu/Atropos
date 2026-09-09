unit Atropos.Adapters.BuildCapability;

interface
uses Atropos.Adapters.BuildService;

type
  TDelphiBuildCapabilityDetector = class(TInterfacedObject,
    IBuildCapabilityDetector)
  private
    FProcessRunner: IBuildProcessRunner;
    FDetectedDelphiPath: string;
    FHasDetected: Boolean;
    FSupportsHeadlessMSBuild: Boolean;
    function CompileProbe(const ADelphiPath, ACompilerPath: string): Boolean;
    function DetectHeadlessMSBuild(const ADelphiPath: string): Boolean;
  public
    constructor Create(const AProcessRunner: IBuildProcessRunner);
    function SupportsHeadlessMSBuild(const ADelphiPath: string): Boolean;
  end;

implementation
uses System.IOUtils, System.SysUtils;

constructor TDelphiBuildCapabilityDetector.Create(
  const AProcessRunner: IBuildProcessRunner);
begin
  FProcessRunner := AProcessRunner;
end;

function TDelphiBuildCapabilityDetector.CompileProbe(const ADelphiPath,
  ACompilerPath: string): Boolean;
var
  LCancelled: Boolean;
  LCommand: string;
  LCompilerOutput: string;
  LExitCode: Cardinal;
  LProbeDirectory: string;
  LProbeSource: string;
  LRsVarsPath: string;
  LTimedOut: Boolean;
begin
  LProbeDirectory := TPath.Combine(TPath.GetTempPath,
    'Atropos-compiler-probe-' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(LProbeDirectory);
  try
    LProbeSource := TPath.Combine(LProbeDirectory, 'AtroposCompilerProbe.dpr');
    LRsVarsPath := TPath.Combine(ADelphiPath, 'bin\rsvars.bat');
    TFile.WriteAllText(LProbeSource,
      'program AtroposCompilerProbe;' + sLineBreak + 'begin' + sLineBreak +
      'end.');
    LCommand := Format('"%s" /d /c ""%s" && "%s" -B -Q -E"%s" ' +
      '-N"%s" "%s""', [GetEnvironmentVariable('ComSpec'), LRsVarsPath,
      ACompilerPath, LProbeDirectory, LProbeDirectory, LProbeSource]);
    Result := FProcessRunner.Execute(LCommand, 30000, nil, LCompilerOutput,
      LExitCode, LTimedOut, LCancelled) and (LExitCode = 0) and
      not LTimedOut and not LCancelled;
  finally
    TDirectory.Delete(LProbeDirectory, True);
  end;
end;

function TDelphiBuildCapabilityDetector.DetectHeadlessMSBuild(
  const ADelphiPath: string): Boolean;
var
  LCompilerPath: string;
  LMSBuildPath: string;
  LRsVarsPath: string;
begin
  Result := False;
  LRsVarsPath := TPath.Combine(ADelphiPath, 'bin\rsvars.bat');
  if not TFile.Exists(LRsVarsPath) then
    Exit;
  LMSBuildPath := TPath.Combine(GetEnvironmentVariable('WINDIR'),
    'Microsoft.NET\Framework\v4.0.30319\MSBuild.exe');
  if not TFile.Exists(LMSBuildPath) then
    Exit;
  LCompilerPath := TPath.Combine(ADelphiPath, 'bin\dcc32.exe');
  if not TFile.Exists(LCompilerPath) then
    Exit;
  Result := Assigned(FProcessRunner) and CompileProbe(ADelphiPath,
    LCompilerPath);
end;

function TDelphiBuildCapabilityDetector.SupportsHeadlessMSBuild(
  const ADelphiPath: string): Boolean;
begin
  if FHasDetected and SameText(FDetectedDelphiPath, ADelphiPath) then
  begin
    Result := FSupportsHeadlessMSBuild;
    Exit;
  end;
  FDetectedDelphiPath := ADelphiPath;
  FSupportsHeadlessMSBuild := DetectHeadlessMSBuild(ADelphiPath);
  FHasDetected := True;
  Result := FSupportsHeadlessMSBuild;
end;

end.
