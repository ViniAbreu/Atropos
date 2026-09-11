unit Lifecycle.Consumer;
interface
uses Lifecycle.Provider, Lifecycle.Unused, Lifecycle.Bridge, Lifecycle.Helpers;
procedure PrintMain;
implementation
procedure PrintMain;
var Value: string;
begin
  Value := '';
  Writeln(Value.TraceLabel);
end;
initialization
  Boot;
finalization
  Shutdown;
end.
