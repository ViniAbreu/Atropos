unit Consumer;
interface
{$DEFINE PROBE_FEATURE}
uses {$IF DEFINED(PROBE_FEATURE)} ProbeDep {$ELSE} ProbeOther {$IFEND};
implementation
procedure Run; begin CallMe; end;
end.
