unit Atropos.Application.Factory;

interface
uses
  Atropos.Application.AppService, Atropos.Core.Config;

type
  TAppServiceFactory = class
  public
    class function CreateDefault(const AConfig: TToolConfig): TProjectCleanerAppService;
  end;

implementation
uses
  Atropos.Core.Ports, Atropos.Adapters.ProjectParser, Atropos.Adapters.DelphiAST, Atropos.Adapters.FileSystem, Atropos.Adapters.ReportGenerator, Atropos.Adapters.ExternalUnitResolver, Atropos.Adapters.DelphiEnvironment;

class function TAppServiceFactory.CreateDefault(const AConfig: TToolConfig): TProjectCleanerAppService;
var
  LASTParser: IASTParser;
begin
  LASTParser := TDelphiASTAdapter.Create;
  
  Result := TProjectCleanerAppService.Create(
    TDprojParserAdapter.Create,
    LASTParser,
    TFileSystemAdapter.Create,
    TReportGeneratorAdapter.Create,
    TDelphiEnvironmentAdapter.Create,
    TExternalUnitResolverAdapter.Create(LASTParser),
    AConfig
  );
end;

end.

