unit Lifecycle.Consumer;
interface
uses Lifecycle.Provider, Lifecycle.Unused, Lifecycle.Bridge, Lifecycle.Helpers;
procedure PrintMain;
implementation
procedure PrintMain;
var Value: string; Clash: Integer;
begin
  Clash := 0;
  Inc(Clash);
  if Clash <> 1 then
    Halt(1);
  Value := '';
  Writeln(Value.TraceLabel);
end;
initialization
  Boot;
finalization
  Shutdown;
end.
