# Contributing

Clone with `--recurse-submodules`, create a focused branch, and read the [architecture](docs/architecture.md), [testing](docs/testing.md), and [safety](docs/safety-and-rollback.md) guides.

## Rules

- Preserve the dependency direction of the hexagonal architecture.
- Do not place I/O, VCL, XML, or DelphiAST dependencies in the Core.
- Bug fixes must include a test that fails without the fix.
- Features must cover the expected behavior and relevant failure paths.
- Source-file writes must prove rollback and encoding preservation.
- Do not rely unnecessarily on globally installed libraries.
- Update all affected documentation.

Before opening a pull request:

```powershell
.\tests\run-quality-gates.ps1 `
  -BdsVersion '23.0' `
  -CodeCoveragePath 'D:\Tools\DelphiCodeCoverage\CodeCoverage.exe' `
  -MinimumLineCoverage 85
```

Describe the problem, technical decision, risks, tests, Win32/Win64 results, coverage, and manual validation. Prefer one workstream per pull request and do not mix unrelated changes.

Contributions are distributed under the project's GPL-3.0 license.
