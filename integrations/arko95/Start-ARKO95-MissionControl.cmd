@echo off
setlocal
pwsh.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0shell\ARKO95.MissionControl.ps1" -ProjectRoot "%~dp0"
