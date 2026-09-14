# Install and use Codex on Windows

The recommended path is the native ChatGPT desktop app for Windows, which includes Codex workflows and native PowerShell support.

## Install Codex for the first time

1. Install the [ChatGPT desktop app for Windows](https://learn.chatgpt.com/docs/windows/windows-app) from the Microsoft Store. The official OpenAI documentation also gives this command-line installation option:

   ```powershell
   winget install --id 9PLM9XGG6VKS -s msstore
   ```

2. Start the app and sign in with your ChatGPT account. Availability can depend on your account or organization settings; follow the choices presented by the app.
3. Copy the exact `Workspace:` path displayed by the launcher installer. If you used the recommended launcher location and closed the installer, display the path by opening PowerShell and running:

   ```powershell
   (Get-Content "$env:LOCALAPPDATA\EES-Codex-Launcher-32bit\config.json" -Raw | ConvertFrom-Json).workspace_root
   ```

   Always use the recorded path. It remains authoritative even if Windows folders have been redirected or you selected a custom location.
4. In Codex, choose **Open folder** or **Add project**. When the Windows folder picker appears, click its address bar, paste the complete workspace path, press **Enter**, and choose **Select Folder**. The selected folder should contain `AGENTS.md`, `launcher-config.json`, `examples`, `models`, and `results`.
5. Use the Windows-native/PowerShell environment. EES is a Windows desktop application, so a WSL-only environment cannot launch it directly.
6. Keep the project sandbox enabled and choose **Ask for approval**. The official OpenAI documentation recommends retaining sandbox boundaries and using targeted approvals rather than full access.
7. Start a task with:

   ```text
   Read AGENTS.md and launcher-config.json. Run the installation test, then explain how you will safely create, solve, and inspect EES models in this workspace. Do not modify the installed launcher.
   ```

8. Codex should read the project instructions, write models only inside the workspace, and invoke the fixed launcher from `%LOCALAPPDATA%\EES-Codex-Launcher-32bit`.
9. When approval is requested, verify that the command calls the installed `Run-EES.ps1`, uses this project as `-WorkspaceRoot`, and selects the configured 32-bit `ees.exe`.

## A first design request

After the test succeeds, try:

```text
Design a simple open-air Brayton cycle producing 100 kW net power. Use EES fluid Air, compressor and turbine isentropic efficiencies of 88%, and a maximum air temperature of 1000 deg C. Search the installed EES library metadata before deciding whether to use a library routine. Write the EES model, run it, inspect the results, check energy balances and constraints, and summarize the design.
```

## Optional terminal interface

Users who prefer a terminal can use the [official Codex CLI instructions](https://learn.chatgpt.com/docs/codex/cli). The desktop app is simpler for this package because it provides native Windows project, approval, terminal, and file-review workflows in one interface.

These links point to live official OpenAI documentation because installation and account availability can change after this package is released.
