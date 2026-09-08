# CLI reference

```text
AtroposCLI.exe -dproj <file.dproj> [options]
```

| Option | Effect |
| --- | --- |
| `-dproj <file>` | Project to analyze; required except when requesting help. |
| `--remove` | Remove units classified as unused. |
| `--move` | Move units used only by `implementation` into that section. |
| `-html` | Write `AtroposReport.html`. |
| `-txt` | Write `AtroposReport.txt`. |
| `--output <directory>` | Report directory; a relative path starts at the `.dproj` directory. |
| `--dry-run` | Analyze and report candidates without modifying source files. |
| `--target <configuration\|platform>` | Validate a target before and after processing; repeat to create a matrix. |
| `--debug` | Enable detailed diagnostics. |
| `--log <file>` | Write the persistent UTF-8 execution log to a specific file. By default, logs are stored under `%LOCALAPPDATA%\Atropos\Logs`. |
| `--help`, `-h`, `/?` | Display help. |

Without `--output`, requested reports are written next to the project. The text summary is also printed to the console without `-txt`.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Success, including when no changes are necessary. |
| `1` | Operational failure, final-build failure, or exception. |
| `2` | Invalid option, missing value, or nonexistent project. |

```powershell
& .\AtroposCLI.exe -dproj $project --remove -txt --output reports
if ($LASTEXITCODE -ne 0) { throw "Atropos failed: $LASTEXITCODE" }
```

The CLI has no interactive cancellation option. Start from a clean branch, review the diff, and do not run two instances against the same source files.
