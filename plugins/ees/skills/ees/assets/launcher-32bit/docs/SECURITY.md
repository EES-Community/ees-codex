# Security model

EES is a Windows desktop program and runs with the signed-in user's permissions. It is not contained by a Codex project filesystem sandbox.

The launcher therefore enforces a narrow contract:

- Input, staging, and output paths must remain within one configured workspace.
- Input must be an EES `.txt` equations file.
- Exactly one `$Export` or `$ExportText` line must use `{{OUTPUT_FILE}}` for the primary audit result.
- Optional workspace inputs and additional outputs require a version 1 artifact manifest. The launcher validates every binding and extension, stages inputs and outputs in the private run directory, requires every expected output to be nonempty, and only then moves outputs to their declared workspace paths. Literal or undeclared file paths remain blocked.
- Existing result files are not replaced unless `-Force` is explicit.
- Structured result extraction is read-only, accepts only `.txt` files inside the configured workspace, and fails explicitly on malformed, unsupported, or duplicate entries.
- Validated `$Import`, `$ImportText`, `$OpenLookup`, `$Export`, `$ExportText`, `$ExportPlot`, `$SaveLookup`, `$SaveTable`, and `$SaveVarInfo` artifacts are supported. `$Reference` is allowed because it changes a thermodynamic reference state rather than accessing a file.
- EES directives that run macros or Python, include arbitrary files, change the default directory, generate LaTeX/PDF files, or require interactive input are blocked. `$Load` is limited to four exact symbolic names for installed EES libraries: Component Library, Mechanical, NASA, and Incompressible; paths and arbitrary library names remain blocked.
- EES is launched with `/NOSPLASH /SOLVE /AI` as a normal shell process and is killed if it exceeds the selected timeout.
- For 32-bit EES, the launcher serializes runs with a named mutex, refuses to proceed while `ees.exe` is already open, and passes `/AI` so all five application libraries are available for the run. On EES 12.358 or newer, while holding that lock, it deletes only the fixed `EES_Msg.txt` beside the selected executable and snapshots any fresh replacement into the workspace before releasing the lock. Older versions skip that file operation. The launcher does not edit, replace, back up, or restore `EES.PRF`.
- The production launcher is installed outside the writable model workspace.
- At most once per 24 hours, the launcher requests the fixed HTTPS manifest at `raw.githubusercontent.com/EES-Community/ees-codex/main/update/latest.json`. It accepts only semantic versions and an HTTPS update link within `github.com/EES-Community/ees-codex`, writes a small cache under `%LOCALAPPDATA%\EES-Codex-Launcher`, and never downloads or installs an update. Set `EES_CODEX_DISABLE_UPDATE_CHECK=1` to suppress the request for the current process and its children.

Keep Codex's project sandbox enabled. Grant targeted approval only to the reviewed installed launcher with the configured workspace and EES executable. Do not grant blanket full-system access merely to avoid launcher approvals.

The installer uses `ExecutionPolicy Bypass` only for scripts inside the extracted package or the installed launcher directory. This avoids common Windows downloaded-script blocking; it is not a signature or proof of trust. Distributors should publish the ZIP's SHA-256 digest over an authenticated channel and should code-sign scripts and the package for a production release.

The package does not contain or modify the EES executable, proprietary EES libraries, or persistent library-autoload preferences. On EES 12.358 or newer, its only managed file in the selected EES directory is the transient `EES_Msg.txt` diagnostic described above. Library discovery uses the packaged `EES_Tool_Metadata.json` as its sole catalog and compares selected-installation metadata only for an availability flag. EES itself may update ordinary session preferences when it starts or exits; the launcher does not patch the preference file.
