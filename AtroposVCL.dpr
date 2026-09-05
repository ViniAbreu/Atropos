program AtroposVCL;

uses
  Vcl.Forms,
  Atropos.VCL.Main in 'src\GUI\Atropos.VCL.Main.pas' {MainForm},
  Atropos.Core.Ports in 'src\Core\Ports\Atropos.Core.Ports.pas',
  Atropos.Core.Domain in 'src\Core\Domain\Atropos.Core.Domain.pas',
  Atropos.Core.Config in 'src\Core\Domain\Atropos.Core.Config.pas',
  Atropos.Adapters.Logger in 'src\Adapters\Logger\Atropos.Adapters.Logger.pas',
  Atropos.Core.Modifier in 'src\Core\Services\Atropos.Core.Modifier.pas',
  Atropos.Adapters.ProjectParser in 'src\Adapters\ProjectParser\Atropos.Adapters.ProjectParser.pas',
  Atropos.Adapters.DelphiAST in 'src\Adapters\DelphiAST\Atropos.Adapters.DelphiAST.pas',
  Atropos.Adapters.FileSystem in 'src\Adapters\FileSystem\Atropos.Adapters.FileSystem.pas',
  Atropos.Adapters.ReportGenerator in 'src\Adapters\ReportGenerator\Atropos.Adapters.ReportGenerator.pas',
  Atropos.Adapters.ExternalUnitResolver in 'src\Adapters\ExternalUnitResolver\Atropos.Adapters.ExternalUnitResolver.pas',
  Atropos.Adapters.DelphiEnvironment in 'src\Adapters\DelphiEnvironment\Atropos.Adapters.DelphiEnvironment.pas',
  Atropos.Application.AppService in 'src\Application\Atropos.Application.AppService.pas',
  Atropos.Application.ExecutionConfig in 'src\Application\Atropos.Application.ExecutionConfig.pas',
  Atropos.Application.Factory in 'src\Application\Atropos.Application.Factory.pas',
  Atropos.Adapters.BuildService in 'src\Adapters\BuildService\Atropos.Adapters.BuildService.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.

