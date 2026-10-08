---
name: ees
description: Create, run, debug, or inspect EES equation models; search installed EES routines; or configure the Windows EES launcher. Use only when the task requires EES Professional, not for generic thermal-fluid analysis.
license: Limited source-available terms in LICENSE.md
---

# Engineering Equation Solver

Use local EES Professional through the installed EES Codex Launcher. EES performs the calculations; this skill selects the appropriate safe workflow.

## Route by task

1. For installation or a user-requested launcher update, read [setup](references/setup.md). Do not load setup for an already configured modeling task.
2. Determine whether the task needs an installed helper. Write-only work and review of existing results may proceed without launcher configuration or setup; do not claim execution. On non-Windows systems, do not silently install another solver.
3. Before catalog lookup, execution, or any other operation that invokes an installed helper, first read `launcher-config.json` in the selected project. If it is absent, check only the documented installed configurations under `%LOCALAPPDATA%\EES-Codex-Launcher-32bit` and `%LOCALAPPDATA%\EES-Codex-Launcher-64bit`. If no usable configuration remains, read setup; reading it does not authorize installation. Preserve the selected workspace and EES edition; if both editions are configured and the user has not chosen, ask which to use. Load the selected configuration as `$config` for later commands.
4. Follow applicable EES workspace instructions already in context. If they do not fully cover the requested operation, or the selected workspace has no EES-specific instructions, read [model workflow](references/model-workflow.md) for the missing guidance. Do not load that fallback when the workspace instructions already cover the task.
5. Read [failure handling](references/failures.md) only after a launcher error, timeout, or unexpected launcher or export behavior. Do not load failure guidance preemptively.

## Invariants

- Run EES only through installed helpers identified by configuration. Bundled launcher assets are installation sources.
- Keep models and results inside the selected workspace. Use EES equation `.txt` files; never disguise a binary `.ees` file.
- Use the catalog helpers rather than loading the complete catalog JSON.
- Do not manually edit EES, an installed launcher, preferences, or libraries, and never weaken or bypass launcher checks. For a user-requested install or update, use the supplied installer workflow in setup.
- From the first attempt, run helpers that start EES outside the filesystem sandbox so they have normal Windows filesystem access. Catalog and metadata helpers may remain sandboxed.
- If matching interactive EES is open, ask the user to save and close it; never terminate it.
- Preserve the chosen model, any supplied or fresh result, and the engineering rationale. Report separately whether the model was written, executed, and checked. Do not treat successful execution as proof of engineering correctness, design fitness, or safety.
