program AtroposCLI;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  Atropos.App.CLI in 'src\CLI\Atropos.App.CLI.pas',
  Atropos.Application.CommandLine in 'src\Application\Atropos.Application.CommandLine.pas',
  Atropos.Core.Profiling in 'src\Core\Services\Atropos.Core.Profiling.pas',
  Atropos.Core.Ports in 'src\Core\Ports\Atropos.Core.Ports.pas',
  Atropos.Core.Analysis in 'src\Core\Domain\Atropos.Core.Analysis.pas',
  Atropos.Core.AnalysisIntersection in 'src\Core\Domain\Atropos.Core.AnalysisIntersection.pas',
  Atropos.Core.Effects in 'src\Core\Domain\Atropos.Core.Effects.pas',
  Atropos.Core.UnitSymbols in 'src\Core\Domain\Atropos.Core.UnitSymbols.pas',
  Atropos.Core.HelperBinding in 'src\Core\Domain\Atropos.Core.HelperBinding.pas',
  Atropos.Core.LocalBinding in 'src\Core\Domain\Atropos.Core.LocalBinding.pas',
  Atropos.Core.TypeNames in 'src\Core\Domain\Atropos.Core.TypeNames.pas',
  Atropos.Core.Compilation in 'src\Core\Domain\Atropos.Core.Compilation.pas',
  Atropos.Core.Domain in 'src\Core\Domain\Atropos.Core.Domain.pas',
  Atropos.Core.Config in 'src\Core\Domain\Atropos.Core.Config.pas',
  Atropos.Adapters.Logger in 'src\Adapters\Logger\Atropos.Adapters.Logger.pas',
  Atropos.Core.Modifier in 'src\Core\Services\Atropos.Core.Modifier.pas',
  Atropos.Core.SourceTokens in 'src\Core\Services\Atropos.Core.SourceTokens.pas',
  Atropos.Core.UsesSyntax in 'src\Core\Services\Atropos.Core.UsesSyntax.pas',
  Atropos.Core.UsesEditor in 'src\Core\Services\Atropos.Core.UsesEditor.pas',
  Atropos.Core.UsesEditPlan in 'src\Core\Services\Atropos.Core.UsesEditPlan.pas',
  Atropos.Adapters.ProjectParser in 'src\Adapters\ProjectParser\Atropos.Adapters.ProjectParser.pas',
  Atropos.Adapters.ProjectContext in 'src\Adapters\ProjectParser\Atropos.Adapters.ProjectContext.pas',
  Atropos.Adapters.CompilerSymbols in 'src\Adapters\ProjectParser\Atropos.Adapters.CompilerSymbols.pas',
  Atropos.Adapters.TargetAnalysisFactory in 'src\Adapters\ProjectParser\Atropos.Adapters.TargetAnalysisFactory.pas',
  Atropos.Adapters.ProjectSourceMappings in 'src\Adapters\ProjectParser\Atropos.Adapters.ProjectSourceMappings.pas',
  Atropos.Adapters.ProjectEvaluationScript in 'src\Adapters\ProjectParser\Atropos.Adapters.ProjectEvaluationScript.pas',
  Atropos.Adapters.DelphiSource in 'src\Adapters\DelphiAST\Atropos.Adapters.DelphiSource.pas',
  Atropos.Adapters.SourceIncludes in 'src\Adapters\DelphiAST\Atropos.Adapters.SourceIncludes.pas',
  Atropos.Adapters.SourceSnapshot in 'src\Adapters\DelphiAST\Atropos.Adapters.SourceSnapshot.pas',
  Atropos.Adapters.DelphiAST in 'src\Adapters\DelphiAST\Atropos.Adapters.DelphiAST.pas',
  Atropos.Adapters.ContextSyntaxBuilder in 'src\Adapters\DelphiAST\Atropos.Adapters.ContextSyntaxBuilder.pas',
  Atropos.Adapters.ConditionalExpression in 'src\Adapters\DelphiAST\Atropos.Adapters.ConditionalExpression.pas',
  Atropos.Adapters.ConditionalSource in 'src\Adapters\DelphiAST\Atropos.Adapters.ConditionalSource.pas',
  Atropos.Adapters.ConditionalImports in 'src\Adapters\DelphiAST\Atropos.Adapters.ConditionalImports.pas',
  Atropos.Adapters.SyntaxFacts in 'src\Adapters\DelphiAST\Atropos.Adapters.SyntaxFacts.pas',
  Atropos.Adapters.HelperFacts in 'src\Adapters\DelphiAST\Atropos.Adapters.HelperFacts.pas',
  Atropos.Adapters.MemberReferences in 'src\Adapters\DelphiAST\Atropos.Adapters.MemberReferences.pas',
  Atropos.Adapters.SymbolFacts in 'src\Adapters\DelphiAST\Atropos.Adapters.SymbolFacts.pas',
  Atropos.Adapters.ExportFacts in 'src\Adapters\DelphiAST\Atropos.Adapters.ExportFacts.pas',
  Atropos.Adapters.ImplicitEffects in 'src\Adapters\DelphiAST\Atropos.Adapters.ImplicitEffects.pas',
  Atropos.Adapters.SyntaxBuilder in 'src\Adapters\DelphiAST\Atropos.Adapters.SyntaxBuilder.pas',
  Atropos.Adapters.FileSystem in 'src\Adapters\FileSystem\Atropos.Adapters.FileSystem.pas',
  Atropos.Adapters.SourceEncoding in 'src\Adapters\FileSystem\Atropos.Adapters.SourceEncoding.pas',
  Atropos.Adapters.FileTransaction in 'src\Adapters\FileSystem\Atropos.Adapters.FileTransaction.pas',
  Atropos.Adapters.ReportGenerator in 'src\Adapters\ReportGenerator\Atropos.Adapters.ReportGenerator.pas',
  Atropos.Adapters.ExternalUnitResolver in 'src\Adapters\ExternalUnitResolver\Atropos.Adapters.ExternalUnitResolver.pas',
  Atropos.Adapters.UnitDependencies in 'src\Adapters\ExternalUnitResolver\Atropos.Adapters.UnitDependencies.pas',
  Atropos.Adapters.TargetResolver in 'src\Adapters\ExternalUnitResolver\Atropos.Adapters.TargetResolver.pas',
  Atropos.Adapters.DelphiEnvironment in 'src\Adapters\DelphiEnvironment\Atropos.Adapters.DelphiEnvironment.pas',
  Atropos.Application.AppService in 'src\Application\Atropos.Application.AppService.pas',
  Atropos.Application.AnalysisPlan in 'src\Application\Atropos.Application.AnalysisPlan.pas',
  Atropos.Application.TargetAnalysis in 'src\Application\Atropos.Application.TargetAnalysis.pas',
  Atropos.Application.Logger in 'src\Application\Atropos.Application.Logger.pas',
  Atropos.Application.Factory in 'src\Application\Atropos.Application.Factory.pas',
  Atropos.Adapters.BuildService in 'src\Adapters\BuildService\Atropos.Adapters.BuildService.pas',
  Atropos.Adapters.BuildCapability in 'src\Adapters\BuildService\Atropos.Adapters.BuildCapability.pas';

var
  LApp: TCLIApp;
begin
  try
    LApp := TCLIApp.Create;
    try
      ExitCode := LApp.Run;
    finally
      LApp.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.

