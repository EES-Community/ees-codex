@echo off
setlocal
title EES Codex Launcher 32-bit Test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\EES-Codex-Launcher-32bit\Test-Installation.ps1"
set "TEST_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %TEST_EXIT%
