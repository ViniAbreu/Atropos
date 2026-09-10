unit Atropos.Adapters.DelphiPowerShell;

interface

type
  TDelphiPowerShell = class
  private
    class procedure ValidatePath(const APath: string); static;
  public
    class function Command(const AScriptPath, ADelphiPath: string): string; static;
  end;

implementation

uses System.SysUtils, System.IOUtils;

class procedure TDelphiPowerShell.ValidatePath(const APath: string);
var LCharacter: Char;
begin
  for LCharacter in APath do
    if CharInSet(LCharacter, ['"', '%', '!', '&', '|', '<', '>', '^', #10, #13]) then
      raise EArgumentException.Create('Unsupported character in evaluation tool path.');
end;

class function TDelphiPowerShell.Command(const AScriptPath, ADelphiPath: string): string;
var LEnvironment, LWindows, LShell, LPowerShell: string;
begin
  LEnvironment := TPath.Combine(ADelphiPath, 'bin\rsvars.bat');
  LWindows := GetEnvironmentVariable('SystemRoot');
  LShell := TPath.Combine(LWindows, 'System32\cmd.exe');
  LPowerShell := TPath.Combine(LWindows, 'System32\WindowsPowerShell\v1.0\powershell.exe');
  ValidatePath(LEnvironment);
  ValidatePath(AScriptPath);
  ValidatePath(LShell);
  ValidatePath(LPowerShell);
  if not TFile.Exists(LEnvironment) then
    raise EFileNotFoundException.Create('Delphi environment script not found: ' + LEnvironment);
  if not TFile.Exists(LPowerShell) then
    raise EFileNotFoundException.Create('Windows PowerShell is unavailable.');
  Result := Format('"%s" /d /c ""%s" && "%s" -NoProfile -NonInteractive -File "%s""',
    [LShell, LEnvironment, LPowerShell, AScriptPath]);
end;

end.
