# Tests, coverage, and quality gates

The separate [semantic baseline](../tests/SemanticProbe/README.md) reproduces the
research catalog against the real parser and domain, preserving known functional
failures and blocked integration scenarios. It records source/binary hashes and
compiler identity, and intentionally returns a nonzero exit code while failures
remain. It is not part of the all-green quality gate.

`tests\AtroposTests.dproj` covers the domain, `.dproj` parsing, DelphiAST, resolution, files, modifier, reports, CLI behavior, application composition, logging, execution lifecycle, presentation state, builds, and integration.

```powershell
msbuild tests\AtroposTests.dproj /t:Build /p:Config=Debug /p:Platform=Win64
.\tests\Win64\Debug\AtroposTests.exe --consolemode:quiet
```

## Complete gate

For Win32 and Win64, the gate builds and runs DUnitX, builds CLI/VCL Release, and runs simulated real-use smoke tests. It then measures Win32 coverage and enforces both the aggregate threshold and a 60% minimum for every instrumented unit. The per-unit floor prevents highly covered units from concealing a local regression.

```powershell
.\tests\run-quality-gates.ps1 `
  -BdsVersion '23.0' `
  -CodeCoveragePath 'D:\Tools\DelphiCodeCoverage\CodeCoverage.exe' `
  -MinimumLineCoverage 85
