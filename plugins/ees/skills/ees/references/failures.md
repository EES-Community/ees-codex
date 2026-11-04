# EES launcher failure handling

Read this reference only after an installed helper returns an error, times out, or shows unexpected launcher or export behavior. Do not repeatedly run an unchanged failing model or increase the timeout without evidence that runtime, rather than a blocked dialog or model error, is the problem.

## Triage

1. Read the helper's JSON status and note its `message`, `ees_message_supported`, `ees_message_present`, `ees_message`, `ees_message_snapshot`, and retained `run_directory`. Preserve the staged program and diagnostic snapshot while investigating. With EES 12.358 or newer, the launcher deletes the fixed EES-installation `EES_Msg.txt` only after acquiring its run lock, then snapshots the fresh file before releasing the lock; do not substitute an independently read fixed file for that per-run snapshot. Older EES versions report capture as unsupported and remain on the export/window-text fallback.
2. If matching interactive EES is already open, ask the user to save and close it. Never terminate the user's interactive process.
3. For a timeout, inspect the retained `.ees-runs` program and `EES_Msg.txt` snapshot before changing the model. Use captured EES window text only when no fresh message was available.
4. If EES reports that the number of input or output variables does not match a procedure declaration, compare the `CALL` statement with the selected signature. Preserve the colon and every comma-delimited output position; leave unused optional outputs blank. For example, use `:DELTAP,,` rather than shortening a three-output procedure to `:DELTAP`.
5. Treat an access error involving an EES shared location outside the workspace as an execution-sandbox problem, not a model compile failure. Rerun the unchanged installed helper with normal Windows filesystem access when authorized.
6. If the expected export is missing or empty, verify the staged program, the single export directive and placeholder, and the reported fresh EES message. EES may return process exit code 0 after a compile or solve failure, so the missing export and structured diagnostic—not the process code alone—determine failure.
7. If the output already exists, choose a new result filename unless replacement is intentional; use `-Force` only for that intentional replacement.
8. If a directive is blocked or the task requires external code, imports, macros, or arbitrary file writes, explain that the launcher does not support the action. Do not bypass or relax its checks.

Correct only the indicated issue, rerun when the evidence supports it, and then inspect a fresh result. Report separately whether the model was written, executed by EES, and checked.

For installation-test failures, use the selected launcher's `docs\TROUBLESHOOTING.md` after reading [setup](setup.md). Preserve profile and recovery files; do not guess which copy is current or alter EES preferences.
