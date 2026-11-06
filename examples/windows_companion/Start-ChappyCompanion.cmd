@echo off
title Chappy Companion - LAN Discovery
cd /d "%~dp0"
if not exist "ChappyCompanion.exe" (
  echo ChappyCompanion.exe was not found in this folder.
  echo Download the Windows CI preview artifact and extract both files together.
  pause
  exit /b 1
)
echo You are about to advertise a temporary PC discovery beacon for 10 minutes.
echo Only use this on a Wi-Fi/LAN that you own or manage.
echo Press Ctrl+C to stop earlier.
echo.
pause
"ChappyCompanion.exe" --start --minutes 10
echo.
echo Chappy Companion is stopped.
pause
