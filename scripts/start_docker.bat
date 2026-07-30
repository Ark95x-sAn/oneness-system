@echo off
REM Start Docker Desktop and wait for daemon
start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
echo Waiting for Docker daemon...
:loop
docker version >nul 2>&1
if %errorlevel% == 0 (
    echo Docker is ready.
    exit /b 0
)
timeout /t 3 /nobreak >nul
goto loop
