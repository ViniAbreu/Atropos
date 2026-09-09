# Known limitations

- `--dry-run` reports candidates but does not produce an applicable patch.
- The VCL interface does not export reports or select an output directory.
- The CLI has no interactive cancellation option.
- Analysis depends on units and search paths obtained from the `.dproj`.
- The `.dproj` evaluator supports quoted `==`/`!=` comparisons, `and`, `or`, parentheses, and `Exists('path')`. Unsupported MSBuild functions or expressions are skipped conservatively and recorded as analysis warnings instead of being treated as ordinary false conditions without explanation.
- Imported MSBuild project files and property functions are not evaluated by the project parser. Keep analysis-critical unit lists and search paths in the `.dproj`; unsupported conditions in those sections are reported.
- Unresolved dependencies are preserved conservatively.
- Unqualified identifiers exported by multiple units are preserved and reported to prevent semantically ambiguous changes.
- Initialization sections and conditional references may prevent changes.
- Dynamic RTTI, name-based loading, side effects, and generated code may escape static analysis.
- Library Paths and globally installed components may differ between machines.
- Current validation focuses on Windows. Discovery is checked against the locally installed BDS 17.0, 22.0, 23.0, and 37.0; full application builds use modern Delphi toolchains. Project-format detection cannot prove source/component compatibility.
- Visual UI behavior and every supported RAD Studio version are not fully covered.

For production use, work on a branch, review every change, and run the analyzed project's functional test suite.
