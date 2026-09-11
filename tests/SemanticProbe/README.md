# Semantic regression baseline

This standalone instrument runs the real Atropos AST adapter, dependency domain,
source resolver and uses modifier against the research catalog. It characterizes
current behavior without changing the engine or treating known failures as success.

## Run

From the repository root, initialize the pinned DelphiAST submodule, then use:

```powershell
git submodule update --init third_party/DelphiAST
.\tests\SemanticProbe\tests\Runner.Tests.ps1
.\tests\SemanticProbe\Run-Probe.ps1 -ValidateOnly
.\tests\SemanticProbe\Build-Probe.ps1 -Platform Win32 -Configuration Base
.\tests\SemanticProbe\Run-Probe.ps1
.\tests\SemanticProbe\Build-Probe.ps1 -Platform Win64 -Configuration Base
.\tests\SemanticProbe\Run-Probe.ps1 -Executable .\tests\SemanticProbe\bin\Win64\Base\Probe.exe
```

The build script defaults to RAD Studio 12 at its standard Windows installation
path. Override `-BdsPath` for a different installation. Project source paths are
relative and use the repository submodule. Base matches the research configuration;
Debug and Release are available but must be recorded as distinct runs. The compiled
program reports compiler version and pointer size. The build manifest binds its
binary hash to source hashes, configuration and Git revisions. The runner rejects
a changed binary or source snapshot; always rebuild after source changes.

Filter with `-Category helpers` or `-Case qualified-call`. Use `-Repeat 10` for repeated
observations, and `-Baseline path/to/summary.json` for status comparison. The default
comparison is the portable historical extract in `baselines/research-20260909.json`.
Timings are descriptive, include no application builds and are not project benchmarks.

Every execution writes a new ignored `results` directory with requests, observations,
JSON/CSV summaries and provenance. Binary outputs are ignored too. Compact versioned
baselines retain individual statuses and failed expectations; local full runs retain
all extracted identifiers and edited text. No input fixture is edited: rewrite cases
use the real modifier with an in-memory file service. Input hashes are checked again
after execution.

Exit codes: 0 means all selected cases passed; 1 means functional FAIL; 2 means
infrastructure ERROR; 3 means only PASS/BLOCKED with at least one BLOCKED. ERROR has
precedence over FAIL, then BLOCKED. A current full run is expected to return 1; do not
mask this exit code in the product quality gate or relabel failures as passing tests.
The runner is an explicit baseline workflow, not an automatically green gate.

## Provenance and unchanged expectations

The catalog and all scenario inputs are copied byte-for-byte from the research dated
2026-09-09. The catalog hash is
`65E7C43439DB73EB04688868820090631BBDB6E991DB3BBEE0A8D90F25D4550A`.
There are 134 executable scenarios and 18 explicitly blocked integration scenarios.
The historical extract stores the SHA-256 of the original summary and retains every
scenario status. It does not claim the historical binary has been rebuilt.

The migrated instrument removes obsolete absolute paths, the duplicate DelphiAST
clone, synthetic legacy inspection mode and the independent raw AST dump. That dump
used a second parser invocation with different input handling; it was not the tree
used for the decision. Observations here come from the actual adapter. Process output
is drained asynchronously so a full output pipe cannot stall the child before exit.
Source-hash validation replaces the old timestamp-only stale-binary check.

Most cases explicitly register provider exports parsed from real PAS files. Only
`resolver=true` cases test source discovery. Rewrite plans are supplied independently
to isolate editing from dependency decisions. Negative parser cases have explicit
error expectations. Some fixtures intentionally contain invalid or unsupported syntax
and must not be added to an application project for compilation.

BLOCKED cases document untested project, runtime, cache and filesystem properties.
Existing product tests cover portions of these areas, but this does not automatically
promote the corresponding research oracle. A passing AST fixture does not demonstrate
unchanged overload selection, helper precedence, initialization order or dynamic use.

## Gaps exposed beyond existing mocks

The recorded Base runs using compiler version 36.0 reproduce the historical status
of every case on both Win32 and Win64: 96 PASS, 38 FAIL, 0 ERROR and 18 BLOCKED.
See the individual assertions and provenance in
[Win32 baseline](baselines/current-20260909-Win32.json) and
[Win64 baseline](baselines/current-20260909-Win64.json).
The instrument was built from the working tree; production sources match commit
7c0fd88. Source hashes identify the exact instrument revision independently of that
commit. These observations do not establish coverage across every build configuration.

| Failing category | FAIL |
|---|---:|
| scope | 10 |
| lifecycle | 7 |
| includes | 5 |
| helpers | 4 |
| generics | 3 |
| enums | 2 |
| directives | 2 |
| rewrite | 2 |
| qualification | 1 |
| ambiguity | 1 |
| advanced (attribute) | 1 |

The scope count includes anonymous-parameter-shadow, where the parser rejects the
fixture syntax before analysis. A functional FAIL is not necessarily a wrong decision
after successful parsing. The existing DUnitX suite also passed on both architectures;
its different coverage does not negate these research failures.

- `helper-export`, `helper-public-export`, `helper-string-use` and `helper-class-use`
  exercise real metadata extraction. The existing domain helper test injects !HELPER
  metadata, so it cannot prove this pipeline works.
- `qualified-call` tests real extraction of a qualified call. The existing domain
  qualification test supplies an already joined qualified identifier.
- `keep-native-effects` recorded a conflict with the former native-initialization
  domain test. The conservative policy now protects known native initialization
  effects too; the historical baseline remains unchanged.

Every future correction must name affected case IDs, preserve unrelated regressions
and justify any policy/oracle revision. Do not derive expectations from current output.

### Anonymous-method compiler contract

The historical `anonymous-parameter-shadow` input declares a local variable as
`var Work: reference to procedure(...)`. Delphi compiler 36.0 rejects that exact
source on both Win32 and Win64 with E2003 for `reference`. Its historical expectation
of successful parsing therefore conflicts with the selected compiler; the preserved
catalog still reports FAIL and is not rewritten to improve the count.

`tests/run-anonymous-smoke-test.ps1` compiles temporary copies of that original input
and provider and requires the specific rejection. The separate AnonymousConsole
fixture uses a named `reference to` type, which the compiler accepts. It checks
parameter shadowing, local/global captures and an outer reference after the closure
before and after optimization. SymbolBinding tests also cover sibling closures and
anonymous-function result types. These additional contracts do not change historical
case IDs, input hashes, expected outcomes or PASS/FAIL totals.

## Source include increment

Source-relative and nested includes now load through the production adapter. Probe
observations expose `includedSources` with parent, resolved path and SHA-256 of the
bytes read. Explicit include paths are supported by the adapter constructor; project
evaluation still needs to supply those paths and the correct compiler context.

`include-declaration`, `include-reference` and `missing-include` now pass.
`include-uses` and `include-nested` extract their contents but retain imports with an
incomplete-analysis reason: editing include provenance is not implemented yet.
Their removal expectations remain unchanged and therefore remain FAIL. Guarded
recursive includes are conservatively rejected. DUnitX additionally covers nested
provenance, path precedence, inactive missing includes, cycles, repeat includes,
content hashes and multiline literal punctuation in root and included sources.

The subsequent analysis-plan increment is exercised by
`Atropos.Tests.AnalysisSnapshot`: it tests the application boundary between planning
and writing, shared provider/include byte validation, cancellation and dry-run.
Probe runs use the parser directly and do not by themselves demonstrate that
application ordering or snapshot validation. These tests do not promote the blocked
project-context or persistent-cache scenarios.
