@echo off
setlocal
title Chappy remote traffic snapshot - manual Windows PC export
cd /d "%~dp0"
if not exist "ChappyCompanion.exe" (
  echo Companion EXE missing. Extract the Windows preview ZIP first.
  pause
  exit /b 1
)
echo.
echo Measure only THIS PC's receive/send bytes for 10 seconds.
echo All network adapters are included, not Wi-Fi-only.
echo NO other devices, traffic contents, sites or packets are captured.
echo Generates a NEW local JSON only. No server starts.
echo Type TRAFFIC when asked if you approve.
echo.
"ChappyCompanion.exe" --traffic-export --traffic-seconds 10
set "code=%errorlevel%"
echo Import the generated JSON on your Android in Network Lab.
pause
exit /b %code%
