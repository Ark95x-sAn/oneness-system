@echo off
REM Run this file as Administrator to refresh the OnenessWeb service with the current source build.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\install_oneness_web_service.ps1""'"
