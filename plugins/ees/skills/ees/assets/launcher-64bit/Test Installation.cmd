@echo off
setlocal
title EES Codex Launcher 64-bit Test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\EES-Codex-Launcher-64bit\Test-Installation.ps1"
set "TEST_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %TEST_EXIT%
