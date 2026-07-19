program AtroposCLI;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  Atropos.App.CLI in 'src\CLI\Atropos.App.CLI.pas',
  Atropos.Core.Ports in 'src\Core\Ports\Atropos.Core.Ports.pas',
  Atropos.Core.Domain in 'src\Core\Domain\Atropos.Core.Domain.pas',
  Atropos.Core.Modifier in 'src\Core\Services\Atropos.Core.Modifier.pas',
  Atropos.Adapters.ProjectParser in 'src\Adapters\ProjectParser\Atropos.Adapters.ProjectParser.pas',
  Atropos.Adapters.DelphiAST in 'src\Adapters\DelphiAST\Atropos.Adapters.DelphiAST.pas',
  Atropos.Adapters.FileSystem in 'src\Adapters\FileSystem\Atropos.Adapters.FileSystem.pas',
  Atropos.Adapters.ReportGenerator in 'src\Adapters\ReportGenerator\Atropos.Adapters.ReportGenerator.pas',
  Atropos.Adapters.ExternalUnitResolver in 'src\Adapters\ExternalUnitResolver\Atropos.Adapters.ExternalUnitResolver.pas',
  Atropos.Adapters.DelphiEnvironment in 'src\Adapters\DelphiEnvironment\Atropos.Adapters.DelphiEnvironment.pas',
  Atropos.Application.AppService in 'src\Application\Atropos.Application.AppService.pas',
  Atropos.Application.Factory in 'src\Application\Atropos.Application.Factory.pas';

 var
  LApp: TCLIApp;
begin
  try
    LApp := TCLIApp.Create;
    try
      LApp.Run;
    finally
      LApp.Free;
    end;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.

