# EES thermal-fluid modeling workspace - 64-bit

This workspace is configured for safely generating and solving EES text programs through the installed 64-bit launcher.

## Required workflow

1. Read `launcher-config.json` before invoking EES. Treat it as installation information, not as permission to modify files outside this workspace.
2. Before recreating a heat-transfer correlation or component model, search the packaged canonical catalog through the selected launcher:

   ```powershell
   $config = Get-Content .\launcher-config.json -Raw | ConvertFrom-Json
   & (Join-Path $config.install_directory 'Search-EES-Library.ps1') -Query 'search terms' -EesPath $config.ees_path -Limit 3 -Detail Compact
   ```

   Keep results concise. Inspect one candidate with `Get-EES-Routine.ps1 -RoutineID '<id>' -EesPath $config.ees_path -Detail Compact`. Request `-Detail Full` only when its alternate signatures or parameter descriptions are needed, then compile-test the selected signature and units. The packaged `EES_Tool_Metadata.json` is the sole search source; `installed_metadata_match` only reports whether the selected installation metadata lists the routine. The launcher passes `/AI`, so its five application libraries are available for controlled runs. A returned `required_load_directive` is optional for a controlled run; include it exactly when portability to an ordinary EES session is useful.
3. Identify inputs, unknowns, constraints, and material assumptions. Distinguish user-supplied values from estimates, and ask only for missing information that materially changes the model. Write EES equation programs as `.txt` files inside this workspace. Use EES thermophysical-property functions and explicit units where appropriate.
4. Include exactly one `{{OUTPUT_FILE}}` placeholder on exactly one `$Export` or `$ExportText` directive. Export only the inputs, states, constraints, engineering performance, and balance residuals needed to audit the result.
5. Run only the installed launcher identified by `install_directory`:

   ```powershell
   $config = Get-Content .\launcher-config.json -Raw | ConvertFrom-Json
   & (Join-Path $config.install_directory 'Run-EES.ps1') `
     -WorkspaceRoot $config.workspace_root `
     -ProgramPath (Join-Path $config.workspace_root 'models\model-name.txt') `
     -OutputPath (Join-Path $config.workspace_root 'results\model-name-results.txt') `
     -EesPath $config.ees_path `
     -TimeoutSeconds 120
   ```

6. Read the launcher status and fresh result. Check units, conservation balances, physical feasibility, stated constraints, and sensitivity to important assumptions. Revise and rerun when needed.
7. Preserve the chosen model, result, and a short engineering rationale. Report separately whether the model was written, executed, and checked. Do not treat successful execution as proof of engineering correctness, design fitness, or safety.

## Safety constraints

- Do not modify the installed launcher, EES installation, libraries, or preferences. The launcher uses `/AI` without patching `EES.PRF64`.
- Before an automated run, ask the user to save and close interactive 64-bit EES if it is open; never terminate it.
- Do not add `$Python`, `$Include`, macro-running, importing, or arbitrary file-writing directives. The launcher permits only these exact built-in library directives: `$Load Component Library`, `$Load Mechanical`, `$Load NASA`, and `$Load Incompressible`.
- Keep all generated sources and outputs within this workspace.
- From the first attempt, run commands that start EES outside the filesystem sandbox so they have normal Windows filesystem access; catalog and metadata searches may remain sandboxed.
- Prefer a new result filename for each material iteration. Use `-Force` only for an intentional replacement.
- Treat catalog metadata as discovery information. Verify a candidate routine by its signature, units, documentation, and a small compile test.
- If EES times out, inspect the retained `.ees-runs` program and launcher diagnostic before changing the model.
