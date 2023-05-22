@echo off
setlocal enabledelayedexpansion

REM 获取脚本所在目录
set "script_dir=%~dp0"

REM 构建完整的文件路径
set "file_path=%script_dir%bvid.txt"

REM 打印文件路径
echo File path: %file_path%

REM 检查文件是否存在
if not exist "%file_path%" (
    echo File "bvid.txt" does not exist in the script directory.
    pause
    exit /b
)


REM 读取文件内容
set /p content=<"%file_path%"

REM 打印文件内容
echo %content%

REM 检查是否有文件被拖拽到脚本上
if "%~1"=="" (
    echo No files dragged onto script.
    pause
    exit /b
)

REM 循环打印拖拽到脚本上的每个文件名称
for %%i in (%*) do (
    @REM   echo %%i
    redis-cli -h %REDIS_ADDRESS% RPUSH render-list "{\"filename\": \"%%~nxi\", \"bvid\": \"!content!\" }"
)

pause