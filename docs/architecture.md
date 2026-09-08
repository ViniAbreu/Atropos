# Architecture

```text
CLI / VCL -> Application Service -> Core (domain and ports)
                                      ^
                                      |
          Adapters (AST, XML, files, build, environment, reports)
```

## Layers

- `src\Core`: models, configuration, rules, modifier, and ports. It does not know about UI or infrastructure.
- `src\Application`: orchestrates environment discovery, builds, analysis, commit, rollback, logs, and progress.
- `src\Adapters`: integrates DelphiAST, `.dproj`, external units, files, BDS, the registry, and reports.
- `src\CLI` and `src\GUI`: presentation contracts over the same application service.

Adapters and presentation depend on Core abstractions. The domain must not import VCL, XML, registry, filesystem, or DelphiAST units. New integrations must implement a port and be connected by the factory.

Main adapter responsibilities:

- `DelphiAST`: syntactic view of source files;
- `ProjectParser`: conditional properties, units, search paths, recursive property expansion, and diagnostics for unsupported MSBuild expressions;
- `ExternalUnitResolver`: unit location and exported symbols;
- `FileSystem`: encoding-aware I/O, exclusive project locks, and SHA-256-verified backup transactions with versioned manifests;
- `BuildService`: AutoBuild, timeout, cancellation, and metrics;
- `DelphiEnvironment`: project version and RAD Studio installation discovery;
- `ReportGenerator`: text and HTML output.
