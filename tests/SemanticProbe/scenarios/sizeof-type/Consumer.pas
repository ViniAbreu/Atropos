unit Consumer;
interface
uses ProbeDep;
implementation
function Run:Integer; begin Result:=SizeOf(TRec); end;
end.
