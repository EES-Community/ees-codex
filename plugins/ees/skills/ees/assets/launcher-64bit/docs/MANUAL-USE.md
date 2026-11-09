# Manual PowerShell use

Codex is optional. You can write an EES text program yourself and run it through the same launcher.

## Run the included example

Open PowerShell and run:

```powershell
$config = Get-Content "$env:USERPROFILE\EES-Codex-Workspace-64bit\launcher-config.json" -Raw | ConvertFrom-Json
& "$env:LOCALAPPDATA\EES-Codex-Launcher-64bit\Run-EES.ps1" `
  -WorkspaceRoot $config.workspace_root `
  -ProgramPath "$($config.workspace_root)\examples\heat_exchanger.txt" `
  -OutputPath "$($config.workspace_root)\results\manual_test.txt" `
  -EesPath $config.ees_path `
  -TimeoutSeconds 30 `
  -Force
```

Read only the principal result and related residuals:

```powershell
& "$env:LOCALAPPDATA\EES-Codex-Launcher-64bit\Get-EES-Result.ps1" `
  -Path "$env:USERPROFILE\EES-Codex-Workspace-64bit\results\manual_test.txt" `
  -Variable 'Q_dot' `
  -Pattern '*_resid' `
  -Detail Compact
```

Use `-Detail Full` without selectors, or `Get-Content`, when you need the complete export.

Read the JSON returned by `Run-EES.ps1` before parsing the export. If `update_check.update_available` is true, its message identifies the installed and current launcher versions; the notification does not change the solve result or install anything. With EES 12.358 or newer, `ees_message_supported` is true; if `ees_message_present` is also true, inspect `ees_message` and the retained `ees_message_snapshot` even when `status` is `success`. The launcher deletes the previous fixed `EES_Msg.txt` only after acquiring its run lock, then snapshots the fresh file before another run can replace it. Older EES versions report message capture as unsupported and retain the existing export/window-text behavior.

## Required EES source contract

The input must be a `.txt` file below the configured workspace. It must contain exactly one output placeholder on exactly one `$Export` or `$ExportText` directive:

```text
$Export /H /V /U /N '{{OUTPUT_FILE}}' T_hot, T_cold, UA, Q_dot
```

Use explicit units and export the inputs, constraints, primary results, and residuals needed to assess the model. The launcher replaces the placeholder with a unique staged result path.

## Add a validated plot or data file

The primary text export is always required. For an additional EES file, put an uppercase placeholder on a supported file directive and declare its workspace destination in a version 1 artifact manifest. The included `examples\property_plot.txt` and `examples\property_plot-artifacts.json` demonstrate `$ExportPlot`.

```powershell
& "$env:LOCALAPPDATA\EES-Codex-Launcher-64bit\Run-EES.ps1" `
  -WorkspaceRoot $config.workspace_root `
  -ProgramPath "$($config.workspace_root)\examples\property_plot.txt" `
  -OutputPath "$($config.workspace_root)\results\manual_property_plot.txt" `
  -ArtifactManifestPath "$($config.workspace_root)\examples\property_plot-artifacts.json" `
  -EesPath $config.ees_path `
  -TimeoutSeconds 120 `
  -Force
```

The launcher validates and stages the file, then returns it in `output_artifacts`. Supported validated input directives are `$Import`, `$ImportText`, and `$OpenLookup`; supported outputs are `$Export`, `$ExportText`, `$ExportPlot`, `$SaveLookup`, `$SaveTable`, and `$SaveVarInfo`. Literal and undeclared file paths remain blocked.

## Search packaged EES metadata

```powershell
& "$env:LOCALAPPDATA\EES-Codex-Launcher-64bit\Search-EES-Library.ps1" `
  -Query 'compact heat exchanger pressure drop' `
  -Limit 3 `
  -Detail Compact
```

The compact command returns ranked candidates with only the routine identifier and type, short description, primary syntax, required load directive, installed-metadata match, and deprecation or replacement information. Use the selected search record directly.

When the routine ID is already known without searching, retrieve it compactly:

```powershell
& "$env:LOCALAPPDATA\EES-Codex-Launcher-64bit\Get-EES-Routine.ps1" `
  -RoutineID 'Blackbody' `
  -Detail Compact
```

Do not make this second compact call after a compact search. Add `-Detail Full` for one selected routine when alternate signatures, parameter descriptions, keywords, categories, paths, hashes, or help references are needed. Numeric `unit_type_code` values are not self-describing, so confirm units from the routine documentation or a compile test. Both modes use the packaged `EES_Tool_Metadata.json` as their sole catalog source; selected-installation metadata is compared only for `installed_metadata_match` and is never merged.

The launcher passes `/AI`, so a returned `required_load_directive` is optional for this controlled run. To make the program portable to an ordinary EES session, copy that exact directive to its beginning. For example, component models normally use:

```text
$Load Component Library
```

## Retest the installation

Double-click **Test Installation.cmd** in the extracted package, or run:

```powershell
& "$env:LOCALAPPDATA\EES-Codex-Launcher-64bit\Test-Installation.ps1"
```
