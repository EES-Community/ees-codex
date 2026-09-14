# EES for Codex

An EES skill packaged as a Codex plugin and repository marketplace. It helps Codex find EES library routines, write equation models, solve them with local EES Professional, and inspect exported results.

The plugin includes the original 32-bit and 64-bit EES Codex Launcher 0.4.0-beta distributions. EES, EES licenses, and Codex are required separately.

## Requirements

- Windows 10 or 11 and Windows PowerShell 5.1 or PowerShell 7.
- EES Professional supporting `/solve` and `/AI`.
- A Codex desktop app with the Add plugin marketplace dialog.

Choose the launcher matching **EES bitness**, not Windows bitness. Python and Node are not needed by the launcher. The exact minimum EES version remains to be established through Windows testing.

## Add the marketplace

In the desktop app's **Add plugin marketplace** dialog:

| Field | Value |
| --- | --- |
| Source | `https://github.com/EES-Community/ees-codex` (or an absolute local repository folder for local testing). |
| Git ref | `main` for the GitHub repository. Leave unset for a local folder. |
| Sparse paths | Leave empty so the marketplace and plugin assets are all included. |

Select **Add marketplace**, find **Engineering Equation Solver**, and install it. Start a new conversation to load the skill. The marketplace scaffold currently uses the identifier `personal`; the plugin identifier is `ees`.

For local development, use this repository's folder as the Source, not its `plugins/ees` subfolder. The marketplace entry lives at `.agents/plugins/marketplace.json` and points to `./plugins/ees`.

## Set up EES and solve a model

Ask Codex:

> Use the EES skill to set up the launcher for my installed EES Professional and run the installation test.

The skill locates EES, selects the matching bundled installer, and sets up separate launcher and model folders. If both EES editions exist, specify your preferred edition. The installation test runs real EES calculations. Save and close interactive EES before running it.

Then try:

> Use EES to calculate the heat duty for water flowing at 1 kg/s from 20 C to 60 C at 200 kPa. Save the model and exported results and explain the units and assumptions.

Models and results stay in the selected workspace. The plugin install alone does not install or test the Windows launcher. Updates to the plugin do not automatically update an already installed launcher.

## Contents

- `.agents/plugins/marketplace.json`: repository marketplace entry.
- `plugins/ees/.codex-plugin/plugin.json`: plugin manifest.
- `plugins/ees/skills/ees/SKILL.md`: reusable EES workflow.
- `plugins/ees/skills/ees/references/setup.md`: setup and compatibility guidance.
- `plugins/ees/skills/ees/assets/launcher-{32,64}bit/`: unchanged upstream distributions.
- `UPSTREAM.json`: source archive names and SHA-256 checksums.

The original launchers use an exported text-file workflow and include Database22 calling metadata for 813 routines. They provide directive filters, fresh per-run output staging, process serialization, and timeout diagnostics. These checks are not an OS security sandbox or proof of engineering correctness.

## Validation status

Package structure and archive integrity can be checked on Linux. End-to-end installation, marketplace UI behavior, and actual solves must also be verified in the target Windows desktop environment before a customer release. Bundled upstream tests have not been executed as part of this initial packaging.

## Notices

See [NOTICE.md](NOTICE.md). No new open-source license is assigned by this packaging. Upstream notices state that the derived catalog may be redistributed with its owner's permission; retain those notices. Publisher-selected licensing for the new packaging remains to be decided before public release.
