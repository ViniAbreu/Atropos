unit Atropos.Adapters.Logger;

interface
uses
  Atropos.Core.Ports;

type
  TLogEvent = reference to procedure(const AMsg: string);

  TAppLogger = class(TInterfacedObject, ILogger)
  private
    FOnLog: TLogEvent;
  public
    constructor Create(const AOnLog: TLogEvent);
    procedure Log(const AMsg: string);
  end;

implementation


constructor TAppLogger.Create(const AOnLog: TLogEvent);
begin
  FOnLog := AOnLog;
end;

procedure TAppLogger.Log(const AMsg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(AMsg);
end;

end.
