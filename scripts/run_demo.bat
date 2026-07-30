@echo off
REM Run Oneness System orchestrator in demo mode
cd /d "C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem"
call venv\Scripts\activate
set DEMO_MODE=true
python src\oneness_orchestrator.py --demo
