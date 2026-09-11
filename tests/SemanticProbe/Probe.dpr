program Probe;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  Atropos.Core.Profiling in '..\..\src\Core\Services\Atropos.Core.Profiling.pas',
  Atropos.Core.Ports in '..\..\src\Core\Ports\Atropos.Core.Ports.pas',
  Atropos.Core.Analysis in '..\..\src\Core\Domain\Atropos.Core.Analysis.pas',
  Atropos.Core.AnalysisIntersection in '..\..\src\Core\Domain\Atropos.Core.AnalysisIntersection.pas',
  Atropos.Core.Effects in '..\..\src\Core\Domain\Atropos.Core.Effects.pas',
  Atropos.Core.UnitSymbols in '..\..\src\Core\Domain\Atropos.Core.UnitSymbols.pas',
  Atropos.Core.HelperBinding in '..\..\src\Core\Domain\Atropos.Core.HelperBinding.pas',
  Atropos.Core.LocalBinding in '..\..\src\Core\Domain\Atropos.Core.LocalBinding.pas',
  Atropos.Core.TypeNames in '..\..\src\Core\Domain\Atropos.Core.TypeNames.pas',
  Atropos.Core.Compilation in '..\..\src\Core\Domain\Atropos.Core.Compilation.pas',
  Atropos.Core.Domain in '..\..\src\Core\Domain\Atropos.Core.Domain.pas',
  Atropos.Core.Config in '..\..\src\Core\Domain\Atropos.Core.Config.pas',
  Atropos.Core.Modifier in '..\..\src\Core\Services\Atropos.Core.Modifier.pas',
  Atropos.Core.SourceTokens in '..\..\src\Core\Services\Atropos.Core.SourceTokens.pas',
  Atropos.Core.UsesSyntax in '..\..\src\Core\Services\Atropos.Core.UsesSyntax.pas',
  Atropos.Core.UsesEditor in '..\..\src\Core\Services\Atropos.Core.UsesEditor.pas',
  Atropos.Core.UsesEditPlan in '..\..\src\Core\Services\Atropos.Core.UsesEditPlan.pas',
  Atropos.Adapters.DelphiSource in '..\..\src\Adapters\DelphiAST\Atropos.Adapters.DelphiSource.pas',
  Atropos.Adapters.SourceIncludes in '..\..\src\Adapters\DelphiAST\Atropos.Adapters.SourceIncludes.pas',
  Atropos.Adapters.SourceSnapshot in '..\..\src\Adapters\DelphiAST\Atropos.Adapters.SourceSnapshot.pas',
  Atropos.Adapters.DelphiAST in '..\..\src\Adapters\DelphiAST\Atropos.Adapters.DelphiAST.pas',
  Atropos.Adapters.ContextSyntaxBuilder in '..\..\src\Adapters\DelphiAST\Atropos.Adapters.ContextSyntaxBuilder.pas',
  Atropos.Adapters.ConditionalExpression in '..\..\src\Adapters\DelphiAST\Atropos.Adapters.ConditionalExpression.pas',
  Atropos.Adapters.ConditionalSource in '..\..\src\Adapters\DelphiAST\Atropos.Adapters.ConditionalSource.pas',
  Atropos.Adapters.ConditionalImports in '..\..\src\Adapters\DelphiAST\Atropos.Adapters.ConditionalImports.pas',
  Atropos.Adapters.SyntaxFacts in '..\..\src\Adapters\DelphiAST\Atropos.Adapters.SyntaxFacts.pas',
  Atropos.Adapters.HelperFacts in '..\..\src\Adapters\DelphiAST\Atropos.Adapters.HelperFacts.pas',
  Atropos.Adapters.MemberReferences in '..\..\src\Adapters\DelphiAST\Atropos.Adapters.MemberReferences.pas',
  Atropos.Adapters.SymbolFacts in '..\..\src\Adapters\DelphiAST\Atropos.Adapters.SymbolFacts.pas',
  Atropos.Adapters.ExportFacts in '..\..\src\Adapters\DelphiAST\Atropos.Adapters.ExportFacts.pas',
  Atropos.Adapters.ImplicitEffects in '..\..\src\Adapters\DelphiAST\Atropos.Adapters.ImplicitEffects.pas',
  Atropos.Adapters.SyntaxBuilder in '..\..\src\Adapters\DelphiAST\Atropos.Adapters.SyntaxBuilder.pas',
  Atropos.Adapters.ExternalUnitResolver in '..\..\src\Adapters\ExternalUnitResolver\Atropos.Adapters.ExternalUnitResolver.pas',
  Atropos.Adapters.UnitDependencies in '..\..\src\Adapters\ExternalUnitResolver\Atropos.Adapters.UnitDependencies.pas',
  Atropos.Adapters.TargetResolver in '..\..\src\Adapters\ExternalUnitResolver\Atropos.Adapters.TargetResolver.pas',
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
