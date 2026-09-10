unit ProbeOverloads;
interface
function Choose(Value: Integer): Integer; overload;
implementation
function Choose(Value: Integer): Integer; begin Result := Value; end;
end.
