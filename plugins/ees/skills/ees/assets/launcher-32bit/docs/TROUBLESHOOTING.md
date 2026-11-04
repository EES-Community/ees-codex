# Troubleshooting — 32-bit edition

## 32-bit EES was not found

The installer checks `C:\EES32\ees.exe`. For another location:

```powershell
.\Install-EES-Codex-Launcher.ps1 -EesPath 'D:\EES32\ees.exe'
```

This edition accepts only an executable named `ees.exe`. It intentionally rejects `ees64.exe` even when 64-bit EES is installed.

## The installer or script is blocked

Extract the whole ZIP first. Right-click the downloaded ZIP, select **Properties**, select **Unblock** if available, and extract it again. `Install.cmd` invokes Windows PowerShell with a process-scoped execution-policy bypass; it does not change the machine's execution policy.

## EES reports an error or the launcher times out

The launcher uses `/SOLVE /AI`; `/CHECK` is not needed for the ordinary solve/export workflow. With EES 12.358 or newer, after acquiring its run lock and confirming no interactive `ees.exe` is open, it deletes the previous `EES_Msg.txt` beside the EES executable. When EES exits, the launcher snapshots any fresh file into the retained `.ees-runs` directory and returns the text as `ees_message`. Older EES versions remain usable and report `ees_message_supported=false`. If the export is missing, the run fails even when EES reports process exit code 0. On timeout the launcher stops only the process it created; supported versions prefer the fresh message snapshot, while older versions use accessible window text when available.

On EES 12.358 or newer, do not diagnose a run from an independently read fixed `C:\EES32\EES_Msg.txt`; another run can replace it. Use the `ees_message_snapshot` path in the launcher's JSON. If the launcher cannot remove the previous fixed file before starting EES, it stops rather than risk reporting stale diagnostics.

## The output already exists

Use a new output filename for an auditable design history. Use `-Force` only when intentionally replacing a result.

## The library search returns no useful routine

Confirm that `ees_path`, `installed_metadata_path`, and `userlib_path` in `launcher-config.json` point to the 32-bit installation and its `Userlib` folder. `metadata_path` and `catalog_path` should point to the packaged canonical `EES_Tool_Metadata.json` inside the launcher directory. Write the governing equations directly when no verified routine is available.

## A Component Library routine reports a missing dependency

Confirm that the matching 32-bit Component Support and Component Library files are installed and enabled, then compile-test the routine again. `Compressor2_CL` with `$Load Component Library` was verified with the development machine's 32-bit EES installation.

## Codex cannot launch EES

Use the native Windows/PowerShell project environment, not a WSL-only project. Keep **Ask for approval** enabled and approve the specific command that invokes the installed launcher. Ensure the project folder is the configured EES workspace.

## The launcher says 32-bit EES is already running

Close every interactive 32-bit EES window and try again. The launcher serializes automated solves and deliberately avoids sharing an EES process with an interactive session.

## An older launcher left EES profile recovery files

Version 0.5.1-beta uses `/AI` and does not create profile backup or recovery files. If files from version 0.3.0-beta remain, do not guess which copy is current:

Preserve these files and contact support before starting EES or renaming anything:

```text
C:\EES32\EES.PRF
C:\EES32\EES.PRF.ees-codex-backup
C:\EES32\EES.PRF.ees-codex-backup.json
```

## Test again

Run `%LOCALAPPDATA%\EES-Codex-Launcher-32bit\Test-Installation.ps1`. Its JSON output identifies the selected executable, workspace, result path, catalog status, `/AI` library test, or failure message.
