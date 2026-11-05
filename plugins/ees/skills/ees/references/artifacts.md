# Validated EES file artifacts

Read this reference only when an EES model must import a workspace data file or produce an additional EES file such as a native plot, lookup table, parametric table, or variable-information file.

## Capability gate

Use this workflow only when `Resolve-EES-LauncherCapabilities.ps1` reports `validated_artifact_manifest_capable=true` and the requested directive appears in the selected configuration's `artifact_input_directives` or `artifact_output_directives`. If not, keep the ordinary single text export, mention the available launcher update once, and do not weaken or bypass the installed launcher.

The current launcher is Solve-only. Every run still requires `-OutputPath` and exactly one `{{OUTPUT_FILE}}` placeholder on `$Export` or `$ExportText`. An artifact manifest adds validated files; it does not replace the principal audit result.

## Manifest contract

Create a version 1 JSON file inside the selected workspace. Each binding name must use uppercase letters, digits, and underscores, start with a letter, be unique, and appear exactly once in the EES source. Use paths relative to the workspace when practical.

```json
{
  "version": 1,
  "inputs": [],
  "outputs": [
    {
      "name": "PLOT_FILE",
      "path": "results/water-property-plot.jpg"
    }
  ]
}
```

The launcher resolves every path beneath `WorkspaceRoot`, requires every input to exist, refuses to replace an output unless `-Force` is explicit, and checks the extension against the directive. It copies inputs to the private run directory. It directs EES outputs to that run directory, verifies every expected file is present and nonempty, and only then moves them to the declared workspace destinations.

Current validated input directives are `$Import`, `$ImportText`, and `$OpenLookup`. Current validated output directives are `$Export`, `$ExportText`, `$ExportPlot`, `$SaveLookup`, `$SaveTable`, and `$SaveVarInfo`. The placeholder must occupy that directive's filename argument; using it as a table name while supplying a literal filename is rejected. Interactive `?` selection and `$OpenLookup /FORMAT`, which names a second file, are not supported. File directives without a declared placeholder remain blocked.

## Native plot example

Use a declared placeholder as the EES filename:

```ees
$UnitSystem SI C kPa kJ Mass
T=25 [C]
P=101.325 [kPa]
h=Enthalpy(Water,T=T,P=P)

$PropertyPlot Water TS DEF DEF DoQLines
$ExportPlot '{{PLOT_FILE}}' 1
$Export /H /V /U /N '{{OUTPUT_FILE}}' T, P, h
```

Then run:

```powershell
& (Join-Path $config.install_directory 'Run-EES.ps1') `
  -WorkspaceRoot $config.workspace_root `
  -ProgramPath (Join-Path $config.workspace_root 'models\water-property-plot.txt') `
  -OutputPath (Join-Path $config.workspace_root 'results\water-property-plot.txt') `
  -ArtifactManifestPath (Join-Path $config.workspace_root 'models\water-property-plot-artifacts.json') `
  -EesPath $config.ees_path `
  -TimeoutSeconds 120
```

Read the structured status before opening any files. Confirm `status=success`, inspect any EES message, and verify the expected entries in `input_artifacts` and `output_artifacts`. For an image, inspect the actual rendered file rather than relying only on its nonzero length.

## Safety boundary

`$Reference` is allowed when `thermodynamic_reference_directive_capable=true`; it changes a fluid's thermodynamic reference state and does not name a filesystem path. `$Python`, `$Include`, macro-running directives, `$DefaultDirectory`, `$LaTeXPDF`, and interactive `$Input` remain blocked. The exact `$Load` whitelist remains `$Load Component Library`, `$Load Mechanical`, `$Load NASA`, and `$Load Incompressible`.