```

The smoke test verifies the PE architecture, copies the fixture, runs the CLI, removes a dependency, generates a report, and confirms that the original fixture remains unchanged. It explicitly requests the `Debug|Win32` and `Debug|Win64` targets, validating the user-configured matrix.

The gate also runs the projects under `tests\Fixtures` on both architectures. The console fixture covers namespaces, `in` aliases, conditionals, and initialization/finalization; the VCL fixture builds a real DFM form. Each run uses a temporary directory and confirms that versioned fixtures remain unchanged.

Coverage instruments all testable Core, Application, CLI, and Adapter units. The VCL form and program entry points are intentionally excluded from line coverage because they require a Windows message loop or process startup. Their logic is kept in the instrumented execution-presentation model, while executable wiring, PE architecture, CLI startup, and real VCL project handling are validated by the Win32/Win64 build and smoke gates. Generated code and the vendored DelphiAST implementation are also excluded; the Atropos DelphiAST adapter remains instrumented.

Parser regression coverage includes Delphi source files encoded with a UTF-8 byte-order mark, including exact-size stream buffers. Atropos normalizes the source text before invoking the vendored parser so that encoding detection cannot read beyond the input buffer.

Parser and file editing share source encoding detection: a BOM takes precedence,
valid unmarked UTF-8 is decoded as UTF-8, and other unmarked bytes use the Windows
default code page. Regression fixtures check exact accented text, extracted facts,
and unchanged source bytes for the default code page, UTF-8 with/without BOM and
UTF-16 with BOM. This does not infer arbitrary foreign code pages or CODEPAGE directives.

Build diagnostics accept MSBuild's `Hint warning H...` prefix as well as the
existing labelled and unlabelled formats. Reports count inline hint edits applied
separately from the before/after diagnostic totals: an edit is not proof that a
diagnostic disappeared. Regression coverage includes unchanged hint totals after
multiple edits, in both text and HTML reports.

Compiler probing also records default R/Q/B/C/J/T switch values from the selected
compiler. Conditional parsing applies these defaults before explicit project
options and source directives; empty project options retain defaults and invalid
values fail explicitly. Tests cover both target compilers, option precedence and
the missing-default regression. Contexts without probed defaults remain unknown.

Numeric conditional facts are probed with the selected compiler for primitive
System types and TMethod. RTLVersion is recorded only when the compiler confirms
it matches CompilerVersion. Unknown sizes remain errors. Before declaration binding
is available, unqualified numeric names already seen in active source or following
uses clauses remain unknown; explicit System qualification can disambiguate a local
type unless System itself has appeared. This conservative boundary includes names
introduced by includes. Tests cover target-specific sizes and local name shadowing.

The Windows parser adapter accepts Unsafe as an identifier without changing its
text or source positions. Compiler-checked fixtures cover constants, types, fields,
routines, parameters and locals, alongside field/parameter/result Unsafe attributes.
Parser fixtures use isolated temporary directories so separate checkouts cannot
overwrite each other's sources during validation.

The same adapter coverage exercises modern Delphi multiline string literals. Their contents are replaced with line-preserving placeholders for syntax analysis, preventing SQL or other embedded text from being interpreted as Delphi identifiers while keeping diagnostics aligned with the original source.

Coverage only:

```powershell
.\tests\run-coverage.ps1 -CodeCoveragePath 'D:\Tools\DelphiCodeCoverage\CodeCoverage.exe' -BdsVersion '23.0' -MinimumLineCoverage 85
```

The `.github\workflows\delphi-quality.yml` workflow requires a self-hosted Windows runner with RAD Studio and `DELPHI_CODE_COVERAGE` configured.

The lifecycle runtime smoke builds the original project via CLI dry-run, runs it,
then removes an unused import and moves the provider used only in initialization
and finalization to implementation. The rebuilt executable must retain exactly
`TransitiveInit|Boot|Main|Shutdown|TransitiveFinal` on both platforms. A bridge
import must remain in its original section because it activates the otherwise
unreferenced effect unit. This tests direct calls and one transitive chain;
it does not yet prove arbitrary initialization order or all movement semantics.

Parser lifecycle tests distinguish initialization, finalization and the legacy unit
body from ordinary procedure bodies and program bodies. The optional
`IUnitLifecycleFacts` port exposes phase, source path and normalized start location.
These are parser facts, not original byte ranges for editing. The adapter preserves
the start-file provenance when a section begins in an include and ends in its parent.
The legacy `HasInitializationSection` flag is a compatibility summary of any direct
unit lifecycle section; callers needing the phase should consume the facts port.

Effect graph tests exercise imports in both sections, pure cycles, cycles reaching
an effect, absent transitive sources, incomplete metadata and aliases/namespaces.
The traversal visits each name once per assessment and does not cache an unfinished
cycle as effect-free. Known effects take precedence over uncertainty elsewhere in
the graph; otherwise any missing facts produce an unknown preservation decision.
Resolver metadata is derived from the same parsed tree and kept per target/context.
Custom resolvers without `IUnitDependencyResolver` cannot prove absence of effects.
Manual `RegisterUnitExports` alone also leaves dependency metadata unknown;
callers must supply `RegisterUnitDependencies`, including an explicit empty list
when appropriate. SemanticProbe forwards imports from each parsed provider, and
synthetic unit tests declare their dependency-free fixtures explicitly.
Helper fact tests parse record/class helpers with default, private, public and
protected visibility, distinguish methods from properties, exclude ordinary and
implementation types, verify source locations and independent repeated reads.
These tests validate declaration extraction, not compiler helper precedence.

Helper integration regressions distinguish receivers across routines, parameter
shadowing, class fields, aliases, chains, bare calls, with blocks and lifecycle
variables. Competing helper imports and absent member facts remain unknown.
The lifecycle runtime fixture calls a string helper before and after optimization
and requires its import to move to implementation without changing output.

Lexical binding tests cover declaration order, inline initializers and blocks,
independent routines, generic arity, type expressions in declarations, owner fields,
qualified type members, overload uncertainty and include expansion order. The
lifecycle runtime fixture exports a colliding name from the unused provider and
shadows it locally; the optimizer must remove that import while preserving output.

Type-identity tests cover generic/plain collisions, argument counts, inferred and
explicit generic routine calls, qualified and nested type arguments, scoped enum
visibility, anonymous enum exports, attribute suffix alternatives and resolver
alias/reset behavior. The lifecycle fixture checks a generic record value and
instantiates an abbreviated custom attribute through RTTI before and after edits.
It requires removal of the plain-type collision while retaining the generic and
attribute providers in the interface, with identical lifecycle output on Win32/Win64.

Occurrence-edit tests verify section-specific decisions, original positions after
multiline strings/comments, stable ordering, in-path mappings, stale-plan rejection,
conditional uncertainty and no-op writes. Real file tests compare every byte for
default encoding, UTF-8 with/without BOM and UTF-16, using LF and CRLF. Removal now
retains comments even when their associated import is deleted.
The UsesConsole runtime gate builds Debug/Release on both platforms before and after
moving a provider into a guarded implementation clause. Debug emits Extra|7 and
Release emits 7; repeated optimization must leave the source hash unchanged. This
checks parenthesized conditional directives with the compiler: the pinned AST lexer
does not itself apply their conditional-state transitions reliably.

ConditionalConsole validates nested expressions, Delphi operator precedence, IFOPT,
ELSEIF and state carried through nested includes using actual compiler output.
Debug emits Precedence|8|Include and Release emits Precedence|100|Include before and
after removal of an unconditional unused import. Conditional providers remain in
the source. Unit tests also cover exact large integer comparisons across platforms,
repeated includes with different defines, inactive missing includes, local/project
switch precedence and explicit rejection of unsupported expressions. Compiler probes
rejected PUSH/POP and the tested parenthesized IF-expression directive; these are not
used as evidence of supported Delphi syntax.

AnonymousConsole verifies compiler-valid named anonymous-method types, parameter
shadowing, local/global captures and an outer reference that must retain its import.
Both platforms must emit Parameter:2|Capture:11|Global:1|Outside:99 before and after
optimization. The same gate requires compiler rejection of a temporary copy of the
historical inline `reference to` variable declaration with E2003 for `reference`.
That historical scenario keeps its original failing oracle; the valid supplementary
tests do not promote it to PASS.

SemanticRuntime exercises real VCL DFM streaming, OnCreate binding, class lookup by
registered string name, overload selection across two units and competing string helpers. Both platforms must
emit DFM:42|Registry:TStreamProbe|Integer|String|Second:value before and after cleanup. It also
builds three deliberately changed copies: removing the registration import must still
compile but fail during streaming; removing the exact overload provider must still
compile/run but select Variant for both calls; reversing the helper imports must
compile/run but select First:value. Both helper imports and their order must survive
cleanup, while an unused import in their consumer must be removed. Successful compilation alone
cannot satisfy these contracts.

`run-semantic-runtime-tests.ps1` writes `artifacts/integration/<platform>/semantic-runtime.json`
and captured process logs. PASS is recorded only after positive behavior, all
negative controls, actual removals, preserved imports and original fixture hashes
have been checked. The evidence identifies the CLI binary hash, target, research
catalog hash and fixture hashes. An interrupted run remains RUNNING; a caught failure
records FAIL. These supplementary results cover `dfm-streaming-registration`,
`rtti-string-registration`, `compiler-overload-binding` and `compiler-helper-precedence` in their integration layer.
They do not modify the historical Probe catalog or its BLOCKED totals and do not
prove arbitrary dynamic registration or complete compiler overload resolution.

Declaration provenance tests split routine/type headers across includes and the
main source. The adapter retains the starting file even when DelphiAST assigns
the compound node's ending file. The class-method fixture uses an explicit public
section; an include immediately following class still exposes a pinned-parser
lookahead limitation and is not claimed as supported by this change.

Implicit-effect tests cover managed record storage, aliases/nested records, pure
records/scalars, managed/foreign storage, class constructors, class storage and
resolver cache propagation. A direct compiler experiment on Win32/Win64 emitted
RecordInit/Main/RecordFinal for an imported unit containing an unused global managed
record; adding a class-method call also emitted ClassInit before RecordInit and
Touch after Main. The same class constructor was silent without that reference.
These observations justify definite record effects and unknown class activation,
not a general proof of constructor scheduling. The lifecycle runtime gate now
requires RecordInit and RecordFinal before/after optimization while preserving the
managed provider in its original interface section.

The `CancellationTransaction` fixture exercises the real application service,
DelphiAST parser, dependency resolver, uses editor and filesystem transaction in
an isolated temporary directory. It cancels after analysis before the first write,
after the first of two writes, and after the final write before the final build.
The write observer verifies that edits, a manifest and backups actually exist.
Each case requires EAbort, byte-for-byte restoration of UTF-8/BOM/LF and
UTF-16/BOM/CRLF sources, an unchanged provider, no commit or final build, and no
remaining manifest or backups. A new independent transaction must then succeed.
Project enumeration and the successful baseline build are controlled test doubles;
this fixture does not claim to exercise compiler cancellation or process crashes.
It provides direct application/filesystem evidence for the historical
`cancellation-transaction` contract without changing the Probe catalog status.

`CacheLifecycle` checks the existing analysis-scoped metadata caches. A changed
shared include invalidates the active snapshot; after BeginAnalysis and resolver
Initialize, both consumers expose the new export and no longer expose the removed
one. A changed provider similarly refreshes export facts, imports and initialization
status, and Initialize removes previously captured metadata before the next parse.
The real target factory and compiler process runner create Debug/Release services
for Win32 and Win64, then interleave lookups of the same conditional provider to
verify that exports from one configuration never appear in the other.

These tests prove restart freshness and the `cache-context-isolation` contract.
They do not implement or validate persistent/shared content-keyed caching or automatic
invalidation inside an active analysis. Such mutations still abort the snapshot;
source/include persistent-cache scenarios retain their historical BLOCKED status.

## Phase performance profiling

Run `tests/run-performance-profile.ps1 -Platform Win32` and again with Win64.
The runner builds the optimized AtroposProfile harness and applies the real default
application workflow to three fresh copies of each representative fixture. It checks
successful baseline/final builds, actual edits, required phase samples, original
fixture hashes, and accounting of exclusive time against total execution time.
Results and a RUNNING/PASS/FAIL manifest with source/runner/harness/binary hashes
are written under `artifacts/performance/<platform>`. Profiling is a diagnostic
workflow, not a timing threshold in the regular quality gate. Do not run other
builds/benchmarks concurrently when collecting a comparison.

The in-memory, thread-local profiler is inactive by default in CLI/VCL. The harness
explicitly enables it and outputs per-phase/per-subject calls and inclusive/exclusive
wall-clock milliseconds. Exclusive time subtracts nested instrumented operations;
only exclusive phase totals may be summed. Parsing includes source I/O, conditional
preparation and includes; extraction covers syntax traversals; resolution excludes
its nested parsing/extraction; decisions exclude their nested resolution/extraction.
Project evaluation, target preparation (including compiler symbol probing), edit
planning, edit writes (including backups), builds and remaining execution overhead
are separate phases. Errors close their scopes and failed executions cannot be
reported as successful measurements. Repeated parser calls are reported per file;
nested resolver wrapper calls are not counts of distinct units.

Measurements include instrumentation overhead, OS caches and process-startup cost.
These small console/VCL fixtures do not establish large-project throughput or justify
persistent caching. Compare repeated runs and source/toolchain hashes before drawing
performance conclusions. Direct use of AtroposProfile applies edits; supply only a
disposable project copy, as the runner does automatically.

ContextRuntime validates all four Debug/Release x Win32/Win64 targets in one cleanup.
Imported context.props supplies configuration-specific aliases, namespace order and
a Debug define. The consumer has both define/platform-specific dependencies; its
DPR maps Mapped to chosen/Mapped.pas despite a competing root file. Every target's
runtime output must be identical before/after, while an unused import is actually
removed. Three separately compiled negative controls change the alias, namespace
order or DPR mapping and must select different observable values. Direct resolver
tests also use distinct exports to prove selection among competing files.

The scanner now accepts complete qualified IF/ELSE alternatives; names assembled
partially across directives remain unsupported. The uses reader recognizes mutually
exclusive branch alternatives sharing a separator, enabling safe edits elsewhere
in that list. Conditional entries remain immutable; independent guards cannot stand
in for a missing comma. Regression tests cover these boundaries and idempotence.

The quality gate runs run-context-runtime-tests.ps1 for both CLI architectures. Its
supplementary evidence is artifacts/integration/<platform>/context-runtime/result.json,
with input/binary/runner hashes and all target/control observations. Working copies
are retained under the ignored artifacts directory for inspection; fixtures remain
unchanged. Contracts cover project defines, platforms, namespaces, aliases, DPR paths
and imported props without modifying the historical Probe catalog or BLOCKED totals.

BinaryRuntime compiles a provider in an isolated producer directory and exposes
only its DCU through the consumer project's binary search path. The producer source
is retained outside the project; the provider is not a project source reference.
The runner requires no provider PAS in the consumer tree, exactly one provider DCU
(no project-output rebuild), an unchanged DCU hash and the explicit source/exports
unresolved preservation diagnostic. Before and after removing another unused import,
runtime must emit BinaryInit|Main|BinaryFinal even though no provider symbol is
referenced in source. Removing the binary import in a control still compiles but
must emit only Main, demonstrating that a successful build does not preserve effects.

The quality gate runs this on Win32/Win64. Evidence for `package-dcu-only` is saved
in artifacts/integration/<platform>/binary-runtime/result.json with compiler, CLI,
DCU, runner and fixture hashes. Producer sources and project copies are retained
for inspection. This proves conservative handling of a DCU-only dependency, not
DCU decompilation or dynamic BPL loading. The historical Probe catalog is unchanged.

For a controlled scaling measurement, run `tests/run-scaled-profile.ps1 -Platform Win32`
and then the same command with `-Platform Win64`. Do not run competing builds while
measuring. Defaults generate 16 providers, 32 consumers, and 128 or 512 constants
per provider, with three fresh copies per size. Every consumer references four
constants near the end of each provider's declarations and includes one unused
dependency. The generated project therefore exposes 2,048 or 8,192 provider symbols
and 2,048 source references across the consumers. `-SymbolCounts` and `-Repetitions`
can adjust the experiment; the standalone generator also exposes provider/consumer
counts and refuses to overwrite an existing directory.

The runner builds and executes the baseline, profiles production cleanup, executes
the result, and checks the exact expected sum, all required imports, removal of the
unused imports, unchanged other source files, phase accounting, and verification
builds. It retains generated inputs, outputs, hashes and per-phase measurements under
`artifacts/performance/scaled/<platform>/<run-id>/run.json`. Each run records PASS or
FAIL; incomplete measurements must not be reported as successful experiments.
This is a synthetic scaling workload, not a claim about a particular production
application. Baseline compilation precedes measurement, so filesystem/compiler caches
may be warm. Timing includes profiler overhead and should be compared across repeated
runs on the same machine. Use it alongside the representative runtime fixtures;
neither a single timing nor a passing build alone justifies persistent cache changes.

Structured export lookup uses an analysis-local index of full export names and
generic arities. A routine also supplies the inferred-argument lookup at arity zero;
types do not. Replacing export facts clears previous entries, including inferred
routine entries. Known empty metadata does not fall back to legacy identifiers.
TypeIdentity tests compare indexed lookup with the previous linear predicate across
duplicate names, owners, arities, routines and non-ASCII characters, and verify input
array isolation and replacement. Existing source-based tests cover qualified types,
routine inference, attributes and aliases. Use the unchanged scaled generator to
compare performance; keep behavioral checks enabled when measuring the index.

The `syntax-building` profile phase measures actual AST construction within the
broader `parsing` phase, which still includes reading, hashing, conditional source
preparation and include resolution. AnalysisSnapshot tests require tree identity
reuse only for unchanged inputs within one analysis, rebuilding for changed root
or include bytes, and independence across analysis lifetimes. They also exercise
a new higher-priority include with identical bytes, both during a later read and
after the last read but before validation. Removing the missing-candidate recording
causes both include-resolution regression tests to fail. Reverting an observed
change does not rehabilitate an already invalid snapshot. This reuses syntax, not
filesystem observations; additional retained AST memory is a tradeoff, and reduced
construction counts alone do not establish a wall-clock speedup.

Executable-size metrics use the evaluated MSBuild `FinalOutput` for the selected
configuration and platform after a successful build. ProjectContext regressions
cover renamed output, Unicode paths, missing artifacts, target property groups,
and task output properties. When output metadata is unavailable or can change
inside a target, the metric remains unknown. Metadata lookup failures preserve
build success; cancellation still propagates. A real RepresentativeConsole run
with minimal MSBuild verbosity reproduces the old missing-size report and verifies
the measured executable with the new adapter.

Assembler double-quoted literals are tokenized as strings, including apostrophes
inside them. ConditionalEvaluation tests cover active and inactive assembler blocks
and require the declaration after the closing conditional to remain visible. The
minimal assembler example compiles with dcc32 and dcc64. The local System.AnsiStrings
source reproduces the former unterminated-conditional error and parses successfully
with this tokenizer correction.

Record alignment is parsed as a constant expression. Tests cover literal sizes,
SizeOf, arithmetic, local constants and imported constants with both bare and
qualified names. Alignment expressions remain in the syntax tree so dependency
analysis can retain their references; a single literal also keeps its alignment
attribute. Compiler fixtures verify the accepted alignment syntax in Win32 and Win64.

Local declaration lookup is indexed by scope and name, retaining declaration order,
availability positions, generic arity and conservative overload behavior. SymbolBinding
regressions cover 30,000 declarations, input-array isolation, and comparison against
SameText for ASCII and non-ASCII names. External-name ordering remains unchanged.

Parser syntax failures retain their source file and line/column in diagnostics,
including errors inside include files. Unexpected EOF coordinates are normalized
before the upstream parser wraps its exception. DelphiASTAdapter regressions verify
root, include and EOF locations. Coordinates refer to the parser's normalized input;
multiline-string normalization preserves lines but may change columns.

CompilerTraceProcess tests exercise native compiler preparation on Win32/Win64,
including local type shadowing, imported DECLARED names, repeated includes, and the
installed Winapi.Windows and System.SysUtils sources. They require both discovery
and validation compilations, verify source/include mutation rejection and check
reuse without further compiler calls. Imports needed by compiler conditions remain
constrained. Process tests cover cancellation, stale or missing artifacts, changed
project/environment settings, and project hooks. The dependency reader is checked
against generated lists as well as malformed and missing paths. These checks do not
establish support for uncaptured regenerated dependencies or every Delphi version.
