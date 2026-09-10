# Evaluated project context

`IProjectContextProvider` and `TMsBuildProjectContext` provide the evaluation stage
for the upcoming per-target analysis pipeline. They are compiled and tested but are
not yet selected by `TAppServiceFactory`. The active application still uses the
existing project parser and AST compiler defaults; this increment does not claim to
correct conditional analysis in CLI or VCL.

The provider runs the installed .NET Framework MSBuild evaluation API in an isolated
Windows PowerShell process under the selected Delphi `rsvars.bat` environment. It
does not run build targets. Configuration and platform are MSBuild global properties,
so project assignments cannot override an explicitly requested target. An empty
target requests the project's defaults. The request is JSON encoded inside a
temporary script; project paths are not interpolated into shell commands. Responses
are UTF-8 JSON encoded as Base64 to preserve Unicode across console code pages.

The result records evaluated defines, ordered source/include paths, namespaces,
aliases, compiler option property values, active PAS `DCCReference` items, main
source, compiler path and executable file version. Imported property files and
property functions are evaluated by MSBuild. Root/import hashes are checked across
two evaluations to reject changed inputs; returned project-file hashes can later
extend the application snapshot. Each call starts a fresh process and evaluation.

Missing imports, malformed output, process failure, timeout and cancellation fail
explicitly. There is no fallback that treats failed evaluation as an empty context.
Temporary scripts are removed after the process finishes or is terminated. The
existing process runner supplies cancellation, timeout and process-tree cleanup.

## Boundaries before activation

- Evaluated properties are not necessarily the final compiler invocation. Targets
  may change properties or items or produce task outputs during a build. Direct
  compiler-related property groups in targets are listed in `DeferredProperties`;
  that list is not exhaustive proof that no other deferred effects exist.
- Empty option values remain unknown, rather than being converted to false.
  Executable file version is not Delphi's `CompilerVersion` constant. Compiler
  predefined symbols and effective switches still need explicit derivation.
- The result contains ordered alias and namespace settings; binding and source
  resolution do not consume them yet. DPR `uses ... in` mappings and generated units
  require further extraction.
- The application must analyze every selected target with its own parser/resolver
  context, combine only compatible decisions, include target-exclusive units, and
  validate project metadata before writing. Simply unioning search paths or defines
  would lose target identity and is not an acceptable integration.
- Windows PowerShell and .NET Framework MSBuild are required. PowerShell execution
  policy failures remain explicit; this adapter does not override machine policy.

The DUnitX fixture `Atropos.Tests.ProjectContext` executes the real evaluation API
against temporary projects for all four Debug/Release and Win32/Win64 combinations,
imports, property functions, global-property precedence, Unicode paths, conditional
items, changed imports and deferred property detection. It proves evaluation does
not execute a target that would write a marker file. These tests do not yet promote
the research end-to-end project-context scenarios.
