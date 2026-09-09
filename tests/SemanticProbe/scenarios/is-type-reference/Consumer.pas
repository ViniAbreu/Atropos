unit Consumer;
interface
uses ProbeDep;
implementation
function Run(Value:TObject):Boolean; begin Result:=Value is TItem; end;
end.
