# EES for Codex

An EES skill packaged as a Codex plugin and repository marketplace. EES Professional remains the solver. Coordinated release 0.5.0-beta gives Codex a repeatable workflow for finding EES library routines, writing equation models, invoking a controlled local launcher, and checking fresh exported results.

The plugin includes matching 32-bit and 64-bit EES Codex Launcher 0.5.0-beta distributions. EES, an EES license, and Codex are required separately. The beta labels apply to this integration package, not to EES Professional.

## What the skill adds

- Chooses the launcher that matches the installed EES edition and uses the recorded workspace rather than guessing paths.
- Searches the current packaged `EES_Tool_Metadata.json` before recreating a routine, using compact output first and full detail only for a selected candidate.
- Writes auditable EES text models, runs them through the launcher, and requires a fresh exported result.
- Requests compact structured engineering outputs and residuals after ordinary solves, while retaining full-export and raw-file fallbacks.
- Checks units, balances, feasibility, assumptions, and launcher diagnostics instead of treating a started process as a verified calculation.

Codex can open `ees.exe` without this skill, and the launcher can also be used manually from PowerShell. A bare request to run EES does not by itself supply the model/output contract, library-search workflow, directive checks, stale-result protection, or result-review steps. The skill packages those decisions so they are applied consistently.

## Requirements

- Windows 10 or 11 with the built-in Windows PowerShell 5.1.
- EES Professional. The installation test verifies command-line solving and application-library access.
- Codex in the ChatGPT desktop app with access to the Plugins Directory.

PowerShell 7 is supported; EES-starting commands hand off automatically to Windows PowerShell 5.1. PowerShell 6 is not a tested target. Python and Node.js are not required.

Choose by **EES bitness**, not Windows bitness: `ees.exe` selects the 32-bit launcher and `ees64.exe` selects the 64-bit launcher. If both editions are installed, specify which one to use. The exact minimum EES version remains to be established through Windows testing.

## Add the marketplace

Open **Plugins** in Codex, normally from the left sidebar. Placement can vary by app version. Select **Add**, then **Add Marketplace**, then add a repository with these values:

| Field | Value |
| --- | --- |
| Source | `https://github.com/EES-Community/ees-codex` |
| Git ref | `main` |
| Sparse paths | Leave empty so the marketplace and plugin assets are all included. |

Open **Engineering Equation Solver**. Depending on the app version and current state, its action may be labeled **Try now**, **Install**, or shown as a plus button. If it is already installed, do not uninstall it merely because the label differs from this README. Start a new conversation after the first installation so the skill is loaded. The marketplace identifier is `ees-codex`; the plugin identifier is `ees`.

Most users should use the GitHub source above. A local checkout is only for maintainers or testing; when needed, select the repository root containing `.agents/plugins/marketplace.json`, not `plugins/ees`.

### Older `personal` marketplace conflict

Early prerelease copies used the generic marketplace name `personal`. If Codex says that marketplace is registered from another source, first inspect what is registered:

```powershell
codex plugin marketplace list --json
codex plugin list --json
```

Do not delete the plugin cache or remove an unrelated personal marketplace. If `ees@personal` is an obsolete EES installation, remove that plugin. Remove the old `personal` marketplace only when the reported root is the obsolete EES source and no other plugin depends on it:

```powershell
codex plugin remove ees@personal --json
codex plugin marketplace remove personal --json
```

Fully quit and restart the ChatGPT desktop app, then add the current `ees-codex` marketplace. A CLI alternative is `codex plugin marketplace add EES-Community/ees-codex --ref main`.

### Manual skill-copy fallback

Use this only when the normal plugin marketplace is unavailable. From a local checkout of this repository, copy the complete `plugins\ees\skills\ees` directory to the current per-user skill location, `%USERPROFILE%\.agents\skills\ees`. Do not combine it with an existing directory of the same name; inspect and preserve an existing copy before replacing it.

```powershell
$repository = 'C:\path\to\ees-codex'
$skillSource = Join-Path $repository 'plugins\ees\skills\ees'
$skillParent = Join-Path $env:USERPROFILE '.agents\skills'
$skillDestination = Join-Path $skillParent 'ees'

if (-not (Test-Path -LiteralPath (Join-Path $skillSource 'SKILL.md'))) {
    throw "EES skill source not found: $skillSource"
}
if (Test-Path -LiteralPath $skillDestination) {
    throw "An EES skill already exists at $skillDestination; preserve or remove it before retrying."
}

New-Item -ItemType Directory -Path $skillParent -Force | Out-Null
Copy-Item -LiteralPath $skillSource -Destination $skillDestination -Recurse
```

Start a new Codex task after copying; if the skill does not appear, restart Codex. This fallback installs the skill bundle only. Launcher installation and its live test remain the separate next step described below. Replace the complete manual-copy directory for a fallback update; do not overlay files. Before switching to the marketplace, preserve and remove the manual copy so Codex does not discover duplicate or stale skills with the same `ees` name. For normal distribution and updates, prefer the plugin marketplace.

