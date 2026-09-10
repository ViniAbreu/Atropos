unit Semantic.Calls;
interface
uses Semantic.Overloads, Semantic.Fallback, Semantic.Unused;
procedure RunCalls;
implementation
procedure RunCalls;
begin
  Writeln(Pick(7));
  Writeln(Pick('seven'));
end;
end.
