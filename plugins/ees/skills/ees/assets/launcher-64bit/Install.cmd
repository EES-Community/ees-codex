@echo off
setlocal
title EES Codex Launcher 64-bit Installer
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-EES-Codex-Launcher.ps1" %*
set "INSTALL_EXIT=%ERRORLEVEL%"
echo.
if not "%INSTALL_EXIT%"=="0" echo Installation did not complete successfully.
pause
exit /b %INSTALL_EXIT%
