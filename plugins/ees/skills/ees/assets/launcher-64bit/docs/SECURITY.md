# Security model — 64-bit edition

EES runs with the signed-in user's Windows permissions. The launcher therefore confines model and result paths to the configured workspace, permits one controlled export, blocks external-code and arbitrary-file directives, launches EES with `/NOSPLASH /SOLVE /AI` as a normal shell process, and enforces a timeout. Structured result extraction is read-only, accepts only `.txt` files inside the configured workspace, and fails explicitly on malformed, unsupported, or duplicate entries.

For every 64-bit solve, the launcher:

- serializes access with a named mutex and refuses to run while `ees64.exe` is already open;
- passes `/AI` so all five application libraries are available for the run;
- on EES 12.358 or newer, while holding the lock, deletes only the fixed `EES_Msg.txt` beside the selected executable and snapshots any fresh replacement into the workspace before releasing the lock; older versions skip that file operation; and
- does not edit, replace, back up, or restore `EES.PRF64`.

The package does not contain EES or proprietary EES libraries. On EES 12.358 or newer, its only managed file in the selected EES directory is the transient `EES_Msg.txt` diagnostic described above. Library discovery uses the packaged `EES_Tool_Metadata.json` as its sole catalog and compares selected-installation metadata only for an availability flag. EES itself may update ordinary session preferences when it starts or exits; the launcher does not patch the preference file. Distributors should publish the ZIP checksum over an authenticated channel and code-sign production releases.
