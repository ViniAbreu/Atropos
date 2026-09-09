# Delphi installation discovery

## Selection policy

1. Honor an explicitly configured `BDS` when the installation has usable tools.
2. Enumerate numeric BDS installation keys under HKCU and HKLM, in both the
   32-bit and 64-bit registry views. Read `RootDir`, `App`, and `App x64`.
3. Validate paths on disk. Ignore removed installations, empty registrations,
   and alternate profile keys such as `37.0_x64`.
4. Prefer the project-format hint when unambiguous and installed. Otherwise
   choose the highest valid registered version at or above the known minimum.
   Equal versions prefer the user registration. Unknown formats use the newest
   available installation; an older compiler is not a safe inferred fallback.

`ProjectVersion` is not a compiler version. In particular, `20.3` is shared
by Delphi 12.3 and Delphi 13.0; automatic selection uses the newest available
installation from BDS 23.0 onward. Set `BDS` explicitly to retain Delphi 12
for such a project. Format `20.4` maps to BDS 37.0. Unknown future formats
are not matched by a broad `20.*` rule.

A usable installation contains `bin\bds.exe`, `bin64\bds.exe`, or complete
headless tools (`bin\rsvars.bat`, `bin\dcc32.exe`, and
`bin\CodeGear.Delphi.Targets`). The existing capability probe still checks
whether command-line compilation is licensed and operational. IDE fallback
prefers `bin\bds.exe`, then `bin64\bds.exe`. Explicit build targets continue
to use MSBuild, keeping target architecture separate from IDE architecture.

Selection does not prove that third-party components or source language
features are compatible. Baseline compilation remains mandatory and aborts
processing on failure. A compiler error is not a reason to silently switch
installations and repeat source modification.

## Reproducible selection

For a PowerShell session using Delphi 13:

```powershell
$env:BDS = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
.\Win64\Release\AtroposCLI.exe -dproj 'D:\Project\App.dproj' --dry-run
```

Use the actual root for custom installations. This affects that shell and its
child processes; Atropos does not rewrite registry entries or global variables.
Build logs include `Resolved Delphi installation:` with the actual selected path.

## Verification and references

The regression suite covers stale exact/highest versions, explicit/stale BDS,
custom directories, shared formats, missing/malformed projects, both registry
views, missing RootDir with App/App x64, IDE64-only and headless installations.
Registry tests use temporary keys under `Software\Atropos.Tests`, never the
real Embarcadero installation keys. The optional local matrix checks the
installed 17.0, 22.0, 23.0, and 37.0 roots.

Official Embarcadero references:

- [RAD Studio 13 changes](https://docwiki.embarcadero.com/RADStudio/Florence/en/What%27s_New): installation/registry numbering jumps to 37.0.
- [Florence environment variables](https://docwiki.embarcadero.com/RADStudio/Florence/en/Defined_Environment_Variables): BDS/BDSBIN locations.
- [Athens environment variables](https://docwiki.embarcadero.com/RADStudio/Athens/en/Defined_Environment_Variables): BDS 23.0.
- [64-bit IDE](https://docwiki.embarcadero.com/RADStudio/Florence/en/64-bit_IDE): App x64 and checking that the executable exists. Some examples on this page retain Athens numbering; the Florence release notes establish 37.0.
- [MSBuild](https://docwiki.embarcadero.com/RADStudio/en/MSBuild): building dproj projects in the selected RAD Studio environment.

The file-format range hints and shared formats are also documented by the
maintainers of [Ethea InnoSetupScripts](https://github.com/EtheaDev/InnoSetupScripts).
They are selection heuristics, not an Embarcadero guarantee of compatibility.
