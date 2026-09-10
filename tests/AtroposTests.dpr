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
  Atropos.Tests.Presentation in 'src\Atropos.Tests.Presentation.pas',
  Atropos.App.CLI in '..\src\CLI\Atropos.App.CLI.pas',
  Atropos.Application.Factory in '..\src\Application\Atropos.Application.Factory.pas',
  Atropos.Tests.Domain in 'src\Atropos.Tests.Domain.pas',
  Atropos.Core.Analysis in '..\src\Core\Domain\Atropos.Core.Analysis.pas',
  Atropos.Core.AnalysisIntersection in '..\src\Core\Domain\Atropos.Core.AnalysisIntersection.pas',
  Atropos.Core.Effects in '..\src\Core\Domain\Atropos.Core.Effects.pas',
  Atropos.Core.UnitSymbols in '..\src\Core\Domain\Atropos.Core.UnitSymbols.pas',
  Atropos.Core.HelperBinding in '..\src\Core\Domain\Atropos.Core.HelperBinding.pas',
  Atropos.Core.LocalBinding in '..\src\Core\Domain\Atropos.Core.LocalBinding.pas',
  Atropos.Core.TypeNames in '..\src\Core\Domain\Atropos.Core.TypeNames.pas',
  Atropos.Core.Compilation in '..\src\Core\Domain\Atropos.Core.Compilation.pas',
  Atropos.Tests.AnalysisDecisions in 'src\Atropos.Tests.AnalysisDecisions.pas',
  Atropos.Tests.SourceIncludes in 'src\Atropos.Tests.SourceIncludes.pas',
  Atropos.Tests.ConditionalImports in 'src\Atropos.Tests.ConditionalImports.pas',
  Atropos.Tests.Profiling in 'src\Atropos.Tests.Profiling.pas',
  Atropos.Core.Profiling in '..\src\Core\Services\Atropos.Core.Profiling.pas',
  Atropos.Tests.CacheLifecycle in 'src\Atropos.Tests.CacheLifecycle.pas',
  Atropos.Tests.CancellationTransaction in 'src\Atropos.Tests.CancellationTransaction.pas',
  Atropos.Tests.AnalysisSnapshot in 'src\Atropos.Tests.AnalysisSnapshot.pas',
  Atropos.Tests.ProjectContext in 'src\Atropos.Tests.ProjectContext.pas',
  Atropos.Tests.CompilerTraceProcess in 'src\Atropos.Tests.CompilerTraceProcess.pas',
  Atropos.Tests.CompilerDependencySources in 'src\Atropos.Tests.CompilerDependencySources.pas',
  Atropos.Tests.TargetAnalysis in 'src\Atropos.Tests.TargetAnalysis.pas',
  Atropos.Tests.EffectGraph in 'src\Atropos.Tests.EffectGraph.pas',
  Atropos.Core.Domain in '..\src\Core\Domain\Atropos.Core.Domain.pas',
  Atropos.Core.Config in '..\src\Core\Domain\Atropos.Core.Config.pas',
  Atropos.Adapters.Logger in '..\src\Adapters\Logger\Atropos.Adapters.Logger.pas',
  Atropos.Core.Ports in '..\src\Core\Ports\Atropos.Core.Ports.pas',
  Atropos.Adapters.ProjectParser in '..\src\Adapters\ProjectParser\Atropos.Adapters.ProjectParser.pas',
  Atropos.Adapters.ProjectContext in '..\src\Adapters\ProjectParser\Atropos.Adapters.ProjectContext.pas',
  Atropos.Adapters.CompilerDependencies in '..\src\Adapters\ProjectParser\Atropos.Adapters.CompilerDependencies.pas',
  Atropos.Adapters.CompilerContextSignature in '..\src\Adapters\ProjectParser\Atropos.Adapters.CompilerContextSignature.pas',
  Atropos.Adapters.CompilerTraceScript in '..\src\Adapters\ProjectParser\Atropos.Adapters.CompilerTraceScript.pas',
  Atropos.Adapters.CompilerTraceProcess in '..\src\Adapters\ProjectParser\Atropos.Adapters.CompilerTraceProcess.pas',
  Atropos.Adapters.DelphiPowerShell in '..\src\Adapters\BuildService\Atropos.Adapters.DelphiPowerShell.pas',
  Atropos.Adapters.CompilerSymbols in '..\src\Adapters\ProjectParser\Atropos.Adapters.CompilerSymbols.pas',
  Atropos.Adapters.TargetAnalysisFactory in '..\src\Adapters\ProjectParser\Atropos.Adapters.TargetAnalysisFactory.pas',
  Atropos.Adapters.ProjectSourceMappings in '..\src\Adapters\ProjectParser\Atropos.Adapters.ProjectSourceMappings.pas',
  Atropos.Adapters.ProjectEvaluationScript in '..\src\Adapters\ProjectParser\Atropos.Adapters.ProjectEvaluationScript.pas',
  Atropos.Tests.DprojParser in 'src\Atropos.Tests.DprojParser.pas',
  Atropos.Adapters.DelphiSource in '..\src\Adapters\DelphiAST\Atropos.Adapters.DelphiSource.pas',
  Atropos.Adapters.SourceIncludes in '..\src\Adapters\DelphiAST\Atropos.Adapters.SourceIncludes.pas',
  Atropos.Adapters.SourceSnapshot in '..\src\Adapters\DelphiAST\Atropos.Adapters.SourceSnapshot.pas',
  Atropos.Adapters.DelphiAST in '..\src\Adapters\DelphiAST\Atropos.Adapters.DelphiAST.pas',
  Atropos.Adapters.ContextSyntaxBuilder in '..\src\Adapters\DelphiAST\Atropos.Adapters.ContextSyntaxBuilder.pas',
  Atropos.Adapters.ConditionalExpression in '..\src\Adapters\DelphiAST\Atropos.Adapters.ConditionalExpression.pas',
  Atropos.Adapters.CompilerBranchTrace in '..\src\Adapters\DelphiAST\Atropos.Adapters.CompilerBranchTrace.pas',
  Atropos.Adapters.TracedIncludes in '..\src\Adapters\DelphiAST\Atropos.Adapters.TracedIncludes.pas',
  Atropos.Adapters.CompilerPreparation in '..\src\Adapters\DelphiAST\Atropos.Adapters.CompilerPreparation.pas',
  Atropos.Adapters.CompilerInputs in '..\src\Adapters\DelphiAST\Atropos.Adapters.CompilerInputs.pas',
  Atropos.Adapters.CompilerSourceInputs in '..\src\Adapters\DelphiAST\Atropos.Adapters.CompilerSourceInputs.pas',
  Atropos.Adapters.NativeSourcePreparer in '..\src\Adapters\DelphiAST\Atropos.Adapters.NativeSourcePreparer.pas',
  Atropos.Adapters.ConditionalSource in '..\src\Adapters\DelphiAST\Atropos.Adapters.ConditionalSource.pas',
  Atropos.Adapters.ConditionalImports in '..\src\Adapters\DelphiAST\Atropos.Adapters.ConditionalImports.pas',
  Atropos.Adapters.SyntaxFacts in '..\src\Adapters\DelphiAST\Atropos.Adapters.SyntaxFacts.pas',
  Atropos.Adapters.HelperFacts in '..\src\Adapters\DelphiAST\Atropos.Adapters.HelperFacts.pas',
  Atropos.Adapters.MemberReferences in '..\src\Adapters\DelphiAST\Atropos.Adapters.MemberReferences.pas',
  Atropos.Adapters.SymbolFacts in '..\src\Adapters\DelphiAST\Atropos.Adapters.SymbolFacts.pas',
  Atropos.Adapters.ExportFacts in '..\src\Adapters\DelphiAST\Atropos.Adapters.ExportFacts.pas',
  Atropos.Adapters.ImplicitEffects in '..\src\Adapters\DelphiAST\Atropos.Adapters.ImplicitEffects.pas',
  Atropos.Adapters.SyntaxBuilder in '..\src\Adapters\DelphiAST\Atropos.Adapters.SyntaxBuilder.pas',
  Atropos.Tests.DelphiASTAdapter in 'src\Atropos.Tests.DelphiASTAdapter.pas',
  Atropos.Tests.SymbolBinding in 'src\Atropos.Tests.SymbolBinding.pas',
  Atropos.Tests.TypeIdentity in 'src\Atropos.Tests.TypeIdentity.pas',
  Atropos.Tests.ImplicitEffects in 'src\Atropos.Tests.ImplicitEffects.pas',
  Atropos.Tests.CompilerDirectives in 'src\Atropos.Tests.CompilerDirectives.pas',
  Atropos.Tests.ConditionalEvaluation in 'src\Atropos.Tests.ConditionalEvaluation.pas',
  Atropos.Tests.CompilerBranchTrace in 'src\Atropos.Tests.CompilerBranchTrace.pas',
  Atropos.Tests.CompilerParser in 'src\Atropos.Tests.CompilerParser.pas',
  Atropos.Adapters.FileSystem in '..\src\Adapters\FileSystem\Atropos.Adapters.FileSystem.pas',
  Atropos.Adapters.SourceEncoding in '..\src\Adapters\FileSystem\Atropos.Adapters.SourceEncoding.pas',
  Atropos.Adapters.FileTransaction in '..\src\Adapters\FileSystem\Atropos.Adapters.FileTransaction.pas',
  Atropos.Tests.FileSystem in 'src\Atropos.Tests.FileSystem.pas',
  Atropos.Core.Modifier in '..\src\Core\Services\Atropos.Core.Modifier.pas',
  Atropos.Core.SourceTokens in '..\src\Core\Services\Atropos.Core.SourceTokens.pas',
  Atropos.Core.UsesSyntax in '..\src\Core\Services\Atropos.Core.UsesSyntax.pas',
  Atropos.Core.UsesEditor in '..\src\Core\Services\Atropos.Core.UsesEditor.pas',
  Atropos.Core.UsesEditPlan in '..\src\Core\Services\Atropos.Core.UsesEditPlan.pas',
  Atropos.Tests.Modifier in 'src\Atropos.Tests.Modifier.pas',
  Atropos.Tests.UsesEditing in 'src\Atropos.Tests.UsesEditing.pas',
  Atropos.Adapters.ReportGenerator in '..\src\Adapters\ReportGenerator\Atropos.Adapters.ReportGenerator.pas',
  Atropos.Tests.ReportGenerator in 'src\Atropos.Tests.ReportGenerator.pas',
  Atropos.Adapters.ExternalUnitResolver in '..\src\Adapters\ExternalUnitResolver\Atropos.Adapters.ExternalUnitResolver.pas',
  Atropos.Adapters.UnitDependencies in '..\src\Adapters\ExternalUnitResolver\Atropos.Adapters.UnitDependencies.pas',
  Atropos.Adapters.TargetResolver in '..\src\Adapters\ExternalUnitResolver\Atropos.Adapters.TargetResolver.pas',
  Atropos.Tests.ExternalResolver in 'src\Atropos.Tests.ExternalResolver.pas',
  Atropos.Tests.Integration in 'src\Atropos.Tests.Integration.pas',
  Atropos.Adapters.DelphiEnvironment in '..\src\Adapters\DelphiEnvironment\Atropos.Adapters.DelphiEnvironment.pas',
  Atropos.Tests.DelphiEnvironment in 'src\Atropos.Tests.DelphiEnvironment.pas',
  Atropos.Application.AppService in '..\src\Application\Atropos.Application.AppService.pas',
  Atropos.Application.AnalysisPlan in '..\src\Application\Atropos.Application.AnalysisPlan.pas',
  Atropos.Application.TargetAnalysis in '..\src\Application\Atropos.Application.TargetAnalysis.pas',
  Atropos.Application.Logger in '..\src\Application\Atropos.Application.Logger.pas',
  Atropos.Adapters.BuildService in '..\src\Adapters\BuildService\Atropos.Adapters.BuildService.pas',
  Atropos.Adapters.BuildArtifact in '..\src\Adapters\BuildService\Atropos.Adapters.BuildArtifact.pas',
  Atropos.Adapters.BuildCapability in '..\src\Adapters\BuildService\Atropos.Adapters.BuildCapability.pas',
  Atropos.Tests.BuildReliability in 'src\Atropos.Tests.BuildReliability.pas',
  Atropos.Tests.ProjectResolution in 'src\Atropos.Tests.ProjectResolution.pas',
  Atropos.Application.ExecutionConfig in '..\src\Application\Atropos.Application.ExecutionConfig.pas',
  Atropos.Tests.ExecutionConfig in 'src\Atropos.Tests.ExecutionConfig.pas',
  Atropos.Application.ExecutionLifecycle in '..\src\Application\Atropos.Application.ExecutionLifecycle.pas',
  Atropos.Application.ExecutionPresentation in '..\src\Application\Atropos.Application.ExecutionPresentation.pas',
  Atropos.Adapters.ExecutionThread in '..\src\Adapters\Execution\Atropos.Adapters.ExecutionThread.pas',
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

