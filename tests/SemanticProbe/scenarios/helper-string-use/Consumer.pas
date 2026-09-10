unit Consumer;
interface
uses ProbeHelpers;
implementation
function Run(Value: string): string; begin Result := Value.Twist; end;
end.
