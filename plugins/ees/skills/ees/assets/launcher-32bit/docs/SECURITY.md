# Security model

EES is a Windows desktop program and runs with the signed-in user's permissions. It is not contained by a Codex project filesystem sandbox.

The launcher therefore enforces a narrow contract:

- Input, staging, and output paths must remain within one configured workspace.
- Input must be an EES `.txt` equations file.
- Exactly one `$Export` or `$ExportText` line must use `{{OUTPUT_FILE}}`.
- Existing result files are not replaced unless `-Force` is explicit.
- EES directives that run macros or Python, load external files, import data, or create other files are blocked. `$Load` is limited to four exact symbolic names for installed EES libraries: Component Library, Mechanical, NASA, and Incompressible; paths and arbitrary library names remain blocked.
- EES is launched hidden and killed if it exceeds the selected timeout.
- For 32-bit EES, the launcher serializes runs with a named mutex, refuses to proceed while `ees.exe` is already open, and passes `/AI` so all five application libraries are available for the run. It does not edit, replace, back up, or restore `EES.PRF`.
- The production launcher is installed outside the writable model workspace.

Keep Codex's project sandbox enabled. Grant targeted approval only to the reviewed installed launcher with the configured workspace and EES executable. Do not grant blanket full-system access merely to avoid launcher approvals.

The installer uses `ExecutionPolicy Bypass` only for scripts inside the extracted package or the installed launcher directory. This avoids common Windows downloaded-script blocking; it is not a signature or proof of trust. Distributors should publish the ZIP's SHA-256 digest over an authenticated channel and should code-sign scripts and the package for a production release.

The package does not contain or modify the EES executable, proprietary EES libraries, or persistent library-autoload preferences. Library discovery reads metadata from the user's selected EES installation. EES itself may update ordinary session preferences when it starts or exits; the launcher does not patch the preference file.
