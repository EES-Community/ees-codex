# EES Codex Launcher — 64-bit edition

This Windows package lets Codex—or a person using PowerShell—write an EES equations file, solve it with **64-bit EES Professional**, and read a fresh text result. It requires no Python installation.

This edition is deliberately locked to 64-bit EES. Its installer and installed tools reject `ees.exe`. The package does **not** include EES, an EES license, Codex, or OpenAI software.

## What you need

- Windows 10 or 11.
- A working 64-bit EES Professional installation that supports the `/AI` command-line option. The `/solve` feature is also required.
- Normally, EES at `C:\EES64\ees64.exe`. A custom location containing `ees64.exe` can be supplied to the installer.
- Windows PowerShell 5.1 or PowerShell 7.
- Codex is optional. See [Install and use Codex](docs/CODEX-SETUP.md) if you do not have it.

## Install the launcher

1. Download the ZIP and save it locally.
2. Right-click the ZIP, select **Properties**, and select **Unblock** if Windows shows that option. Select **OK**.
3. Extract the complete ZIP. Do not run the installer while browsing inside the ZIP.
4. Open the extracted folder and double-click **Install.cmd**.
5. Choose the launcher and models-and-results workspace directories. Press **Enter** to accept each recommended path. The recommended workspace is `%USERPROFILE%\EES-Codex-Workspace-64bit`, directly inside your Windows user folder—not inside Documents, Music, or OneDrive.
6. The installer selects `C:\EES64\ees64.exe`, runs real EES calculations, checks the Database22 catalog, and uses `/AI` to test routines from all five application libraries without `$Load`. It also verifies that the persistent library-autoload setting in `EES.PRF64` was not changed.

For a custom EES location, run:

```powershell
.\Install-EES-Codex-Launcher.ps1 -EesPath 'D:\your-folder\ees64.exe'
```

For an unattended installation, supply both locations:

```powershell
.\Install-EES-Codex-Launcher.ps1 `
  -InstallDirectory 'C:\Tools\EES-Codex-Launcher-64bit' `
  -WorkspaceDirectory 'C:\Engineering\EES-Codex-Workspace-64bit'
```

## Use it with Codex

1. Follow [Install and use Codex](docs/CODEX-SETUP.md).
2. Copy the final `Workspace:` path printed by the installer.
3. In Codex, choose **Open folder** or **Add project**, paste the complete path into the Windows folder picker, and select the folder.
4. Give Codex this task:

```text
Read AGENTS.md and launcher-config.json. Run the installation test, then explain how you will safely create, solve, and inspect 64-bit EES models in this workspace. Do not modify the installed launcher.
```

If you accepted the recommended launcher location, this command displays the exact workspace path:

```powershell
(Get-Content "$env:LOCALAPPDATA\EES-Codex-Launcher-64bit\config.json" -Raw | ConvertFrom-Json).workspace_root
```

## Included capabilities

- Enforced use of 64-bit `ees64.exe`.
- Automatic access to all five EES application libraries during controlled solves through the EES `/AI` command-line option. The launcher does not edit, replace, back up, or restore `EES.PRF64`.
- Safe staging, timeout handling, installed metadata search, and the Engineering Tool Dialog Database22 catalog.
- Heat exchanger, water-property, and open Brayton-cycle examples.
- A repeatable installation test and non-destructive uninstaller.

## Important limitations

- Generated engineering designs require review by a qualified engineer.
- Catalog routines must be compile-tested against the user's installed library build.
- The installation test compile-tests representative routines from all five application libraries; other catalog routines should still be compile-tested against the user's installed library build.
- Close interactive 64-bit EES before a controlled run. The launcher serializes automated runs and refuses to start while another `ees64.exe` process is open.

See [Catalog provenance](docs/CATALOG.md), [Troubleshooting](docs/TROUBLESHOOTING.md), and [Security model](docs/SECURITY.md).
