@echo off
setlocal

if "%~1"=="" (
    echo Drag one or more video files onto this script.
    pause
    exit /b 1
)

where powershell.exe >nul 2>nul
if errorlevel 1 (
    echo powershell.exe not found.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0enqueue_render.ps1" %*
set "exit_code=%errorlevel%"

if not "%exit_code%"=="0" (
    echo.
    echo Enqueue failed with exit code %exit_code%.
)

pause
exit /b %exit_code%
