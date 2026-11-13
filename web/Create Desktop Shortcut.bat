@echo off
rem === Guitar Quest: puts a clickable shortcut on the Windows desktop ===
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\create_shortcut.ps1"
echo.
pause
