# Tests, coverage, and quality gates

`tests\AtroposTests.dproj` covers the domain, `.dproj` parsing, DelphiAST, resolution, files, modifier, reports, CLI, lifecycle, builds, and integration.

```powershell
msbuild tests\AtroposTests.dproj /t:Build /p:Config=Debug /p:Platform=Win64
.\tests\Win64\Debug\AtroposTests.exe --consolemode:quiet
```

## Complete gate

For Win32 and Win64, the gate builds and runs DUnitX, builds CLI/VCL Release, and runs simulated real-use smoke tests. It then measures Win32 coverage and enforces the threshold.

```powershell
.\tests\run-quality-gates.ps1 `
  -BdsVersion '23.0' `
  -CodeCoveragePath 'D:\Tools\DelphiCodeCoverage\CodeCoverage.exe' `
  -MinimumLineCoverage 85
```

The smoke test verifies the PE architecture, copies the fixture, runs the CLI, removes a dependency, generates a report, and confirms that the original fixture remains unchanged.

Coverage only:

```powershell
.\tests\run-coverage.ps1 -CodeCoveragePath 'D:\Tools\DelphiCodeCoverage\CodeCoverage.exe' -BdsVersion '23.0' -MinimumLineCoverage 85
```

The `.github\workflows\delphi-quality.yml` workflow requires a self-hosted Windows runner with RAD Studio and `DELPHI_CODE_COVERAGE` configured.
