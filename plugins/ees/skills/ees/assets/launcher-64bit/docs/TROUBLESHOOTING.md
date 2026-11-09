# Troubleshooting — 64-bit edition

## 64-bit EES was not found

The installer checks `C:\EES64\ees64.exe`. For another location:

```powershell
.\Install-EES-Codex-Launcher.ps1 -EesPath 'D:\EES64\ees64.exe'
```

This edition accepts only `ees64.exe` and rejects 32-bit `ees.exe`.

## EES reports an error or times out

The launcher uses `/SOLVE /AI`. With EES 12.358 or newer, after acquiring its run lock and confirming no interactive `ees64.exe` is open, it deletes the previous `EES_Msg.txt` beside the EES executable. When EES exits, the launcher snapshots any fresh file into the retained `.ees-runs` directory and returns the text as `ees_message`. Older EES versions remain usable and report `ees_message_supported=false`. If the export is missing, the run fails even when EES reports process exit code 0. On timeout the launcher stops only the process it created; supported versions prefer the fresh message snapshot, while older versions use accessible window text when available.

On EES 12.358 or newer, do not diagnose a run from an independently read fixed `C:\EES64\EES_Msg.txt`; another run can replace it. Use the `ees_message_snapshot` path in the launcher's JSON. If the launcher cannot remove the previous fixed file before starting EES, it stops rather than risk reporting stale diagnostics.

## The launcher says 64-bit EES is already running

Close every interactive 64-bit EES window. The launcher serializes automated solves and deliberately avoids sharing an EES process with an interactive session.

## An older launcher left EES profile recovery files

Version 0.7.0-beta uses `/AI` and does not create profile backup or recovery files. If files from version 0.3.0-beta remain, do not guess which copy is current. Preserve these files and contact support before starting EES or renaming anything:

```text
C:\EES64\EES.PRF64
C:\EES64\EES.PRF64.ees-codex-backup
C:\EES64\EES.PRF64.ees-codex-backup.json
```

## Test again

Run `%LOCALAPPDATA%\EES-Codex-Launcher-64bit\Test-Installation.ps1`. Its JSON output identifies the selected executable, workspace, result, catalog status, `/AI` library test, and persistent-autoload check.
