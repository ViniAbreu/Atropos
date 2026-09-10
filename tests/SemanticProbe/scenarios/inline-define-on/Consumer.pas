unit Consumer;
interface
{$DEFINE PROBE_FEATURE}
uses {$IFDEF PROBE_FEATURE} ProbeDep {$ELSE} ProbeOther {$ENDIF};
implementation
procedure Run; begin CallMe; end;
end.
