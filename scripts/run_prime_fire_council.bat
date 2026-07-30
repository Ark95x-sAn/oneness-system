@echo off
REM Prime Fire Council — launch AI serve web control center + Oneness orchestrator
cd /d "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem"
call venv\Scripts\activate
set DEMO_MODE=true
start "Oneness Orchestrator" venv\Scripts\python src\oneness_orchestrator.py --demo
start "Oneness Web" dotnet run --project src\Oneness.Web --urls http://localhost:5050
start http://localhost:5050
echo Prime Fire Council active. Open http://localhost:5050
