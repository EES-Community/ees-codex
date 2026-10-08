# EES launcher failure handling

Read this reference only after an installed helper returns an error, times out, or shows unexpected launcher or export behavior. Do not repeatedly run an unchanged failing model or increase the timeout without evidence that runtime, rather than a blocked dialog or model error, is the problem.

## Triage

1. Read the helper's JSON status and note its message and retained `run_directory`. Preserve the staged program and diagnostics while investigating.
2. If matching interactive EES is already open, ask the user to save and close it. Never terminate the user's interactive process.
3. For a timeout, inspect the retained `.ees-runs` program and captured EES window text before changing the model. A timeout commonly indicates a modal compile or solve dialog.
4. Treat an access error involving an EES shared location outside the workspace as an execution-sandbox problem, not a model compile failure. Rerun the unchanged installed helper with normal Windows filesystem access when authorized.
5. If the expected export is missing or empty, verify the staged program, the single export directive and placeholder, and the reported EES message. Do not report the model as executed successfully.
6. If the output already exists, choose a new result filename unless replacement is intentional; use `-Force` only for that intentional replacement.
7. If a directive is blocked or the task requires external code, imports, macros, or arbitrary file writes, explain that the launcher does not support the action. Do not bypass or relax its checks.

Correct only the indicated issue, rerun when the evidence supports it, and then inspect a fresh result. Report separately whether the model was written, executed by EES, and checked.

For installation-test failures, use the selected launcher's `docs\TROUBLESHOOTING.md` after reading [setup](setup.md). Preserve profile and recovery files; do not guess which copy is current or alter EES preferences.
