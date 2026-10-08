# EES model workflow

Read this fallback when the selected project has no EES-specific workspace instructions or those instructions do not fully cover the requested operation; use only the missing guidance. When invoking an installed helper, use the `$config` object selected by the router and set `$workspaceRoot` to the task's project root, normally `$config.workspace_root`. For write-only or existing-result review without a helper, use the user-selected project root and skip helper-only sections. Configuration is installation information, not permission to modify other locations.

## Without executable EES

For write-only work or review of existing files, no launcher configuration or EES edition is required. Keep new files under the user-selected project root. Skip catalog, compile-test, and execution steps. Statically inspect supplied source and results for equations, units, constraints, balances, physical feasibility, and the export contract. Clearly state that compilation, execution, result freshness, and result provenance were not verified.

## Find an installed routine

Before recreating a heat-transfer correlation or component model, search the selected installation's catalog and then inspect one candidate:

```powershell
& (Join-Path $config.install_directory 'Search-EES-Library.ps1') `
  -Query 'compressor constant efficiency' -EesPath $config.ees_path -Limit 5
& (Join-Path $config.install_directory 'Get-EES-Routine.ps1') `
  -RoutineID 'Compressor2_CL' -EesPath $config.ees_path
```

Keep search results concise and never load the full catalog JSON. The Database22 catalog contains calling metadata, not executable libraries. An `installed_metadata_match` is discovery evidence, not proof that the routine and its dependencies will compile. When executable EES is available, verify the selected signature, parameter meanings, and units with a small EES compile test before building around it.

The launcher passes `/AI`, making all five EES application libraries available for a controlled run without changing persistent autoload preferences. A returned `required_load_directive` is therefore optional for a controlled run; include it exactly when portability to an ordinary EES session is useful. The only permitted `$Load` directives are `$Load Component Library`, `$Load Mechanical`, `$Load NASA`, and `$Load Incompressible`.

## Write and solve

1. Identify inputs, unknowns, constraints, and material assumptions. Distinguish user-supplied values from estimates, and ask only for missing information that materially changes the model. Use EES thermophysical-property functions and explicit units where appropriate.
2. Write an EES equation `.txt` file under the selected workspace. Include exactly one `{{OUTPUT_FILE}}` placeholder on exactly one `$Export` or `$ExportText` directive. If export syntax is uncertain, consult the installed `examples\heat_exchanger.txt` or `examples\water_heater.txt`; do not load examples otherwise.
3. Export only the inputs, states, constraints, performance quantities, and balance residuals needed to audit the answer. Use a new result filename for a material iteration; use `-Force` only for an intentional replacement.
4. Run the installed launcher:

```powershell
$workspaceRoot = $config.workspace_root
& (Join-Path $config.install_directory 'Run-EES.ps1') `
  -WorkspaceRoot $workspaceRoot `
  -ProgramPath (Join-Path $workspaceRoot 'models\model.txt') `
  -OutputPath (Join-Path $workspaceRoot 'results\model-results.txt') `
  -EesPath $config.ees_path `
  -TimeoutSeconds 120
```

For another user-selected project, set `$workspaceRoot` to that project's absolute path before the command; the workspace, program, and output arguments must all use it. Keep the model and result beneath that root. Do not change the installed launcher's global configuration merely to work in another project.

5. Read the launcher status and the fresh exported result. Check units, conservation balances, physical feasibility, requested constraints, and sensitivity to important assumptions. Revise and rerun when needed. A successful process or nonempty export alone does not establish correctness.

Do not add `$Python`, `$Include`, macro-running, importing, arbitrary file-writing directives, or other actions rejected by the launcher. If the requested model requires an unsupported action, explain the limitation instead of weakening the launcher.
