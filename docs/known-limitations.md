# Known limitations

- `--dry-run` reports candidates but does not produce an applicable patch.
- The VCL interface does not export reports or select an output directory.
- The CLI has no interactive cancellation option.
- Analysis depends on units and search paths obtained from the `.dproj`.
- Unresolved dependencies are preserved conservatively.
- Initialization sections and conditional references may prevent changes.
- Dynamic RTTI, name-based loading, side effects, and generated code may escape static analysis.
- Library Paths and globally installed components may differ between machines.
- Current validation focuses on Windows and BDS 23.0.
- Visual UI behavior and every supported RAD Studio version are not fully covered.

For production use, work on a branch, review every change, and run the analyzed project's functional test suite.
