unit Lifecycle.Helpers;
interface
type
  TTraceHelper = record helper for string
    function TraceLabel: string;
  end;
implementation
function TTraceHelper.TraceLabel: string;
begin
  Result := 'Main' + Self;
end;
end.
