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
uses Atropos.Adapters.BuildCapability, Atropos.Adapters.BuildService,
  Atropos.Adapters.DelphiEnvironment, Atropos.Adapters.ExternalUnitResolver,
  Atropos.Adapters.ReportGenerator, Atropos.Adapters.FileSystem,
  Atropos.Adapters.DelphiAST, Atropos.Adapters.ProjectParser;

class function TAppServiceFactory.CreateDefault(const AConfig: TToolConfig;
  const AShouldCancel: TCancellationCheck): TProjectCleanerAppService;
var
  LASTParser: IASTParser;
  LEnvService: IDelphiEnvironmentService;
  LBuildProcessRunner: IBuildProcessRunner;
begin
  LASTParser := TDelphiASTAdapter.Create;
  LEnvService := TDelphiEnvironmentAdapter.Create;
  LBuildProcessRunner := TWin32BuildProcessRunner.Create;
  
  Result := TProjectCleanerAppService.Create(
    TDprojParserAdapter.Create,
    LASTParser,
    TFileSystemAdapter.Create,
    TReportGeneratorAdapter.Create,
    LEnvService,
    TExternalUnitResolverAdapter.Create(LASTParser),
    TBuildServiceAdapter.Create(LEnvService, nil, LBuildProcessRunner, 600000,
      AShouldCancel,
      TDelphiBuildCapabilityDetector.Create(LBuildProcessRunner)),
    AConfig,
    AShouldCancel
  );
end;

end.
