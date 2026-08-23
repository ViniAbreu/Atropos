unit Atropos.App.CLI;

interface
uses
  Atropos.Core.Config;

type
  TCLIApp = class
  private
    FDprojPath: string;
    procedure ParseParams(var AConfig: TToolConfig);
  public
    procedure Run;
  end;

implementation
uses System.SysUtils, System.IOUtils, Atropos.Application.Factory,
  Atropos.Application.AppService;

procedure TCLIApp.ParseParams(var AConfig: TToolConfig);
var
  i: Integer;
  LParam: string;
begin
  for i := 1 to ParamCount do
  begin
    LParam := ParamStr(i);
    
    if SameText(LParam, '-dproj') and (i < ParamCount) then
    begin
      FDprojPath := ParamStr(i + 1);
      Continue;
    end;
    
    if SameText(LParam, '--remove') then
    begin
      AConfig.RemoveUnused := True;
      Continue;
    end;
    
    if SameText(LParam, '--move') then
    begin
      AConfig.MoveToImplementation := True;
      Continue;
    end;
    
    if SameText(LParam, '--debug') then
    begin
      AConfig.EnableDebug := True;
      Continue;
    end;
    
    if SameText(LParam, '-html') then
    begin
      AConfig.ExportHTML := True;
      Continue;
    end;
    
    if SameText(LParam, '-txt') then
    begin
      AConfig.ExportTXT := True;
      Continue;
    end;
  end;
end;

procedure TCLIApp.Run;
var
  LAppService: TProjectCleanerAppService;
  LConfig: TToolConfig;
begin
  try
    LConfig := TToolConfig.Default;
    ParseParams(LConfig);
    
    if FDprojPath.IsEmpty then
    begin
      Writeln('Atropos CLI v1.0');
      Writeln('Usage: AtroposCLI -dproj <path_to_dproj> [options]');
      Writeln('Options:');
      Writeln('  --remove   Remove unused units');
      Writeln('  --move     Move units to implementation uses clause if applicable');
      Writeln('  -html          Export report to HTML');
      Writeln('  -txt           Export report to TXT');
      Writeln('  --debug        Enable verbose debug logging');
      Exit;
    end;

    if not TFile.Exists(FDprojPath) then
    begin
      Writeln('Error: Project file not found -> ', FDprojPath);
      Exit;
    end;

    LAppService := TAppServiceFactory.CreateDefault(LConfig);
    try
      LAppService.OnLog := procedure(const AMsg: string)
        begin
          Writeln(AMsg);
        end;
      
      LAppService.Execute(FDprojPath);
    finally
      LAppService.Free;
    end;
    
  except
    on E: Exception do
      Writeln('Critical Error: ', E.Message);
  end;
end;

end.
