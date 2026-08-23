<div align="center">
  <img src="doc/atropos-logo.png" alt="Atropos Logo" width="150">
  <h1>Atropos</h1>
  <p><strong>Automated uses clause optimizer for Delphi projects</strong></p>
  <p>
    <a href="https://github.com/ViniAbreu/Atropos/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/ViniAbreu/Atropos?style=flat-square&color=blue"></a>
    <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-GPLv3-green?style=flat-square"></a>
  </p>
</div>

Atropos cleans and optimizes the `uses` clauses of your Delphi projects (`.dproj`). It safely parses your code to remove unused dependencies and moves units to the `implementation` block when applicable.

If the project fails to compile after the optimization, **Atropos automatically rolls back** all changes.

## 💡 Why Atropos? (Benefits)

Over time, Delphi projects accumulate "ghost dependencies" (units added by the IDE or developers that are no longer used). A surgical, automated clean-up of your `uses` clauses provides immense benefits:

- ⚡ **Faster Compilation:** The compiler parses fewer files. Furthermore, moving dependencies from the `interface` down to the `implementation` prevents a cascade of unnecessary recompilations across your project when a unit changes.
- 📉 **Smaller Executables:** Eliminating unused dependencies ensures the linker drops dead code, resulting in leaner binaries.
- 🧠 **IDE Performance (LSP/Code Insight):** A clean `uses` clause drastically reduces the workload on the Delphi Code Insight and Language Server Protocol (LSP), meaning a faster, more responsive autocomplete experience.
- 🏗️ **Lower Coupling (Better Encapsulation):** By moving internal dependencies down to the `implementation` block, you effectively hide the unit's internal workings from the rest of the project. This prevents code entanglement and makes your architecture naturally more decoupled.

## ⚙️ How it works

1. **Project Parsing:** Atropos first parses your `.dproj` file to capture and analyze all the units included in your project, ensuring it has the full context.
2. **AST Engine:** Powered by the `DelphiAST` library, it generates and reads the Abstract Syntax Tree (AST) of your `.pas` files.
3. **Deep Analysis:** It cross-references the identifiers used in your code against the exported symbols of your imported units.
4. **Smart Optimization:**
   - Units that are completely unused are safely removed.
   - Units present in the `interface` uses clause that are only needed in the `implementation` block are automatically downgraded (moved to the implementation clause).
   - *Note: Units that cannot be located in the search paths, units that contain an `initialization` block, or units wrapped in compiler directives (`{$IFDEF}`, etc.) are strictly ignored to prevent side effects.*
5. **Fail-Safe Mechanism:** It automatically builds your project in the background. If the cleanup breaks the compilation, a full rollback is instantly applied. You never lose code.

## 🚀 Getting Started

Download the latest release from the [Releases page](https://github.com/ViniAbreu/Atropos/releases/latest). You can use either the GUI (`AtroposVCL.exe`) or the command line interface (`AtroposCLI.exe`).

### CLI Usage

```bash
AtroposCLI.exe -dproj "C:\Path\To\Project.dproj" --remove --move -html
```

**Options:**
- `-dproj <path>`: Path to your `.dproj` file.
- `--remove`: Remove unused units.
- `--move`: Move units from interface to implementation if applicable.
- `-html`: Generate HTML report.
- `-txt`: Generate TXT report.
- `--debug`: Enable verbose logging.

## 🤝 Contributing

We welcome all forms of contribution! Here are a few ways you can help:
- 🐛 **Report Bugs & Suggest Features:** Open an [Issue](https://github.com/ViniAbreu/Atropos/issues).
- 💻 **Submit Code:** Open a Pull Request. Please read our guidelines in the `.agents/skills` folder before submitting!
- ⭐️ **Show Support:** Give us a Star on GitHub!
- ☕ **Donate:** Consider supporting the project financially to help keep it active.

## 📄 License
GPL-3.0 License.
