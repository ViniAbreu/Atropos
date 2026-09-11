unit Atropos.Adapters.BuildArtifact;

interface

uses Atropos.Core.Ports, Atropos.Core.Compilation;

type
  TBuildArtifact = class
  public
    class procedure UpdateSize(var AMetrics: TBuildMetrics;
      const AProvider: IProjectContextProvider; const AProject, ADelphiPath: string;
      const ATarget: TBuildTarget; const ALogger: ILogger); static;
  end;

implementation

uses System.SysUtils, System.IOUtils;

class procedure TBuildArtifact.UpdateSize(var AMetrics: TBuildMetrics;
  const AProvider: IProjectContextProvider; const AProject, ADelphiPath: string;
  const ATarget: TBuildTarget; const ALogger: ILogger);
var LContext: TProjectCompilationContext;
begin
  if not AMetrics.Success or not Assigned(AProvider) then Exit;
  AMetrics.ExeSizeBytes := 0;
  try
    LContext := AProvider.EvaluateProject(AProject, ADelphiPath, ATarget);
    if LContext.ExecutablePath.IsEmpty then Exit;
    if TFile.Exists(LContext.ExecutablePath) then
      AMetrics.ExeSizeBytes := TFile.GetSize(LContext.ExecutablePath);
  except
    on E: EAbort do raise;
    on E: Exception do
      if Assigned(ALogger) then
        ALogger.Log('Cannot determine executable size: ' + E.Message);
  end;
end;

end.
