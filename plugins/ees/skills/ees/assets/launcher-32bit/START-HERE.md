# EES Codex Launcher — 32-bit edition

This Windows package lets Codex—or a person using PowerShell—write an EES equations file, solve it with **32-bit EES Professional**, and read a fresh text result. It requires no Python installation.

This edition is deliberately locked to 32-bit EES. Its installer, solver launcher, discovery command, and library-catalog commands reject `ees64.exe`. The package does **not** include EES, an EES license, Codex, or OpenAI software.

## What you need

- Windows 10 or 11.
- A working 32-bit EES Professional installation that supports the `/AI` command-line option. The `/solve` feature is also required.
- Normally, EES at `C:\EES32\ees.exe`. A custom location containing an executable named `ees.exe` can be supplied to the installer.
- Windows PowerShell 5.1 or PowerShell 7.
- Codex is optional. See [Install and use Codex](docs/CODEX-SETUP.md) if you do not have it.

## Install the launcher

1. Download the ZIP and save it locally.
2. Right-click the ZIP, select **Properties**, and select **Unblock** if Windows shows that option. Select **OK**.
3. Extract the complete ZIP. Do not run the installer while browsing inside the ZIP.
4. Open the extracted folder and double-click **Install.cmd**.
5. The installer asks where to install the launcher and where to create the models-and-results workspace. Press **Enter** to accept each recommended path. The recommended workspace is `%USERPROFILE%\EES-Codex-Workspace-32bit`, directly inside your Windows user folder—not inside Documents, Music, or OneDrive. If entering another location, type a complete path beginning with a drive letter, such as `C:\Engineering\EES-Codex-Workspace-32bit`; relative entries are rejected.
6. It selects `C:\EES32\ees.exe`, runs real 32-bit EES calculations, verifies `Q_dot = 200 kW`, checks the Database22 catalog, and uses `/AI` to test routines from all five application libraries without `$Load`. It also verifies that the persistent library-autoload setting in `EES.PRF` was not changed. A green success message confirms the installation.

If 32-bit EES is somewhere else, open PowerShell in the extracted folder and run:

```powershell
.\Install-EES-Codex-Launcher.ps1 -EesPath 'D:\your-folder\ees.exe'
```

The installer rejects `ees64.exe`, does not require administrator privileges, and does not add anything to the system `PATH`.

For an unattended or scripted installation, supply both locations explicitly:

```powershell
.\Install-EES-Codex-Launcher.ps1 `
  -InstallDirectory 'C:\Tools\EES-Codex-Launcher-32bit' `
  -WorkspaceDirectory 'C:\Engineering\EES-Codex-Workspace-32bit'
```

## Use it with Codex

1. Follow [Install and use Codex](docs/CODEX-SETUP.md).
2. Find the final `Workspace:` path printed by the installer. This is the exact folder you selected. Do not look for a folder literally named `%USERPROFILE%`.
3. In Codex, choose **Open folder** or **Add project**. In the Windows folder picker, click the address bar, paste the complete workspace path, press **Enter**, and then choose **Select Folder**. If you accepted the recommended location, it will normally be `C:\Users\your-name\EES-Codex-Workspace-32bit`.
4. Give Codex this first task:

```text
Read AGENTS.md and launcher-config.json. Run the installation test, then explain how you will safely create, solve, and inspect 32-bit EES models in this workspace. Do not modify the installed launcher.
```

Codex may ask permission to launch EES because it is a desktop application outside its writable project. Review the fixed `Run-EES.ps1` path and approve that invocation when you are satisfied.

If you no longer have the installer window and used the recommended launcher location, open PowerShell and run this command to display the exact workspace path:

```powershell
(Get-Content "$env:LOCALAPPDATA\EES-Codex-Launcher-32bit\config.json" -Raw | ConvertFrom-Json).workspace_root
```

## Use it without Codex

The launcher is useful on its own. Follow [Manual PowerShell use](docs/MANUAL-USE.md).

## Included capabilities

- Enforced use of 32-bit `ees.exe` throughout the installed toolchain.
- Automatic access to all five EES application libraries during Codex-controlled solves through the EES `/AI` command-line option. The launcher does not edit, replace, back up, or restore `EES.PRF`.
- Safe staging of one EES `.txt` equations file and one result file.
- Timeout and diagnostic handling for hidden EES error dialogs.
- Search of the selected installation's `EES_Tool_Metadata.json`.
- Search of the richer Engineering Tool Dialog Database22 catalog, including UnitType descriptions.
- Heat exchanger, water-property, and open Brayton-cycle examples.
- A repeatable installation test and a non-destructive uninstaller.

## Important limitations

- Generated engineering designs require review by a qualified engineer. The launcher verifies software execution, not design fitness or safety.
- The safe workflow blocks directives that can run external code, load arbitrary files, or create extra output files. It permits only a short exact whitelist of built-in EES library names returned by the catalog.
- A catalog match is not proof that a routine will execute in every library revision. Codex must perform a small compile test against the installed 32-bit libraries.
- Close interactive 32-bit EES before a Codex-controlled run. The launcher serializes automated runs and refuses to start while another `ees.exe` process is open.

For details, see [Catalog provenance](docs/CATALOG.md), [Troubleshooting](docs/TROUBLESHOOTING.md), and [Security model](docs/SECURITY.md).
