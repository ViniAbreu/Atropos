unit Atropos.App.CLI;

interface


type
  TCLIApp = class
  private
    FDprojPath: string;
    procedure ParseParams;
  public
    procedure Run;
  end;

implementation
uses
  Atropos.Application.AppService, Atropos.Application.Factory, System.SysUtils, System.IOUtils;

procedure TCLIApp.ParseParams;
var
  i: Integer;
begin
  for i := 1 to ParamCount do
  begin
    if SameText(ParamStr(i), '-dproj') and (i < ParamCount) then
      FDprojPath := ParamStr(i + 1);
  end;
end;

procedure TCLIApp.Run;
var
  LAppService: TProjectCleanerAppService;
begin
  try
    ParseParams;
    
    if FDprojPath = '' then
    begin
      Writeln('Atropos CLI v1.0');
      Writeln('Usage: AtroposCLI -dproj <path_to_dproj>');
      Exit;
    end;

    if not TFile.Exists(FDprojPath) then
    begin
      Writeln('Error: Project file not found -> ', FDprojPath);
      Exit;
    end;

    LAppService := TAppServiceFactory.CreateDefault;
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


