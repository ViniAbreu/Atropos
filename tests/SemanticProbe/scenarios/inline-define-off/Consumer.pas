unit Consumer;
interface
{$UNDEF PROBE_FEATURE}
uses {$IFDEF PROBE_FEATURE} ProbeDep {$ELSE} ProbeOther {$ENDIF};
implementation

end.
