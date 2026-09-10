# Known limitations

- `--dry-run` prepares edits in memory and reports candidates, but does not export a standalone patch.
- The VCL interface does not export reports or select an output directory.
- The CLI has no interactive cancellation option.
- Analysis starts from evaluated `.dproj` units and active literal DPR mappings.
  Implicit compilation reachability is not yet complete.
- The default application uses [MSBuild contexts](project-context.md) for imports,
  properties and target-specific source lists. Properties/items produced during
  build targets are not fully evaluated; detected deferred compiler properties preserve
  analysis. The legacy XML parser remains available for injected/custom services.
- Target contexts are separate and actions are intersected before writing. Parsing
  and name-based binding are still partial. Conditional expressions support Boolean
  operators, DEFINED, parentheses and numeric comparisons; IFOPT requires a known
  project or source switch. Unsupported operands/options fail explicitly and preserve
  dependencies. Known numeric facts come from the selected compiler. Declaration-bound
  DECLARED, SIZEOF and RTLVersion conditions can use isolated compiler preparation;
  other unsupported arithmetic, bitwise and precision cases are not inferred.
- Compiler-prepared units retain their imports, including imports referenced only
  by conditional expressions. Their declarations can still inform other consumers.
  This preparation requires precompiled dependencies; regenerated dependency units
  without source snapshots are rejected. Relative resource/object paths, guarded
  recursive includes and declaration-bound DPR conditions remain unsupported or
  restricted. See [project contexts](project-context.md).
- Unresolved dependencies are preserved conservatively.
- The historical anonymous-parameter scenario uses an inline `reference to` variable
  declaration rejected by compiler 36.0 on Win32/Win64. Its original oracle remains
  failing; named anonymous-method types have separate compiler/runtime coverage.
- Active includes are resolved relative to their containing source, then through
  evaluated project include paths. Missing includes, cycles and excessive nesting fail
  explicitly; recursive includes are rejected even when guarded by defines.
- Include provenance records parent, path and content hash. Imports originating in
  includes preserve the entire consumer with a diagnostic until source-aware editing
  is available. Names occurring in conditional imports are also preserved.
- Dependency decisions record state, section, action and reason. Unknown sources,
  parse failures and adapter-reported incomplete analysis are preserved with report
  warnings. Name-based usage decisions remain heuristic until structured binding is
  implemented; an absent diagnostic is not proof of complete semantic analysis.
- Unqualified identifiers exported by multiple units are preserved and reported to prevent semantically ambiguous changes.
- Implementation ambiguity checks include interface imports. Ambiguous candidates
  remain in their original sections; unrelated imports can still be analyzed.
- Direct initialization, finalization and legacy unit-body effects are preserved
  for native and project units alike. Explicit import graphs carry these effects
  transitively, including cycles; missing dependency facts preserve imports as unknown.
  Managed global storage
  and class constructors still require further analysis.
- Initialization sections and conditional references may prevent changes.
- Dynamic RTTI, name-based loading, side effects, and generated code may escape static analysis.
- Library Paths and globally installed components may differ between machines.
- All decisions are collected before uses edits, and the production parser verifies
  source/include and project/import hashes before application. Lookup listings and
  task-produced settings are not yet snapshot inputs. No filesystem lock prevents external changes after
  validation; do not concurrently edit or generate the analyzed sources.
- The editor still has formatting limitations, including section headers placed on
  the same line as surrounding code. Occurrence-aware editing remains required.
- Current validation focuses on Windows. Discovery is checked against the locally installed BDS 17.0, 22.0, 23.0, and 37.0; full application builds use modern Delphi toolchains. Project-format detection cannot prove source/component compatibility.
- Visual UI behavior and every supported RAD Studio version are not fully covered.

For production use, work on a branch, review every change, and run the analyzed project's functional test suite.
