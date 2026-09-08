unit Atropos.App.CLI;

interface

uses
  Atropos.Core.Config,
  Atropos.Core.Ports;

type
  TCLIOutput = TLogEvent;
  TCLIFileExists = reference to function(const APath: string): Boolean;
  TCLIExecute = reference to function(const AProjectPath: string;
    const AConfig: TToolConfig; const AOnLog: TCLIOutput): Boolean;

  TCLIApp = class
  private
    class procedure ShowUsage(const AOutput: TCLIOutput); static;
    class procedure ConsoleOutput(const AMessage: string); static;
    class function DefaultFileExists(const APath: string): Boolean; static;
    class function DefaultExecute(const AProjectPath: string;
      const AConfig: TToolConfig; const AOnLog: TCLIOutput): Boolean; static;
  public
    function Run: Integer;
    class function RunWith(const AArgs: TArray<string>;
      const AOutput: TCLIOutput; const AFileExists: TCLIFileExists;
      const AExecute: TCLIExecute): Integer; static;
  end;

implementation
uses System.SysUtils, System.IOUtils, Atropos.Application.Factory,
  Atropos.Application.AppService, Atropos.Application.CommandLine;

class procedure TCLIApp.ShowUsage(const AOutput: TCLIOutput);
begin
  AOutput('Atropos CLI v1.0');
  AOutput('Usage: AtroposCLI -dproj <path_to_dproj> [options]');
  AOutput('Options:');
  AOutput('  --remove   Remove unused units');
  AOutput('  --move     Move units to implementation uses clause if applicable');
  AOutput('  -html      Export report to HTML');
  AOutput('  -txt       Export report to TXT');
  AOutput('  --output   Directory for generated reports (project directory by default)');
  AOutput('  --dry-run  Report candidates without modifying source files');
  AOutput('  --target   Build target as Configuration|Platform; may be repeated');
  AOutput('  --debug    Enable verbose debug logging');
  AOutput('  --help     Show this help');
end;

class procedure TCLIApp.ConsoleOutput(const AMessage: string);
begin
  Writeln(AMessage);
end;

class function TCLIApp.DefaultFileExists(const APath: string): Boolean;
begin
  Result := TFile.Exists(APath);
end;

class function TCLIApp.DefaultExecute(const AProjectPath: string;
  const AConfig: TToolConfig; const AOnLog: TCLIOutput): Boolean;
var
  LAppService: TProjectCleanerAppService;
begin
  LAppService := TAppServiceFactory.CreateDefault(AConfig);
  try
    LAppService.OnLog := AOnLog;
    Result := LAppService.Execute(AProjectPath);
  finally
    LAppService.Free;
  end;
end;

function TCLIApp.Run: Integer;
var
  LArgs: TArray<string>;
  I: Integer;
begin
  SetLength(LArgs, ParamCount);
  for I := 1 to ParamCount do
    LArgs[I - 1] := ParamStr(I);
  Result := RunWith(LArgs, ConsoleOutput, DefaultFileExists, DefaultExecute);
end;

class function TCLIApp.RunWith(const AArgs: TArray<string>;
  const AOutput: TCLIOutput; const AFileExists: TCLIFileExists;
  const AExecute: TCLIExecute): Integer;
var
  LOptions: TCommandLineOptions;
begin
  Result := 1;
  try
    LOptions := TCommandLineParser.Parse(AArgs);
    if not LOptions.IsValid then
    begin
      AOutput('Error: ' + LOptions.ErrorMessage);
      ShowUsage(AOutput);
      Exit(2);
    end;

    if LOptions.ShowHelp then
    begin
      ShowUsage(AOutput);
      Exit(0);
    end;

    if not AFileExists(LOptions.ProjectPath) then
    begin
      AOutput('Error: Project file not found -> ' + LOptions.ProjectPath);
      Exit(2);
    end;

    if AExecute(LOptions.ProjectPath, LOptions.Config, AOutput) then
      Result := 0;
  except
    on E: Exception do
    begin
      AOutput('Critical Error: ' + E.Message);
      Result := 1;
    end;
  end;
end;

end.
