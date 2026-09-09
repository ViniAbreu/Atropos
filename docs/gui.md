# VCL interface

Run `AtroposVCL.exe`, select a `.dproj`, and choose:

- **Remove Unused:** remove unused dependencies;
- **Move to Implementation:** move dependencies used only by the implementation;
- **Enable Debug Logging:** show detailed processing information.

Click **Iniciar Limpeza** (Start Cleanup). The progress bar tracks the units, while the log panel records builds and decisions. **Cancelar** (Cancel) requests a safe interruption; the window cannot close while execution is active. Completion is synchronized with the UI after success, validation failure, cancellation, or exception, so the window becomes closable as soon as the worker stops. Cancellation and exceptions restore the transaction backups.

## Current limitation

The VCL interface does not yet export HTML/TXT reports or select an output directory. Use the CLI to persist reports; the text summary appears in the log panel.
