unit Consumer;
interface
uses ProbeDep;
implementation
procedure Run; begin {$IFDEF PROBE_NEVER_DEFINED}CallMe;{$ENDIF} end;
end.
