@echo off
setlocal
title EES Codex Launcher 64-bit Uninstaller
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\EES-Codex-Launcher-64bit\Uninstall-EES-Codex-Launcher.ps1"
set "UNINSTALL_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %UNINSTALL_EXIT%
