unit Atropos.Application.CommandLine;

interface

uses
  Atropos.Core.Config,
  Atropos.Core.Ports;

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
  LBuildTarget: TBuildTarget;
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
      Inc(I);
      Continue;
    end;
    if SameText(LArg, '--remove') then
    begin
      Result.Config.RemoveUnused := True;
      Inc(I);
      Continue;
    end;
    if SameText(LArg, '--move') then
    begin
      Result.Config.MoveToImplementation := True;
      Inc(I);
      Continue;
    end;
    if SameText(LArg, '--debug') then
    begin
      Result.Config.EnableDebug := True;
      Inc(I);
      Continue;
    end;
    if SameText(LArg, '--dry-run') then
    begin
      Result.Config.DryRun := True;
      Inc(I);
      Continue;
    end;
    if SameText(LArg, '--target') then
    begin
      if I + 1 >= Length(AArgs) then
      begin
        Result.ErrorMessage := 'Missing value after --target.';
        Exit;
      end;
      Inc(I);
      if not TBuildTarget.TryParse(AArgs[I], LBuildTarget) then
      begin
        Result.ErrorMessage := 'Invalid --target. Use Configuration|Platform.';
        Exit;
      end;
      Result.Config.AddBuildTarget(LBuildTarget);
      Inc(I);
      Continue;
    end;
    if SameText(LArg, '-html') then
    begin
      Result.Config.ExportHTML := True;
      Inc(I);
      Continue;
    end;
    if SameText(LArg, '-txt') then
    begin
      Result.Config.ExportTXT := True;
      Inc(I);
      Continue;
    end;
    if SameText(LArg, '--output') then
    begin
      if I + 1 >= Length(AArgs) then
      begin
        Result.ErrorMessage := 'Missing value after --output.';
        Exit;
      end;
      Inc(I);
      Result.Config.OutputDirectory := AArgs[I];
      Inc(I);
      Continue;
    end;
    if SameText(LArg, '--help') or SameText(LArg, '-h') or
      SameText(LArg, '/?') then
    begin
      Result.ShowHelp := True;
      Inc(I);
      Continue;
    end;
    Result.ErrorMessage := 'Unknown option: ' + LArg;
    Exit;
  end;

  if Result.ProjectPath.IsEmpty and not Result.ShowHelp then
    Result.ErrorMessage := 'The -dproj option is required.';
end;

end.
