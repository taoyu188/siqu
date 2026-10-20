@echo off
chcp 65001 >nul
title Si - Endfield Desktop Pet
cd /d "%~dp0"

echo.
echo   ============================================
echo    Si - Endfield Desktop Pet
echo   ============================================
echo.

where node >nul 2>nul
if errorlevel 1 (
  echo   [!] Node.js not found.
  echo.
  echo   This project needs Node.js 18 or newer.
  echo   Download: https://nodejs.org/
  echo.
  echo   Install it, then run this file again.
  echo.
  pause
  exit /b 1
)

echo   Node.js found:
node -v
echo.
echo   Starting...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Start-Siqu.ps1"

echo.
echo   If no pet appeared, check the log:
echo     %%USERPROFILE%%\.siqu\pet.log
echo.
pause
