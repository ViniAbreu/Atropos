unit Lifecycle.Consumer;
interface
uses Lifecycle.Provider, Lifecycle.Unused, Lifecycle.Bridge, Lifecycle.Helpers, Lifecycle.Managed,
  Lifecycle.TypeChecks;
procedure PrintMain;
implementation
procedure PrintMain;
var Value: string; Clash: Integer;
begin
  CheckTypes;
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
