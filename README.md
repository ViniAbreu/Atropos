<div align="center">
  <img src="doc/atropos-logo.png" alt="Atropos Logo" width="150">
  <h1>Atropos</h1>
  <p><strong>Automated uses clause optimizer for Delphi projects</strong></p>
  <p>
    <a href="https://github.com/ViniAbreu/Atropos/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/ViniAbreu/Atropos?style=flat-square&color=blue"></a>
    <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-GPLv3-green?style=flat-square"></a>
  </p>
</div>

Atropos cleans and optimizes the `uses` clauses of Delphi projects (`.dproj`). It parses the source code to remove unused dependencies and can move dependencies from the `interface` to the `implementation` block.

Before changing any source file, Atropos builds the original project to establish a healthy baseline. It builds the project again after the optimization and either commits the operation or automatically rolls it back.

> ⚠️ **Atropos modifies source code.** Use version control, review the generated diff, and read the [safety and rollback model](docs/safety-and-rollback.md) before your first production use.

## 💡 Why Atropos? (Benefits)

Over time, Delphi projects accumulate "ghost dependencies": units added by the IDE or developers that are no longer used. A surgical, automated cleanup of `uses` clauses provides several benefits:

- ⚡ **Faster compilation:** The compiler parses fewer files. Moving internal dependencies to `implementation` also prevents unnecessary recompilation cascades.
- 📉 **Smaller executables:** Removing unused dependencies helps the linker discard unreachable code.
- 🧠 **Better IDE performance:** Cleaner dependencies reduce work for Code Insight and the Language Server Protocol.
- 🏗️ **Lower coupling:** Keeping implementation details out of the interface improves encapsulation and reduces dependencies between units.

## ⚙️ How it works

1. **Project parsing:** Reads the active configuration, units, and search paths from the `.dproj` file.
2. **Healthy baseline:** Locates RAD Studio and builds the original project before changing files.
3. **AST analysis:** Uses [DelphiAST](https://github.com/RomanYankovsky/DelphiAST) to inspect the source code and exported symbols.
4. **Conservative optimization:**
   - removes units that are proven to be unused;
   - moves interface dependencies used only by the implementation;
   - preserves units when the analysis cannot prove that a change is safe.
5. **Transactional update:** Creates backups before writing source files.
6. **Build verification:** Rebuilds the project and commits the changes or restores the original files.
7. **Report:** Shows a summary and, when requested by the CLI, writes TXT and/or HTML reports.

Units that cannot be resolved, contain initialization behavior, or use syntax that cannot be handled safely are preserved. See the [known limitations](docs/known-limitations.md) for details.

## 🚀 Getting Started

Download the executables from the [Releases page](https://github.com/ViniAbreu/Atropos/releases/latest). You can use either the graphical interface (`AtroposVCL.exe`) or the command-line interface (`AtroposCLI.exe`).

### Building from source

DelphiAST is tracked as a Git submodule. Clone the repository and its dependencies with:

```bash
git clone --recurse-submodules https://github.com/ViniAbreu/Atropos.git
```

If the repository was already cloned, initialize the dependency before building:

```bash
git submodule update --init --recursive
```

See the complete [installation and build guide](docs/installation.md) for supported tools and projects.

### CLI usage

```powershell
AtroposCLI.exe -dproj "C:\Projects\MyApplication\MyApplication.dproj" --remove --move -html -txt
AtroposCLI.exe -dproj "C:\Projects\MyApplication\MyApplication.dproj" --remove -txt --output reports
AtroposCLI.exe -dproj "C:\Projects\MyApplication\MyApplication.dproj" --remove --dry-run -html -txt
```

Common options:

- `-dproj <path>`: path to the Delphi project file;
- `--remove`: remove dependencies proven to be unused;
- `--move`: move eligible dependencies from `interface` to `implementation`;
- `--dry-run`: report optimization candidates without modifying source files;
- `-html`: generate an HTML report;
- `-txt`: generate a text report;
- `--output <directory>`: select the report directory;
- `--debug`: enable verbose logging;
- `--help`: display the complete command reference.

Without `--remove` or `--move`, Atropos performs the initial validation but does not request source changes. Use `--dry-run` to review candidates and generate reports without modifying source files. See the [CLI reference](docs/cli.md) for the complete contract and exit codes.

## 🧪 Quality and compatibility

- ✅ Automated unit and integration tests run on Win32 and Win64.
- ✅ CLI and VCL builds are validated on both architectures.
- ✅ Smoke tests exercise compilation, optimization, reporting, rollback, and fixture preservation.
- ✅ Line coverage is protected by a minimum quality gate.
- ✅ DelphiAST is pinned as a Git submodule.

Consult the [compatibility matrix](docs/compatibility.md) to distinguish validated environments from versions only recognized by the resolver.

## 📚 Documentation

- [Installation and build](docs/installation.md)
- [CLI reference](docs/cli.md)
- [VCL interface](docs/gui.md)
- [Safety and rollback](docs/safety-and-rollback.md)
- [Testing and coverage](docs/testing.md)
- [Architecture](docs/architecture.md)
- [Compatibility](docs/compatibility.md)
- [Known limitations](docs/known-limitations.md)
- [Release process](docs/release.md)

## 🤝 Contributing

We welcome all forms of contribution:

- 🐛 **Report bugs and suggest features:** open an [issue](https://github.com/ViniAbreu/Atropos/issues).
- 💻 **Submit code:** read the [contribution guide](CONTRIBUTING.md) and open a pull request.
- ⭐️ **Show support:** give the project a star.
- ☕ **Donate:** support the project financially to help keep it active.

## 📄 License

[GNU General Public License v3.0](LICENSE).
