# Tests, coverage, and quality gates

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

Coverage only:

```powershell
.\tests\run-coverage.ps1 -CodeCoveragePath 'D:\Tools\DelphiCodeCoverage\CodeCoverage.exe' -BdsVersion '23.0' -MinimumLineCoverage 85
```

The `.github\workflows\delphi-quality.yml` workflow requires a self-hosted Windows runner with RAD Studio and `DELPHI_CODE_COVERAGE` configured.
