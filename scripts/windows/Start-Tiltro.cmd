@echo off
cd /d "%~dp0"
"%~dp0Tiltro.exe"
if errorlevel 1 (
  echo.
  echo Tiltro stopped with an error. Read the message above.
  pause
)
