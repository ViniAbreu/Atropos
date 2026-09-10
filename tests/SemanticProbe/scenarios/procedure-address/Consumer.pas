unit Consumer;
interface
uses ProbeDep;
implementation
var Callback: Pointer;
procedure Run; begin Callback := @CallMe; end;
end.
