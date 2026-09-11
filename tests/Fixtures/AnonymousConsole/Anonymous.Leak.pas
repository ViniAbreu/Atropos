unit Anonymous.Leak;
interface
uses Anonymous.Shadow;
procedure RunLeak;
implementation
type TParamAction = reference to procedure(Clash: Integer);
procedure RunLeak;
var Action: TParamAction;
begin
  Action := procedure(Clash: Integer) begin Inc(Clash); end;
  Action(1);
  Writeln('Outside:', Clash);
end;
end.
