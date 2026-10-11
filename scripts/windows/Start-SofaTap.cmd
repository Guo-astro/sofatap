@echo off
cd /d "%~dp0"
if not exist "%~dp0SofaTap.exe" (
  echo Keep this launcher in the complete Sofatap release folder.
  pause
  exit /b 1
)
start "" "%~dp0SofaTap.exe"
