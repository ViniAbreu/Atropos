program AtroposCLI;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  Atropos.App.CLI in 'src\CLI\Atropos.App.CLI.pas',
  Atropos.Application.CommandLine in 'src\Application\Atropos.Application.CommandLine.pas',
  Atropos.Core.Ports in 'src\Core\Ports\Atropos.Core.Ports.pas',
  Atropos.Core.Analysis in 'src\Core\Domain\Atropos.Core.Analysis.pas',
  Atropos.Core.Domain in 'src\Core\Domain\Atropos.Core.Domain.pas',
  Atropos.Core.Config in 'src\Core\Domain\Atropos.Core.Config.pas',
  Atropos.Adapters.Logger in 'src\Adapters\Logger\Atropos.Adapters.Logger.pas',
  Atropos.Core.Modifier in 'src\Core\Services\Atropos.Core.Modifier.pas',
  Atropos.Adapters.ProjectParser in 'src\Adapters\ProjectParser\Atropos.Adapters.ProjectParser.pas',
  Atropos.Adapters.DelphiSource in 'src\Adapters\DelphiAST\Atropos.Adapters.DelphiSource.pas',
  Atropos.Adapters.SourceIncludes in 'src\Adapters\DelphiAST\Atropos.Adapters.SourceIncludes.pas',
  Atropos.Adapters.SourceSnapshot in 'src\Adapters\DelphiAST\Atropos.Adapters.SourceSnapshot.pas',
  Atropos.Adapters.DelphiAST in 'src\Adapters\DelphiAST\Atropos.Adapters.DelphiAST.pas',
  Atropos.Adapters.FileSystem in 'src\Adapters\FileSystem\Atropos.Adapters.FileSystem.pas',
  Atropos.Adapters.FileTransaction in 'src\Adapters\FileSystem\Atropos.Adapters.FileTransaction.pas',
  Atropos.Adapters.ReportGenerator in 'src\Adapters\ReportGenerator\Atropos.Adapters.ReportGenerator.pas',
  Atropos.Adapters.ExternalUnitResolver in 'src\Adapters\ExternalUnitResolver\Atropos.Adapters.ExternalUnitResolver.pas',
  Atropos.Adapters.DelphiEnvironment in 'src\Adapters\DelphiEnvironment\Atropos.Adapters.DelphiEnvironment.pas',
  Atropos.Application.AppService in 'src\Application\Atropos.Application.AppService.pas',
  Atropos.Application.AnalysisPlan in 'src\Application\Atropos.Application.AnalysisPlan.pas',
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

