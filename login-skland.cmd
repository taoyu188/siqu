@echo off
chcp 65001 >nul
title Si - Skland QR Login
cd /d "%~dp0"

echo.
echo   ============================================
echo    Si - Skland QR Login
echo   ============================================
echo.
echo   A QR image will pop up. Scan it with the
echo   Skland app on your phone, then confirm.
echo.

node "%~dp0core\skland.js" --qr

echo.
echo   ---- done ----
echo   Press any key to close.
pause >nul
