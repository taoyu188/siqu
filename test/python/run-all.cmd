@echo off
chcp 65001 >nul
title Python examples - Si
cd /d "%~dp0..\..\"

echo.
echo   ==========================================
echo    Python examples for Si
echo    Each script has one deliberate bug.
echo    Watch Si explain it in her bubble.
echo   ==========================================
echo.

for %%f in (test\python\01_ok.py test\python\02_type.py test\python\03_index.py test\python\04_key.py test\python\05_none.py test\python\06_name.py) do (
  echo.
  echo   -----------------------------------------
  echo   running: %%f
  echo   -----------------------------------------
  node "core\pyrun.js" "%%f"
  timeout /t 4 >nul
)

echo.
echo   Done. Press any key to close.
pause >nul
