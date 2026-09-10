unit ProbeStringOverload;
interface
function Choose(const Value: string): string; overload;
implementation
function Choose(const Value: string): string; begin Result := Value; end;
end.
