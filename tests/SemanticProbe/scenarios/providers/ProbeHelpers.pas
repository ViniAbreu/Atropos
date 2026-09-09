unit ProbeHelpers;
interface
type TStringTool = record helper for string
  function Twist: string;
end;
implementation
function TStringTool.Twist: string; begin Result := Self; end;
end.
