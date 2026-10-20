@echo off
rem ------------------------------------------------------------
rem  siqu demo launcher
rem  Runs the PowerShell demo with ExecutionPolicy bypassed,
rem  so the default "scripts are disabled" policy doesn't matter.
rem  Keep this file ASCII-only (cmd.exe reads it as GBK).
rem ------------------------------------------------------------
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0demo.ps1" %*
echo.
pause