## Set up EES and solve a model

Close the matching interactive EES application, start a new Codex task, and provide the full executable path. For example:

> Use the $ees skill to install the launcher for my EES Professional at C:\EES32\ees.exe. Use the recommended launcher and workspace locations, run the complete installation test with normal Windows filesystem access, and report the exact workspace path.

There is no separate launcher-picker dialog in the normal agent-driven flow. The executable name selects the matching bundled package; if both editions are present and no path is supplied, Codex asks which one to use. An approval prompt appears only when required by the current Codex permission policy as a command starts EES, so prior approvals or managed policy can change what the user sees.

The installation test runs real EES calculations. Success is normally reported as text containing the installed launcher path, exact workspace path, the 200 kW smoke-test result, catalog lookup, five application-library checks, and unchanged persistent autoload preferences. The exact formatting can vary.

Then try:

> Use the $ees skill to calculate the rate of heat transfer required to increase the temperature of water flowing at 1 kg/s and 200 kPa from 20 C to 60 C. Save the model and exported result, check units and the energy balance, and explain the assumptions.

Models and results stay in the selected workspace. The plugin install alone does not install or test the Windows launcher. Plugin and bundled launcher releases now use the same version and are validated together, but a plugin update does not silently overwrite an already installed launcher. On an explicit update request, the skill reuses the recorded installation paths and runs the matching bundled installer and tests.

## Contents

- `.agents/plugins/marketplace.json`: repository marketplace entry.
- `plugins/ees/.codex-plugin/plugin.json`: plugin manifest.
- `plugins/ees/skills/ees/SKILL.md`: reusable EES workflow.
- `plugins/ees/skills/ees/LICENSE.md` and `NOTICE.md`: license and third-party notices carried by installed plugin and manual skill copies.
- `plugins/ees/skills/ees/references/setup.md`: setup and compatibility guidance.
- `plugins/ees/skills/ees/references/model-workflow.md`: detailed fallback modeling and launcher workflow.
- `plugins/ees/skills/ees/references/failures.md`: conditional launcher failure triage.
- `plugins/ees/skills/ees/assets/launcher-{32,64}bit/`: launcher distributions derived from the documented upstream packages; local modifications are recorded in `UPSTREAM.json`.
- [`output/pdf/EES-Codex-Installation-Guide.pdf`](output/pdf/EES-Codex-Installation-Guide.pdf): distributable Windows installation and first-run guide.
- `UPSTREAM.json`: source archive names and SHA-256 checksums.

The launchers use an exported text-file workflow and include the current owner-maintained `EES_Tool_Metadata.json` snapshot for 813 routines. Search and detail helpers support compact and full modes, and they never merge an older installation catalog into that source. `Get-EES-Result.ps1` provides deterministic compact exact-name and wildcard selection while preserving raw numeric text and units; full mode includes every exported value plus file metadata and diagnostics. The launchers also provide explicit capability declarations, directive filters, fresh per-run output staging, process serialization, and timeout diagnostics. Version 0.5.0-beta automatically hands PowerShell 7 calls to Windows PowerShell 5.1 and starts EES as a normal shell process because EES 12.3.3.2 may exit without solving under .NET Core or when started as a hidden, non-shell process. These checks are not an OS security sandbox or proof of engineering correctness.

Plugin and launcher 0.5.0-beta are one coordinated release. Generated configuration records the release, launcher API level, and supported catalog/result modes so the skill can prefer capabilities over version-string comparisons and fall back safely with older launchers. `UPSTREAM.json` records the exact upstream provenance, canonical metadata hash, and local packaging changes.

## Validation status

Version 0.5.0-beta retains Windows validation against 32-bit EES 12.3.4.0 and 64-bit EES 12.3.2.0. The bundled checks verify coordinated version/capability configuration, compact and full result extraction, the canonical metadata hash and row counts, compact search and routine-detail shapes, full Compressor2_CL signatures and parameters, real EES solving and export, `/AI` access to Component, Mechanical Design, NASA, Incompressible, and Heat Transfer routines, and unchanged persistent autoload preferences. Public directory publication still requires uploading the release ZIP, resolving portal findings, review, and an explicit publish action.

## Notices

See [LICENSE.md](LICENSE.md) and [NOTICE.md](NOTICE.md). Copies are also carried inside the distributable skill so installed plugin and manual skill copies retain their terms. For repository-authored material, the limited, non-open-source license permits the copying, unmodified redistribution, and use needed to install, evaluate, and operate this integration, and it permits redistribution of the unmodified installation guide. Upstream notices state that the derived catalog may be redistributed with its owner's permission; retain those notices. These terms apply only to material for which EES-Community contributors hold copyright and do not alter or sublicense catalog metadata, EES, OpenAI software, or other third-party material.
