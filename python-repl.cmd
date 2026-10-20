@echo off
chcp 65001 >nul
title Python 3.8 - interactive
cd /d "%USERPROFILE%"

echo.
echo   Python 3.8 (32-bit)  -  type exit() to quit
echo   UTF-8 console enabled
echo.

py

echo.
echo   Python exited. Press any key to close.
pause >nul
