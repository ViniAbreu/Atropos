unit Atropos.Adapters.Logger;

interface

uses
  Atropos.Core.Ports;

type
  TAppLogger = class(TInterfacedObject, ILogger)
  private
    FOnLog: TLogEvent;
    FFilePath: string;
    procedure AppendToFile(const AMessage: string);
    class function CreateDefaultFilePath: string; static;
  public
    constructor Create(const AOnLog: TLogEvent;
      const AFilePath: string = '');
    class function CreatePersistent(const AOnLog: TLogEvent;
      const AFilePath: string = ''): TAppLogger; static;
    procedure Log(const AMsg: string);
    property FilePath: string read FFilePath;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils;

constructor TAppLogger.Create(const AOnLog: TLogEvent;
  const AFilePath: string);
begin
  FOnLog := AOnLog;
  FFilePath := AFilePath;
end;

class function TAppLogger.CreatePersistent(const AOnLog: TLogEvent;
  const AFilePath: string): TAppLogger;
var
  LPersistentPath: string;
begin
  LPersistentPath := AFilePath;
  if LPersistentPath.IsEmpty then
    LPersistentPath := CreateDefaultFilePath;
  Result := TAppLogger.Create(AOnLog, LPersistentPath);
end;

procedure TAppLogger.Log(const AMsg: string);
begin
  AppendToFile(AMsg);
  if Assigned(FOnLog) then
    FOnLog(AMsg);
end;

procedure TAppLogger.AppendToFile(const AMessage: string);
var
  LDirectory: string;
  LLine: string;
begin
  if FFilePath.IsEmpty then
    Exit;
  try
    LDirectory := TPath.GetDirectoryName(FFilePath);
    if not LDirectory.IsEmpty then
      TDirectory.CreateDirectory(LDirectory);
    LLine := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' ' +
      AMessage + sLineBreak;
    TFile.AppendAllText(FFilePath, LLine, TEncoding.UTF8);
  except
    FFilePath := '';
  end;
end;

class function TAppLogger.CreateDefaultFilePath: string;
var
  LBaseDirectory: string;
  LIdentifier: string;
begin
  LBaseDirectory := GetEnvironmentVariable('LOCALAPPDATA');
  if LBaseDirectory.IsEmpty then
    LBaseDirectory := TPath.GetTempPath;
  LIdentifier := TGuid.NewGuid.ToString;
  LIdentifier := LIdentifier.Replace('{', '');
  LIdentifier := LIdentifier.Replace('}', '');
  Result := TPath.Combine(LBaseDirectory, 'Atropos\Logs\Atropos-' +
    FormatDateTime('yyyymmdd-hhnnss-zzz', Now) + '-' + LIdentifier + '.log');
end;

end.
