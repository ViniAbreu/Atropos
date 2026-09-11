# Evaluated project context

`TAppServiceFactory` now uses `IProjectContextProvider` for target-specific analysis.
Every requested configuration/platform gets its own parser, source resolver and
export cache. The workflow gathers the union of project units and active explicit
DPR mappings, analyzes that union under each selected context and intersects proposed actions before writing. A unit
needed in any context is preserved; a parse failure vetoes edits for that file.
With no explicit target, evaluation uses the project's defaults.
The provider runs the installed .NET Framework MSBuild evaluation API in an isolated
Windows PowerShell process under the selected Delphi `rsvars.bat` environment. It
does not run build targets. Configuration and platform are MSBuild global properties,
so project assignments cannot override an explicitly requested target. An empty
target requests the project's defaults. The request is JSON encoded inside a
temporary script; project paths are not interpolated into shell commands. Responses
are UTF-8 JSON encoded as Base64 to preserve Unicode across console code pages.

The result records evaluated defines, ordered source/include paths, namespaces,
aliases, compiler option property values, active PAS `DCCReference` items, main
source, compiler path and executable file version. Imported property files and
property functions are evaluated by MSBuild. Root/import hashes are checked across
two evaluations to reject changed inputs; returned project-file hashes also
extend the application snapshot. Each call starts a fresh process and evaluation.

Missing imports, malformed output, process failure, timeout and cancellation fail
explicitly. There is no fallback that treats failed evaluation as an empty context.
Temporary scripts are removed after the process finishes or is terminated. The
existing process runner supplies cancellation, timeout and process-tree cleanup.

## Parser and resolution integration

- Evaluated properties are not necessarily the final compiler invocation. Targets
  may change properties or items or produce task outputs during a build. Direct
  compiler-related property groups in targets are listed in `DeferredProperties`;
  that list is not exhaustive proof that no other deferred effects exist.
- A temporary program queries a catalog of compiler predefined symbols through the
  selected compiler. The compiler banner supplies its language version and VER
  symbol; executable file version is not used as CompilerVersion. Console/GUI mode
  is explicit. This probing currently supports Win32/Win64 Console and Application
  projects; other application types fail explicitly. The generated executable is
  never run, and temporary compiler products are removed.
- Project defines and include paths reach both consumers and providers. A source
  preparation pass evaluates IFDEF/IFNDEF, IF/ELSEIF and known IFOPT switches before
  the AST lexer chooses branches. Defines and switches flow through active includes
  in source order; repeated includes retain distinct prepared content and original
  filenames. Inactive includes are not loaded. Unknown expressions or switches
  reject parsing and preserve consumers/providers with diagnostics.
- Boolean precedence follows Delphi: NOT, AND, OR/XOR, then comparisons. Supported
  operands include DEFINED, Boolean literals, signed Int64 integers, limited decimal
  literals and the selected compiler's CompilerVersion. Integer comparisons remain
  exact on both platforms. Decimal literals are limited to 16 characters; mixed
  numeric comparisons outside exact double integer range are rejected. Arithmetic,
  bitwise expressions and high precision calculations remain restricted. Selected
  compiler numeric facts support known SIZEOF and RTLVersion values. Declaration
  queries and numeric names requiring binding can use compiler preparation below.
- Ordered namespaces and single-step aliases are used for source lookup;
  active DPR `uses ... in` mappings take precedence over PAS filename lookup and
  searched sources. Mapped sources join the unit union even without DCCReference.
  Full scoped binding, implicit compilation reachability, generated units and
  DCU/source equivalence remain incomplete.
- A lexical scan of active and inactive source text protects names occurring in
  conditional imports. Independent unconditional imports can still be removed.
  Conditional qualified names that cannot be delimited fail conservatively. Uses
  entries from includes still preserve the entire consumer until source-aware editing.
- Action agreement is currently by name and section through the existing decision
  model. The union is analyzed even in contexts where a file is absent from that
  context's DCCReference list; this can preserve target-exclusive files unnecessarily.
  Precise compilation reachability and occurrence identity remain follow-up work.
- DPR paths are read from the AST under each target context and resolved relative
  to the MSBuild project directory, including when MainSource is in a subdirectory.
  Only literal paths are accepted. Duplicate mappings, missing
  mapped files and incomplete project parsing abort planning before edits. A mapped
  provider with a mismatched unit declaration is unknown; search does not fall back.
  Project includes containing uses remain explicitly unsupported.
- Project/import hashes and source/include hashes are validated after all target
  analyses, before the first edit. The parser snapshot starts before reading the DPR
  and is retained throughout analysis. Directory listings, task outputs, compiler CFG
  settings outside evaluated properties and filesystem locking remain outside this
  snapshot. Direct deferred compiler properties currently preserve affected analysis.
- Windows PowerShell and .NET Framework MSBuild are required. PowerShell execution
  policy failures remain explicit; this adapter does not override machine policy.

The DUnitX fixture `Atropos.Tests.ProjectContext` executes the real evaluation API
against temporary projects for all four Debug/Release and Win32/Win64 combinations,
imports, property functions, global-property precedence, Unicode paths, conditional
items, changed imports and deferred property detection. It proves evaluation does
not execute a target that would write a marker file. These tests do not yet promote
the research end-to-end project-context scenarios.

`Atropos.Tests.TargetAnalysis` covers isolated symbols, include defines, conditional
import constraints, namespace/alias lookup, incomplete providers, selected Win32 and
Win64 compilers, action disagreement, four evaluated targets, dry-run and project
metadata mutation. Its matrix tests use the real evaluator/parser/resolver/filesystem
with a build-service stub; the quality gate separately runs actual CLI builds and
representative project smoke tests. This is not yet a runtime-semantic guarantee.

## Compiler-assisted conditional preparation

When DECLARED or a numeric condition requires declaration resolution, the target
parser can compile an instrumented copy of a Pascal unit. Unique messages identify
selected branches; each include invocation has its own copy and marker sequence.
The replay preserves source lines and original include paths. The parser retains
all imports in these units because removing an import can change a conditional
result even if a subsequent build succeeds. Their exported declarations remain
available for analysis of other consumers.

The adapter evaluates the original project with MSBuild, then redirects output
properties on its ProjectInstance. It runs the native compiler target and its path
file targets, without running the generated executable. Project initial targets,
replaced compiler targets and hooks on those targets are rejected. A signature of
evaluated compiler properties and standard compiler/task binaries is checked before
and after compilation. Source, include and captured binary hashes extend the
analysis snapshot; missing lookup candidates are recorded as well.

A discovery compilation obtains the compiler dependency list. A second compilation
produces the branch trace after those inputs have been captured, and its dependencies
must be covered by the snapshot. MakeModifiedUnits ensures generated DCUs exist;
the dependency reader accounts for compiler lists that name their source directory
instead of their fresh output directory. Temporary files are deleted, and cached
preparations are reused only while their recorded inputs remain unchanged.

This path currently requires precompiled dependencies: a dependency unit regenerated
from an uncaptured source is rejected. Relative resource/object lookup, recursive
includes, custom toolchains and complete build-target effects remain limitations.
The declaration-dependent fallback currently accepts Pascal units, not DPR sources.
Failure, timeout, cancellation or an incomplete trace never substitutes guessed
conditional values.
