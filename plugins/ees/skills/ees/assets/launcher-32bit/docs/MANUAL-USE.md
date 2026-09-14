# Manual PowerShell use

Codex is optional. You can write an EES text program yourself and run it through the same launcher.

## Run the included example

Open PowerShell and run:

```powershell
$config = Get-Content "$env:USERPROFILE\Documents\EES-Codex-Workspace-32bit\launcher-config.json" -Raw | ConvertFrom-Json
& "$env:LOCALAPPDATA\EES-Codex-Launcher-32bit\Run-EES.ps1" `
  -WorkspaceRoot $config.workspace_root `
  -ProgramPath "$($config.workspace_root)\examples\heat_exchanger.txt" `
  -OutputPath "$($config.workspace_root)\results\manual_test.txt" `
  -EesPath $config.ees_path `
  -TimeoutSeconds 30 `
  -Force
```

Read the result:

```powershell
Get-Content "$env:USERPROFILE\Documents\EES-Codex-Workspace-32bit\results\manual_test.txt"
```

## Required EES source contract

The input must be a `.txt` file below the configured workspace. It must contain exactly one output placeholder on exactly one `$Export` or `$ExportText` directive:

```text
$Export /H /V /U /N '{{OUTPUT_FILE}}' T_hot, T_cold, UA, Q_dot
```

Use explicit units and export the inputs, constraints, primary results, and residuals needed to assess the model. The launcher replaces the placeholder with a unique staged result path.

## Search installed EES routines

```powershell
& "$env:LOCALAPPDATA\EES-Codex-Launcher-32bit\Search-EES-Library.ps1" `
  -Query 'compact heat exchanger pressure drop' `
  -Limit 5
```

The command returns concise JSON containing ranked candidate routines, primary syntax, categories, and installation paths.

Inspect the complete signatures and parameters for one result:

```powershell
& "$env:LOCALAPPDATA\EES-Codex-Launcher-32bit\Get-EES-Routine.ps1" `
  -RoutineID 'Blackbody'
```

The detailed result includes parameters. Numeric `unit_type_code` values are not self-describing in the currently installed JSON, so confirm units from the routine documentation or a compile test.

If a result contains `required_load_directive`, copy that exact directive to the beginning of the EES program. For example, component models normally require:

```text
$Load Component Library
```

## Retest the installation

Double-click **Test Installation.cmd** in the extracted package, or run:

```powershell
& "$env:LOCALAPPDATA\EES-Codex-Launcher-32bit\Test-Installation.ps1"
```
