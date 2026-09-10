unit Atropos.Application.Logger;

interface

uses Atropos.Core.Ports;

type
  TApplicationLogger = class(TInterfacedObject, ILogger)
  private
    FOnLog: TLogEvent;
  public
    constructor Create(const AOnLog: TLogEvent);
    procedure Log(const AMsg: string);
  end;

implementation

constructor TApplicationLogger.Create(const AOnLog: TLogEvent);
begin
  FOnLog := AOnLog;
end;

procedure TApplicationLogger.Log(const AMsg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(AMsg);
end;

end.
