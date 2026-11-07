@echo off
setlocal DisableDelayedExpansion

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass ^
    -File "%~dp0powershell\add-app-to-path.ps1" %*
set "script_exit_code=%errorlevel%"

if not "%~1"=="" exit /b %script_exit_code%
echo.
pause
exit /b %script_exit_code%
