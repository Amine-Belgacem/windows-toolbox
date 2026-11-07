@echo off
setlocal DisableDelayedExpansion

set "powershell_folder=%SystemRoot%\System32\WindowsPowerShell\v1.0"
"%powershell_folder%\powershell.exe" -NoLogo -NoProfile ^
    -ExecutionPolicy Bypass ^
    -File "%~dp0powershell\add-powershell-to-path.ps1" %*
set "script_exit_code=%errorlevel%"

if not "%~1"=="" exit /b %script_exit_code%
echo.
pause
exit /b %script_exit_code%
