@echo off
REM === Comet Warspace Chrome Connection ===
REM Opens Comet Commander + Oneness.Web dashboard in Chrome

start chrome "file:///C:/Users/ArcXN/OneDrive/Desktop/OnenessSystem/comet_commander.html"
timeout /t 2 /nobreak >nul
start chrome "http://localhost:5050"
echo Comet Warspace connected to Chrome.
echo - Comet Commander dashboard opened
echo - Oneness.Web API dashboard opened
timeout /t 3 /nobreak >nul
