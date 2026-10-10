@echo off
cd /d "%~dp0"
"%~dp0SofaTap.exe"
if errorlevel 1 (
  echo.
  echo Sofa Tap stopped with an error. Read the message above.
  pause
)
