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
uses
  Atropos.Application.AppService, Atropos.Application.Factory, System.SysUtils, System.IOUtils;

procedure TCLIApp.ParseParams(var AConfig: TToolConfig);
var
  i: Integer;
  LParam: string;
begin
  for i := 1 to ParamCount do
  begin
    LParam := ParamStr(i);
    if SameText(LParam, '-dproj') and (i < ParamCount) then
      FDprojPath := ParamStr(i + 1)
    else if SameText(LParam, '--remove') then
      AConfig.RemoveUnused := True
    else if SameText(LParam, '--move') then
      AConfig.MoveToImplementation := True
    else if SameText(LParam, '--debug') then
      AConfig.EnableDebug := True
    else if SameText(LParam, '--format') then
      AConfig.FormatOneUnitPerLine := True
    else if SameText(LParam, '--sort') then
      AConfig.SortUsesAlphabetically := True;
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
    
    if FDprojPath = '' then
    begin
      Writeln('Atropos CLI v1.0');
      Writeln('Usage: AtroposCLI -dproj <path_to_dproj> [options]');
      Writeln('Options:');
      Writeln('  --remove   Remove unused units');
      Writeln('  --move     Move units to implementation uses clause if applicable');
      Writeln('  --format   Format uses clause one unit per line');
      Writeln('  --sort     Sort uses clause alphabetically');
      Writeln('  --debug    Enable verbose debug logging');
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


