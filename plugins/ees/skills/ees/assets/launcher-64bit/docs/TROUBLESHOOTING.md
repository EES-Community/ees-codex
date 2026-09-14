# Troubleshooting — 64-bit edition

## 64-bit EES was not found

The installer checks `C:\EES64\ees64.exe`. For another location:

```powershell
.\Install-EES-Codex-Launcher.ps1 -EesPath 'D:\EES64\ees64.exe'
```

This edition accepts only `ees64.exe` and rejects 32-bit `ees.exe`.

## EES opens an error dialog or times out

EES may wait on a modal compile or solve error. The launcher stops only the process it created, reports accessible dialog text, and preserves the staged program for diagnosis.

## The launcher says 64-bit EES is already running

Close every interactive 64-bit EES window. The launcher serializes automated solves and deliberately avoids sharing an EES process with an interactive session.

## An older launcher left EES profile recovery files

Version 0.4.0-beta and later use `/AI` and do not create profile backup or recovery files. If files from version 0.3.0-beta remain, do not guess which copy is current. Preserve these files and contact support before starting EES or renaming anything:

```text
C:\EES64\EES.PRF64
C:\EES64\EES.PRF64.ees-codex-backup
C:\EES64\EES.PRF64.ees-codex-backup.json
```

## Test again

Run `%LOCALAPPDATA%\EES-Codex-Launcher-64bit\Test-Installation.ps1`. Its JSON output identifies the selected executable, workspace, result, catalog status, `/AI` library test, and persistent-autoload check.
