program Probe;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  Atropos.Core.Ports in '..\..\src\Core\Ports\Atropos.Core.Ports.pas',
  Atropos.Core.Domain in '..\..\src\Core\Domain\Atropos.Core.Domain.pas',
  Atropos.Core.Config in '..\..\src\Core\Domain\Atropos.Core.Config.pas',
  Atropos.Core.Modifier in '..\..\src\Core\Services\Atropos.Core.Modifier.pas',
  Atropos.Adapters.DelphiAST in '..\..\src\Adapters\DelphiAST\Atropos.Adapters.DelphiAST.pas',
  Atropos.Adapters.ExternalUnitResolver in '..\..\src\Adapters\ExternalUnitResolver\Atropos.Adapters.ExternalUnitResolver.pas',
  Probe.Json in 'src\Probe.Json.pas',
  Probe.MemoryFile in 'src\Probe.MemoryFile.pas',
  Probe.Engine in 'src\Probe.Engine.pas';

procedure RunCase;
var Request: TJSONObject; Observation: TJSONObject; Engine: TProbeEngine;
begin
  if ParamCount <> 3 then
    raise Exception.Create('Usage: Probe --case request.json observation.json');
  Request := TJSONObject.ParseJSONValue(TFile.ReadAllText(ParamStr(2))) as TJSONObject;
  if not Assigned(Request) then
    raise Exception.Create('Invalid request JSON');
  Engine := TProbeEngine.Create;
  try
    Observation := Engine.Execute(Request);
    try
      TFile.WriteAllText(ParamStr(3), Observation.ToJSON, TEncoding.UTF8);
    finally
      Observation.Free;
    end;
  finally
    Engine.Free;
    Request.Free;
  end;
end;

procedure PrintBuildInfo;
var
  BuildInfo: TJSONObject;
begin
  BuildInfo := TJSONObject.Create;
  try
    BuildInfo.AddPair('compilerVersion', TJSONNumber.Create(CompilerVersion));
    BuildInfo.AddPair('pointerSize', TJSONNumber.Create(SizeOf(Pointer)));
    BuildInfo.AddPair('platform', 'Win32');
    {$IFDEF WIN64}
    BuildInfo.RemovePair('platform').Free;
    BuildInfo.AddPair('platform', 'Win64');
    {$ENDIF}
    Writeln(BuildInfo.ToJSON);
  finally
    BuildInfo.Free;
  end;
end;

procedure Run;
begin
  if SameText(ParamStr(1), '--build-info') then
  begin
    PrintBuildInfo;
    Exit;
  end;
  if SameText(ParamStr(1), '--protocol') then
  begin
    Writeln('2');
    Exit;
  end;
  if SameText(ParamStr(1), '--case') then
  begin
    RunCase;
    Exit;
  end;
  if ParamCount = 0 then
  begin
    Writeln('Suite: powershell -File tests\SemanticProbe\Run-Probe.ps1');
    Writeln('Probe --case request.json observation.json');
    Exit;
  end;
  raise Exception.Create('Unknown argument: ' + ParamStr(1));
end;

begin
  try
    Run;
  except
    on Failure: Exception do
    begin
      Writeln(Failure.ClassName, ': ', Failure.Message);
      ExitCode := 2;
    end;
  end;
  // Preserve a readable IDE console without blocking automated runs.
  if DebugHook <> 0 then
    Readln;
end.
