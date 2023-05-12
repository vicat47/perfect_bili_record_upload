@echo off
setlocal enabledelayedexpansion

REM 检查是否有文件被拖拽到脚本上
if "%~1"=="" (
    echo No files dragged onto script.
    pause
    exit /b
)

REM 循环打印拖拽到脚本上的每个文件名称
for %%i in (%*) do (
    @REM   echo %%i
    redis-cli -h REDIS_ADDRESS RPUSH render-list %%~nxi
)

pause