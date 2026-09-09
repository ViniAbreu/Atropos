# Compatibility

## Automatically validated

| Item | Evidence |
| --- | --- |
| Windows Win32 | Successful build, DUnitX suite, and smoke tests |
| Windows Win64 | Successful build, DUnitX suite, and smoke tests |
| RAD Studio BDS 23.0 / 37.0 | Delphi 12 / 13 discovery and build validation |
| DelphiAST | Commit pinned by the submodule |

This does not certify every combination of Delphi version, component set, and project type.

The resolver treats `ProjectVersion` as a file-format hint, not a unique IDE
identity. A valid explicit `BDS` environment variable wins. Otherwise it uses
a validated registered installation, preferring the hinted version when
unambiguous and falling back to a newer available installation. Both registry
views and HKCU/HKLM are scanned. Stale registrations are skipped; `20.3` is
shared by Delphi 12.3 and 13.0. See [Delphi discovery](delphi-discovery.md).

The current focus is Delphi `.dproj` projects for Windows. Packages, DLLs, services, project groups, cross-platform projects, and remote toolchains require a dedicated test corpus before they can be declared supported.

A combination should enter the validated matrix only after builds, DUnitX, an isolated smoke test, and recording its version and architecture in the pull request.
