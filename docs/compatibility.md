# Compatibility

## Automatically validated

| Item | Evidence |
| --- | --- |
| Windows Win32 | Successful build, DUnitX suite, and smoke tests |
| Windows Win64 | Successful build, DUnitX suite, and smoke tests |
| RAD Studio BDS 23.0 | Current quality-gate environment |
| DelphiAST | Commit pinned by the submodule |

This does not certify every combination of Delphi version, component set, and project type.

The resolver recognizes `ProjectVersion` values associated with BDS 15.0 through 23.0. Recognition is not equivalent to validation. When no mapping exists, it tries the highest installed version and then the `BDS` environment variable.

The current focus is Delphi `.dproj` projects for Windows. Packages, DLLs, services, project groups, cross-platform projects, and remote toolchains require a dedicated test corpus before they can be declared supported.

A combination should enter the validated matrix only after builds, DUnitX, an isolated smoke test, and recording its version and architecture in the pull request.
