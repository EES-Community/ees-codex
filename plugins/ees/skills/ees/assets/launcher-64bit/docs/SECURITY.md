# Security model — 64-bit edition

EES runs with the signed-in user's Windows permissions. The launcher therefore confines model and result paths to the configured workspace, permits one controlled export, blocks external-code and arbitrary-file directives, launches EES hidden, and enforces a timeout.

For every 64-bit solve, the launcher:

- serializes access with a named mutex and refuses to run while `ees64.exe` is already open;
- passes `/AI` so all five application libraries are available for the run; and
- does not edit, replace, back up, or restore `EES.PRF64`.

The package does not contain EES or proprietary EES libraries. EES itself may update ordinary session preferences when it starts or exits; the launcher does not patch the preference file. Distributors should publish the ZIP checksum over an authenticated channel and code-sign production releases.
