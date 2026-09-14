# EES thermal-fluid modeling workspace

This workspace is configured for safely generating and solving EES text programs through an installed launcher.

## Required workflow

1. Read `launcher-config.json` before invoking EES. Treat it as installation information, not as permission to modify files outside this workspace.
2. Search the selected installation's library catalog before reimplementing a heat-transfer correlation or component model:

   ```powershell
   $config = Get-Content .\launcher-config.json -Raw | ConvertFrom-Json
   & (Join-Path $config.install_directory 'Search-EES-Library.ps1') -Query 'search terms' -EesPath $config.ees_path -Limit 10
   ```

   Keep search results concise. For one candidate, retrieve the complete signatures and parameters with `Get-EES-Routine.ps1 -RoutineID '<id>' -EesPath $config.ees_path`. The 32-bit launcher passes `/AI` so all five EES application libraries are available for every controlled solve. A catalog `required_load_directive` may still be included for portability to ordinary EES sessions, but it is not required by this launcher.

3. Write EES equation programs as `.txt` files inside this workspace. Use EES thermophysical property functions and explicit units when appropriate.
4. Include exactly one `{{OUTPUT_FILE}}` placeholder on exactly one `$Export` or `$ExportText` directive. Export inputs, states, constraints, engineering performance, and balance residuals needed to audit the result.
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

6. Read the fresh result and check units, conservation balances, physical feasibility, stated constraints, and sensitivity to important assumptions. Revise and rerun when needed.
7. Preserve the chosen model, its result, and a short engineering rationale. Do not present generated designs as professionally certified.

## Safety constraints

- Do not modify the installed launcher or EES installation. Close interactive 32-bit EES before a launcher run; the launcher serializes automated solves and uses `/AI` without patching `EES.PRF`.
- Do not add `$Python`, `$Include`, macro-running, importing, or arbitrary file-writing directives. The launcher permits only these exact built-in library directives when the catalog calls for them: `$Load Component Library`, `$Load Mechanical`, `$Load NASA`, and `$Load Incompressible`.
- Keep all generated sources and outputs within this workspace.
- Prefer a new result filename for each material design iteration. Use `-Force` only for an intentional replacement.
- Treat EES library metadata as discovery information. Verify a candidate routine by its signature, units, documentation, and a small compile test.
- If EES times out, inspect the retained `.ees-runs` program and the launcher diagnostic before changing the model.
