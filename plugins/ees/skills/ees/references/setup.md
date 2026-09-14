# Windows launcher setup

The skill ships the original 0.4.0-beta distributions under `assets/launcher-32bit/` and `assets/launcher-64bit/`, relative to the skill directory. Each contains its installer, scripts, catalog, examples, notices, and documentation. Choose based on EES's edition, not Windows bitness.

1. Check the user's supplied executable path, or the standard paths `C:\EES32\ees.exe` and `C:\EES64\ees64.exe`. If both are available and the user has not chosen, ask which EES edition to use. A compatible EES Professional installation must already exist; this plugin does not supply it.
2. Read `START-HERE.md` in the chosen asset directory. Resolve the skill directory to its actual path; do not assume a particular plugin-cache path.
3. For user-driven installation, open that directory and run `Install.cmd`. For agent-driven installation, use `Install-EES-Codex-Launcher.ps1` with explicit absolute `-InstallDirectory`, `-WorkspaceDirectory`, and `-EesPath` arguments, so the installer does not wait for console input. Use Windows PowerShell or PowerShell 7 to execute it.
4. Recommended paths are `%LOCALAPPDATA%\EES-Codex-Launcher-32bit` and `%USERPROFILE%\EES-Codex-Workspace-32bit`, with `64bit` substituted for the other edition. Keep the launcher and workspace separate and neither nested inside the other. Do not choose an existing EES installation as either destination. Preserve an existing user's workspace choice.
5. Installation normally runs actual EES calculations: a heat-exchanger result of 200 kW, library catalog lookup, five library calculations, and an autoload-preference check. Read the final test outcome. The earlier “files installed” message does not mean the test passed. Do not use `-SkipTest` and then report successful runtime verification.
6. Read the generated workspace `launcher-config.json`. For later verification, run the installed `Test-Installation.ps1` as a separate PowerShell process; it exits its host and overwrites its known test-result files in the original workspace.

The launchers do not require administrator privileges, Python, Node, a service, or a system PATH change. They do not install EES or Codex. The exact minimum EES version is not specified by these upstream packages; test the required `/AI` capability against the customer's installation.

Treat a plugin update and an installed-launcher update as separate operations. Updating the plugin assets does not refresh the copy in LocalAppData. Rerunning the installer updates launcher files and configuration, preserves existing workspace template files, and runs its tests. Read existing workspace instructions before recommending a refresh.

If installation fails, use the selected distribution's `docs/TROUBLESHOOTING.md`. The upstream numerical tests compare specific printed values and inspect fixed preference-file offsets; failures on another EES release need investigation and do not automatically prove that EES is unusable.
