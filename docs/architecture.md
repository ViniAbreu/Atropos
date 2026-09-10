# Architecture

```text
CLI / VCL -> Application Service -> Core (domain and ports)
                                      ^
                                      |
          Adapters (AST, XML, files, build, environment, reports)
```

## Layers

- `src\Core`: models, configuration, rules, modifier, and ports. It does not know about UI or infrastructure.
- `src\Application`: orchestrates environment discovery, builds, analysis, commit, rollback, logs, and progress.
- `src\Adapters`: integrates DelphiAST, `.dproj`, external units, files, BDS, the registry, and reports.
- `src\CLI` and `src\GUI`: presentation contracts over the same application service.

Adapters and presentation depend on Core abstractions. The domain must not import VCL, XML, registry, filesystem, or DelphiAST units. New integrations must implement a port and be connected by the factory.

## Enforced boundaries

`tests\test-architecture.ps1` rejects reverse dependencies from Core, presentation dependencies from Application or Adapters, named nested routines, `else`, source files above 600 lines, and routines above 120 lines. `Atropos.Application.Factory` is the explicit composition root and is the only Application unit allowed to reference concrete Adapters. The guard has isolated regression fixtures for every rule and runs before compilation in the complete quality gate.

Main adapter responsibilities:

- `DelphiAST`: syntactic view of source files;
- `ProjectParser`: conditional properties, units, search paths, recursive property expansion, and diagnostics for unsupported MSBuild expressions;
- `ExternalUnitResolver`: unit location and exported symbols;
- `FileSystem`: encoding-aware I/O, exclusive project locks, and SHA-256-verified backup transactions with versioned manifests;
- `BuildService`: AutoBuild, timeout, cancellation, and metrics;
- `DelphiEnvironment`: project version and RAD Studio installation discovery;
- `ReportGenerator`: text and HTML output.

Helper declarations are available through the optional Core port
`IUnitHelperFacts`. The DelphiAST adapter returns interface helper names, receiver
type spellings, member names/kinds, visibility and normalized source locations.
Methods are siblings of the HELPER node or children of visibility blocks; they
are not children of HELPER. Private members remain facts, not public exports.
Helper facts now derive legacy export entries. Analysis matches these entries to
member references resolved from routine parameters and variables, with section
and lexical scope. The Core binding service preserves unknown receivers and
competing helper candidates; flat identifier matching excludes helper entries.
The legacy direct lookup API retains its optional compatibility behavior.
Aliases, class fields, inherited receiver types and full symbol identity still
require further binding; uncertain supported references preserve the import.

`IUnitSymbolFacts` separates declarations, references and lexical scopes. Facts
carry expanded traversal order, normalized source positions, declaration kind
and generic arity. Core local binding excludes proven local references from the
import lookup projection. Routine/type/block scopes and interface visibility are
independent; qualified names retain their unit/type prefix. With scopes and local
overloads remain unknown and preserve matching imports. This is lexical binding,
not complete overload resolution, inheritance or compiler-level type identity.

Uses editing tokenizes the original source rather than searching section headers
with regular expressions or using normalized AST columns. Prepared file plans
retain the original and updated text; actionable decisions carry original UTF-16
offsets, source path, section and condition identity. Target intersection preserves
section identity. All file edits are prepared before writes, and the original text
is checked again before each write. Dry-run uses the same preparation path.
The editor retains comments and in-path entries, preserves moved-item source order,
and leaves an already-present destination entry in place. Ambiguous occurrences,
edits crossing directives and unsupported relocation remain unchanged with a reason.
Unconditional entries can be removed when the affected separator and neighboring
entry are also unconditional. Includes hiding a destination clause prevent insertion.

Conditional source preparation lives in the AST adapter. It evaluates supported
expressions against the selected context, blanks inactive text while retaining line
breaks, and supplies prepared active includes under internal keys with their original
filenames. The real sources and hashes remain snapshot inputs. No transformed text
is written back. Unsupported expressions stop parsing rather than selecting a false
branch. The DelphiAST submodule remains pinned and unchanged.

`IUnitExportFacts` carries symbol kind and generic arity independently of legacy
export names. Resolver caches and aliases forward these facts to the Core. Type
lookups require matching arity; generic routine calls may infer their arguments.
Fallback resolvers without these facts keep the broader legacy name comparison.
The syntax adapter retains qualified generic arguments and full attribute names
that upstream AST flattening would discard. Scoped enum members stay under their
named type; anonymous enums still expose their members, including under SCOPEDENUMS.
Attribute references preserve both exact and Attribute-suffixed providers as unknown
until constructor selection and inheritance are resolved. Ordinary references do
not gain the suffix. This does not implement full nominal type or overload binding.

Implicit lifecycle facts are separate from import completeness. Known managed-record
global storage sets the compatibility lifecycle flag; unresolved global/typed/class
storage and class-constructor activation produce unknown effect metadata. Resolver
caches copy this metadata with aliases/namespaces and clear it per context. The
effect graph propagates uncertainty without discarding known import edges; a known
effect elsewhere still takes precedence. Resolvers without implicit-effect metadata
cannot prove absence. Manual contexts backed by real syntax trees must forward
`RegisterImplicitEffects`; synthetic fixtures explicitly declare their facts.

Local aliases and record fields are inspected without treating ordinary Initialize
methods or routine-local record variables as unit startup effects. Foreign types,
managed built-ins, arrays, typed constants and class storage remain conservative.
Class constructors require reachability evidence; merely declaring one is not
reported as a proven executed effect.
