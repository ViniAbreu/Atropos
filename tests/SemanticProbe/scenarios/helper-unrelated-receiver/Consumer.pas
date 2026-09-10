unit Consumer;
interface
uses ProbeHelpers;
type TLocal = class function Twist: string; end;
implementation
function TLocal.Twist: string; begin Result := ''; end;
function Run(Value: TLocal): string; begin Result := Value.Twist; end;
end.
