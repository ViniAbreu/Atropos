unit Consumer; interface {$DEFINE PROBE_A} uses {$IF (DEFINED(PROBE_A) AND NOT DEFINED(PROBE_B))}ProbeDep{$ELSE}ProbeOther{$IFEND}; implementation end.
