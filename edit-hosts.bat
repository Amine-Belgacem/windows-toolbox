@echo off
setlocal DisableDelayedExpansion

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass ^
    -File "%~dp0powershell\edit-hosts.ps1" %*
set "script_exit_code=%errorlevel%"
exit /b %script_exit_code%
