@echo off
setlocal
cd /d "%~dp0.."

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0nanoops.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo.
    echo NanoOps task failed.
    pause
)

exit /b %EXIT_CODE%
