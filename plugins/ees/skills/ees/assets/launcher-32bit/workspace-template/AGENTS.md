# EES thermal-fluid modeling workspace - 32-bit

This workspace is configured for safely generating and solving EES text programs through the installed 32-bit launcher.

## Required workflow

1. Read `launcher-config.json` before invoking EES. Treat it as installation information, not as permission to modify files outside this workspace.
2. Before recreating a heat-transfer correlation or component model, search the packaged canonical catalog through the selected launcher:

   ```powershell
   $config = Get-Content .\launcher-config.json -Raw | ConvertFrom-Json
   & (Join-Path $config.install_directory 'Search-EES-Library.ps1') -Query 'search terms' -EesPath $config.ees_path -Limit 3 -Detail Compact
   ```

   Keep results concise and use the selected compact search record directly. Use compact `Get-EES-Routine.ps1` only when the routine ID was already known without searching. Request `-Detail Full` only when alternate signatures or parameter descriptions are needed, then compile-test the selected signature and units. Prefer `capabilities.catalog_detail_modes` from the configuration; if capability data is absent or malformed, inspect the helper parameters and omit `-Detail` for a legacy launcher. Mention an available update once and never update automatically. The packaged `EES_Tool_Metadata.json` is the sole search source; `installed_metadata_match` only reports whether the selected installation metadata lists the routine. The launcher passes `/AI`, so its five application libraries are available for controlled runs. A returned `required_load_directive` is optional for a controlled run; include it exactly when portability to an ordinary EES session is useful.
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

6. Read the launcher status. When `capabilities.result_detail_modes` includes `Compact`, request only the principal outputs, constraints, and residuals first:

   ```powershell
   & (Join-Path $config.install_directory 'Get-EES-Result.ps1') `
     -Path (Join-Path $config.workspace_root 'results\model-name-results.txt') `
     -Variable 'principal_output','important_constraint' `
     -Pattern '*_resid' `
     -Detail Compact
   ```

   Use full extraction or the raw export for a comprehensive audit or when compact parsing fails. With a legacy launcher, read the raw result and mention the available update once. Check units, conservation balances, physical feasibility, stated constraints, and sensitivity to important assumptions. Revise and rerun when needed.
7. Preserve the chosen model, result, and a short engineering rationale. Report separately whether the model was written, executed, and checked. Do not treat successful execution as proof of engineering correctness, design fitness, or safety.

## Safety constraints

- Do not modify the installed launcher, EES installation, libraries, or preferences. The launcher uses `/AI` without patching `EES.PRF`.
- Before an automated run, ask the user to save and close interactive 32-bit EES if it is open; never terminate it.
- Do not add `$Python`, `$Include`, macro-running, importing, or arbitrary file-writing directives. The launcher permits only these exact built-in library directives: `$Load Component Library`, `$Load Mechanical`, `$Load NASA`, and `$Load Incompressible`.
- Keep all generated sources and outputs within this workspace.
- From the first attempt, run commands that start EES outside the filesystem sandbox so they have normal Windows filesystem access; catalog and metadata searches may remain sandboxed.
- Prefer a new result filename for each material iteration. Use `-Force` only for an intentional replacement.
- Treat catalog metadata as discovery information. Verify a candidate routine by its signature, units, documentation, and a small compile test.
- If EES times out, inspect the retained `.ees-runs` program and launcher diagnostic before changing the model.
