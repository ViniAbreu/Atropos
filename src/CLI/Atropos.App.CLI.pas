unit Atropos.App.CLI;

interface
type
  TCLIApp = class
  private
    procedure ShowUsage;
  public
    function Run: Integer;
  end;

implementation
uses System.SysUtils, System.IOUtils, Atropos.Application.Factory,
  Atropos.Application.AppService, Atropos.Application.CommandLine;

procedure TCLIApp.ShowUsage;
begin
  Writeln('Atropos CLI v1.0');
  Writeln('Usage: AtroposCLI -dproj <path_to_dproj> [options]');
  Writeln('Options:');
  Writeln('  --remove   Remove unused units');
  Writeln('  --move     Move units to implementation uses clause if applicable');
  Writeln('  -html      Export report to HTML');
  Writeln('  -txt       Export report to TXT');
  Writeln('  --debug    Enable verbose debug logging');
  Writeln('  --help     Show this help');
end;

function TCLIApp.Run: Integer;
var
  LAppService: TProjectCleanerAppService;
  LOptions: TCommandLineOptions;
  LArgs: TArray<string>;
  I: Integer;
begin
  Result := 1;
  try
    SetLength(LArgs, ParamCount);
    for I := 1 to ParamCount do
      LArgs[I - 1] := ParamStr(I);
    LOptions := TCommandLineParser.Parse(LArgs);

    if not LOptions.IsValid then
    begin
      Writeln('Error: ', LOptions.ErrorMessage);
      ShowUsage;
      Exit(2);
    end;

    if LOptions.ShowHelp then
    begin
      ShowUsage;
      Exit(0);
    end;

    if not TFile.Exists(LOptions.ProjectPath) then
    begin
      Writeln('Error: Project file not found -> ', LOptions.ProjectPath);
      Exit(2);
    end;

    LAppService := TAppServiceFactory.CreateDefault(LOptions.Config);
    try
      LAppService.OnLog := procedure(const AMsg: string)
        begin
          Writeln(AMsg);
        end;
      
      if LAppService.Execute(LOptions.ProjectPath) then
        Result := 0;
    finally
      LAppService.Free;
    end;
    
  except
    on E: Exception do
    begin
      Writeln('Critical Error: ', E.Message);
      Result := 1;
    end;
  end;
end;

end.
