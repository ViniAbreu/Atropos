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
