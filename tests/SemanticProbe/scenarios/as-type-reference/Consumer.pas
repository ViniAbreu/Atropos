unit Consumer;
interface
uses ProbeDep;
implementation
procedure Run(Value:TObject); var Item:TItem; begin Item:=Value as TItem; end;
end.
