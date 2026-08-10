@echo off
REM === Operations Mind Launcher ===
REM Unified PC Operations Oversight Orchestration Brain
REM Usage: run_ops_mind.bat [--once|--cycle|--health|--status|--loop]

cd /d C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem

REM Try venv Python first, fall back to system Python
set PYTHON=venv\Scripts\python.exe
if not exist %PYTHON% set PYTHON=python

echo ============================================
echo   OPERATIONS MIND — PC Oversight Brain
echo ============================================
echo.

if "%1"=="" (
    echo Running single cycle with report and remediations...
    %PYTHON% -m src.ops_mind.mind --once
) else (
    %PYTHON% -m src.ops_mind.mind %*
)