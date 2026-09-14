@echo off
setlocal
title EES Codex Launcher 32-bit Installer
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-EES-Codex-Launcher.ps1" %*
set "INSTALL_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %INSTALL_EXIT%
