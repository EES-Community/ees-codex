---
name: ees
description: Write, solve, and debug Engineering Equation Solver (EES) thermal-fluid models, search EES library routines, and inspect exported results using a local Windows EES Professional installation. Use for EES model work or EES launcher setup.
---

# Engineering Equation Solver

Use the bundled EES Codex Launcher to solve equation text with the user's installed EES Professional. EES performs the calculations; this skill supplies the modeling workflow and library lookup tools.

## Connect to EES

Find `launcher-config.json` in the user's selected project, or read the installed launcher's `config.json` under `%LOCALAPPDATA%\EES-Codex-Launcher-32bit` or `%LOCALAPPDATA%\EES-Codex-Launcher-64bit`. Read only those known locations first. Respect the user's chosen project and EES edition. If both editions are configured and no preference is given, ask which to use.

If setup is missing or the user requests installation, read [references/setup.md](references/setup.md). The launchers require Windows, PowerShell 5.1 or 7, and EES Professional supporting `/solve` and `/AI`. On another OS, help write or inspect models but do not claim to have solved them or silently install Wine or a replacement solver.

Run the installed helpers identified by `install_directory` in the configuration. The plugin's bundled assets are installation sources. Do not modify the installed launcher or EES preferences to make a model run.

## Find a routine

Before recreating a correlation or component model, search the catalog and inspect a candidate's signature:

```powershell
$config = Get-Content .\launcher-config.json -Raw | ConvertFrom-Json
& (Join-Path $config.install_directory 'Search-EES-Library.ps1') `
  -Query 'compressor constant efficiency' -EesPath $config.ees_path -Limit 5
& (Join-Path $config.install_directory 'Get-EES-Routine.ps1') `
  -RoutineID 'Compressor2_CL' -EesPath $config.ees_path
```

The bundled Database22 catalog contains calling metadata, not executable libraries. An `installed_metadata_match` is not proof that all dependencies are available. Verify a selected signature with a small EES model before building around it. Use the search helpers rather than loading the full catalog JSON into context.

## Write and solve

1. Identify the requested inputs, unknowns, constraints, and assumptions. Use EES property functions and explicit units. Ask for missing inputs when they materially determine the model; distinguish estimates from supplied values.
2. Write a `.txt` equation program inside the selected workspace. Include exactly one `{{OUTPUT_FILE}}` placeholder on exactly one `$Export` or `$ExportText` directive. See the installed `examples/heat_exchanger.txt` and `examples/water_heater.txt` for working formats.
3. Export the variables needed to inspect the result: relevant inputs, states, performance quantities, and balance residuals. Choose a new output filename for a material iteration; use `-Force` only for an intentional replacement.
4. Invoke the installed launcher:

```powershell
& (Join-Path $config.install_directory 'Run-EES.ps1') `
  -WorkspaceRoot $config.workspace_root `
  -ProgramPath (Join-Path $config.workspace_root 'models\model.txt') `
  -OutputPath (Join-Path $config.workspace_root 'results\model-results.txt') `
  -EesPath $config.ees_path -TimeoutSeconds 120
```

5. Read the launcher's status and the fresh exported file. Check units, balances, physical feasibility, requested constraints, and sensitivity where it matters. A successful process or a nonempty export alone does not establish engineering correctness. Preserve the model and result and explain the relevant assumptions and checks.

For another user-selected project, supply that project's absolute path as `-WorkspaceRoot` and keep both model and result under it; the launcher accepts a workspace per invocation. Do not change the installation's global configuration merely to work in another project. The bundled installation test still uses its original configured workspace.

## Execution constraints and failures

- EES is launched with `/solve /nosplash /AI`; the launcher uses `/AI` to make the five application libraries available for that run without editing preferences.
- The matching interactive EES process must be closed before an automated solve. If the launcher reports an existing process, ask the user to save and close it; do not terminate their interactive session.
- Keep source and result paths inside the selected workspace. The launcher accepts equation `.txt` files, not native binary `.ees` files. Request or produce an EES text export when needed; do not rename a binary file to `.txt`.
- Do not bypass the launcher's directive checks. It rejects external-code, import, macro, and several extra-output directives. Its exact permitted `$Load` directives are Component Library, Mechanical, NASA, and Incompressible. If a requested model needs an unsupported action, explain the limitation instead of weakening the launcher.
- On failure, inspect the JSON diagnostic and retained `.ees-runs` program. A timeout may be a hidden compile/solve dialog; inspect its captured text before retrying. Correct the indicated model issue; do not repeatedly rerun an unchanged failing model or silently increase the timeout.
- Report separately whether a model was written, executed by EES, and checked. Do not present an unexecuted model as verified or a generated design as professionally certified.
