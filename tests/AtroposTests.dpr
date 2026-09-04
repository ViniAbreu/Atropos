program AtroposTests;

{$IFNDEF TESTINSIGHT}
{$APPTYPE CONSOLE}
{$ENDIF}

{$STRONGLINKTYPES ON}
uses
  System.SysUtils,
  {$IFDEF TESTINSIGHT}
  TestInsight.DUnitX,
  {$ENDIF }
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,
  Atropos.Tests.Sample in 'src\Atropos.Tests.Sample.pas',
  Atropos.Tests.Domain in 'src\Atropos.Tests.Domain.pas',
  Atropos.Core.Domain in '..\src\Core\Domain\Atropos.Core.Domain.pas',
  Atropos.Core.Config in '..\src\Core\Domain\Atropos.Core.Config.pas',
  Atropos.Adapters.Logger in '..\src\Adapters\Logger\Atropos.Adapters.Logger.pas',
  Atropos.Core.Ports in '..\src\Core\Ports\Atropos.Core.Ports.pas',
  Atropos.Adapters.ProjectParser in '..\src\Adapters\ProjectParser\Atropos.Adapters.ProjectParser.pas',
  Atropos.Tests.DprojParser in 'src\Atropos.Tests.DprojParser.pas',
  Atropos.Adapters.DelphiAST in '..\src\Adapters\DelphiAST\Atropos.Adapters.DelphiAST.pas',
  Atropos.Tests.DelphiASTAdapter in 'src\Atropos.Tests.DelphiASTAdapter.pas',
  Atropos.Tests.CompilerDirectives in 'src\Atropos.Tests.CompilerDirectives.pas',
  Atropos.Adapters.FileSystem in '..\src\Adapters\FileSystem\Atropos.Adapters.FileSystem.pas',
  Atropos.Tests.FileSystem in 'src\Atropos.Tests.FileSystem.pas',
  Atropos.Core.Modifier in '..\src\Core\Services\Atropos.Core.Modifier.pas',
  Atropos.Tests.Modifier in 'src\Atropos.Tests.Modifier.pas',
  Atropos.Adapters.ReportGenerator in '..\src\Adapters\ReportGenerator\Atropos.Adapters.ReportGenerator.pas',
  Atropos.Tests.ReportGenerator in 'src\Atropos.Tests.ReportGenerator.pas',
  Atropos.Adapters.ExternalUnitResolver in '..\src\Adapters\ExternalUnitResolver\Atropos.Adapters.ExternalUnitResolver.pas',
  Atropos.Tests.ExternalResolver in 'src\Atropos.Tests.ExternalResolver.pas',
  Atropos.Tests.Integration in 'src\Atropos.Tests.Integration.pas',
  Atropos.Adapters.DelphiEnvironment in '..\src\Adapters\DelphiEnvironment\Atropos.Adapters.DelphiEnvironment.pas',
  Atropos.Tests.DelphiEnvironment in 'src\Atropos.Tests.DelphiEnvironment.pas',
  Atropos.Application.AppService in '..\src\Application\Atropos.Application.AppService.pas',
  Atropos.Adapters.BuildService in '..\src\Adapters\BuildService\Atropos.Adapters.BuildService.pas',
  Atropos.Tests.BuildReliability in 'src\Atropos.Tests.BuildReliability.pas',
  Atropos.Tests.ProjectResolution in 'src\Atropos.Tests.ProjectResolution.pas',
  Atropos.Application.ExecutionConfig in '..\src\Application\Atropos.Application.ExecutionConfig.pas',
  Atropos.Tests.ExecutionConfig in 'src\Atropos.Tests.ExecutionConfig.pas',
  Atropos.Application.ExecutionLifecycle in '..\src\Application\Atropos.Application.ExecutionLifecycle.pas',
  Atropos.Tests.ExecutionLifecycle in 'src\Atropos.Tests.ExecutionLifecycle.pas',
  Atropos.Application.CommandLine in '..\src\Application\Atropos.Application.CommandLine.pas',
  Atropos.Tests.CommandLine in 'src\Atropos.Tests.CommandLine.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;
  Logger: ITestLogger;
  NUnitLogger: ITestLogger;
begin
{$IFDEF TESTINSIGHT}
  TestInsight.DUnitX.RunRegisteredTests;
  Exit;
{$ENDIF}
  try
    TDUnitX.CheckCommandLine;
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := False;

    if TDUnitX.Options.ConsoleMode <> TDunitXConsoleMode.Off then
    begin
      Logger := TDUnitXConsoleLogger.Create(TDUnitX.Options.ConsoleMode = TDunitXConsoleMode.Quiet);
      Runner.AddLogger(Logger);
    end;

    NUnitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);

    Runner.AddLogger(NUnitLogger);
    Runner.FailsOnNoAsserts := False;

    Results := Runner.Execute;
    if not Results.AllPassed then
      ExitCode := EXIT_ERRORS;

    {$IFNDEF CI}
    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      Write('Done.. press <Enter> key to quit.');
      Readln;
    end;
    {$ENDIF}
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.

