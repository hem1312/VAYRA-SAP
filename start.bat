@echo off
rem Double-click launcher: starts both services and opens the default browser.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1"
pause
