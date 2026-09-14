@echo off
setlocal
title EES Codex Launcher 32-bit Uninstaller
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\EES-Codex-Launcher-32bit\Uninstall-EES-Codex-Launcher.ps1" -InstallDirectory "%LOCALAPPDATA%\EES-Codex-Launcher-32bit"
set "UNINSTALL_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %UNINSTALL_EXIT%
