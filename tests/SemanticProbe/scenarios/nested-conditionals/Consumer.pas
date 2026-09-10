unit Consumer;
interface
{$DEFINE PROBE_A}
{$DEFINE PROBE_B}
uses {$IFDEF PROBE_A}{$IFDEF PROBE_B}ProbeDep{$ELSE}ProbeOther{$ENDIF}{$ELSE}ProbeOther{$ENDIF};
implementation
procedure Run; begin CallMe; end;
end.
