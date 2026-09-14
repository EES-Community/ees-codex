# EES thermal-fluid modeling workspace — 64-bit

This workspace is configured for safely generating and solving EES text programs through the installed 64-bit launcher.

## Required workflow

1. Read `launcher-config.json` before invoking EES.
2. Search the selected installation's library catalog before reimplementing a heat-transfer correlation or component model. Retrieve a candidate's complete details with `Get-EES-Routine.ps1`, then compile-test it. The launcher passes `/AI` so all five EES application libraries are available during every controlled solve.
3. Write EES programs as `.txt` files inside this workspace. Include exactly one `{{OUTPUT_FILE}}` placeholder on one `$Export` or `$ExportText` directive.
4. Run only the installed `Run-EES.ps1` identified by `install_directory`, passing the configured workspace and `ees_path`.
5. Read the fresh result and check units, balances, physical feasibility, constraints, and important sensitivities.

## Safety constraints

- Do not modify the installed launcher or EES installation. Close interactive 64-bit EES before a launcher run; the launcher serializes automated solves and uses `/AI` without patching `EES.PRF64`.
- Do not add `$Python`, `$Include`, macro-running, importing, or arbitrary file-writing directives. Only the launcher's exact built-in `$Load` whitelist is permitted.
- Keep generated sources and outputs inside this workspace.
- Prefer a new result filename for each material iteration. Use `-Force` only for an intentional replacement.
- Treat catalog metadata as discovery information and compile-test every candidate routine.
