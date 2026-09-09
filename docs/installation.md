# Installation and build

## Runtime requirements

- Windows;
- an installed and registered RAD Studio/Delphi environment;
- a `.dproj` that builds in the local environment;
- read and write access to source files and reports.

Download the Win32 or Win64 package from the [releases](https://github.com/ViniAbreu/Atropos/releases/latest). The Atropos executable architecture does not change the platform configured in the project being analyzed.

## Source code

```powershell
git clone --recurse-submodules https://github.com/ViniAbreu/Atropos.git
cd Atropos
```

In an existing clone:

```powershell
git submodule update --init --recursive
```

Open `Atropos.groupproj` or build from a RAD Studio Command Prompt:

```powershell
msbuild AtroposCLI.dproj /t:Build /p:Config=Release /p:Platform=Win64
msbuild AtroposVCL.dproj /t:Build /p:Config=Release /p:Platform=Win64
```

Outputs are written to `<platform>\<configuration>`. DelphiAST is located in `third_party\DelphiAST`; use the submodule commit instead of a global installation.

## Troubleshooting

- Missing DelphiAST unit: initialize the submodule.
- RAD Studio not found: check the per-user and machine-wide BDS registry entries and the `BDS` environment variable. Atropos prefers the project version but can use the newest registered installation when that exact version is unavailable.
- Baseline build failed: build the same `.dproj` manually and repair the baseline.
- Very large global Library Path: use the quality gates, which isolate dependencies for the Atropos build.
