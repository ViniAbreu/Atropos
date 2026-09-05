unit Atropos.Application.CommandLine;

interface

uses
  Atropos.Core.Config;

type
  TCommandLineOptions = record
    ProjectPath: string;
    Config: TToolConfig;
    ShowHelp: Boolean;
    ErrorMessage: string;
    function IsValid: Boolean;
  end;

  TCommandLineParser = class
  public
    class function Parse(const AArgs: TArray<string>): TCommandLineOptions; static;
  end;

implementation

uses
  System.SysUtils;

function TCommandLineOptions.IsValid: Boolean;
begin
  Result := ErrorMessage.IsEmpty;
end;

class function TCommandLineParser.Parse(const AArgs: TArray<string>): TCommandLineOptions;
var
  I: Integer;
  LArg: string;
begin
  Result := Default(TCommandLineOptions);
  Result.Config := TToolConfig.Default;
  I := 0;
  while I < Length(AArgs) do
  begin
    LArg := AArgs[I];
    if SameText(LArg, '-dproj') then
    begin
      if I + 1 >= Length(AArgs) then
      begin
        Result.ErrorMessage := 'Missing value after -dproj.';
        Exit;
      end;
      Inc(I);
      Result.ProjectPath := AArgs[I];
    end
    else if SameText(LArg, '--remove') then
      Result.Config.RemoveUnused := True
    else if SameText(LArg, '--move') then
      Result.Config.MoveToImplementation := True
    else if SameText(LArg, '--debug') then
      Result.Config.EnableDebug := True
    else if SameText(LArg, '-html') then
      Result.Config.ExportHTML := True
    else if SameText(LArg, '-txt') then
      Result.Config.ExportTXT := True
    else if SameText(LArg, '--output') then
    begin
      if I + 1 >= Length(AArgs) then
      begin
        Result.ErrorMessage := 'Missing value after --output.';
        Exit;
      end;
      Inc(I);
      Result.Config.OutputDirectory := AArgs[I];
    end
    else if SameText(LArg, '--help') or SameText(LArg, '-h') or SameText(LArg, '/?') then
      Result.ShowHelp := True
    else
    begin
      Result.ErrorMessage := 'Unknown option: ' + LArg;
      Exit;
    end;
    Inc(I);
  end;

  if Result.ProjectPath.IsEmpty and not Result.ShowHelp then
    Result.ErrorMessage := 'The -dproj option is required.';
end;

end.
