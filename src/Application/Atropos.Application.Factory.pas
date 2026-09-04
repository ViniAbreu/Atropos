unit Atropos.Application.Factory;

interface
uses
  Atropos.Application.AppService,
  Atropos.Core.Config,
  Atropos.Core.Ports;

type
  TAppServiceFactory = class
  public
    class function CreateDefault(const AConfig: TToolConfig;
      const AShouldCancel: TCancellationCheck = nil): TProjectCleanerAppService;
  end;

implementation
uses Atropos.Adapters.BuildService, Atropos.Adapters.DelphiEnvironment, Atropos.Adapters.ExternalUnitResolver, Atropos.Adapters.ReportGenerator, Atropos.Adapters.FileSystem, Atropos.Adapters.DelphiAST, Atropos.Adapters.ProjectParser;

class function TAppServiceFactory.CreateDefault(const AConfig: TToolConfig;
  const AShouldCancel: TCancellationCheck): TProjectCleanerAppService;
var
  LASTParser: IASTParser;
  LEnvService: IDelphiEnvironmentService;
begin
  LASTParser := TDelphiASTAdapter.Create;
  LEnvService := TDelphiEnvironmentAdapter.Create;
  
  Result := TProjectCleanerAppService.Create(
    TDprojParserAdapter.Create,
    LASTParser,
    TFileSystemAdapter.Create,
    TReportGeneratorAdapter.Create,
    LEnvService,
    TExternalUnitResolverAdapter.Create(LASTParser),
    TBuildServiceAdapter.Create(LEnvService, nil, nil, 600000, AShouldCancel),
    AConfig,
    AShouldCancel
  );
end;

end.
