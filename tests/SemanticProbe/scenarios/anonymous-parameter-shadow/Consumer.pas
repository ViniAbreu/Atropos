unit Consumer;
interface
uses ProbeDep;
implementation
procedure Run; var Work: reference to procedure(Clash: Integer);
begin Work := procedure(Clash: Integer) begin Inc(Clash); end; end;
end.
