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