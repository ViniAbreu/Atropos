unit Consumer;
interface
{$DEFINE PROBE_FEATURE}
{$UNDEF PROBE_FEATURE}
uses {$IFDEF PROBE_FEATURE} ProbeDep {$ELSE} ProbeOther {$ENDIF};
implementation

end.
