@echo off
title Chappy Companion - One-time PC Confirmation Preview
cd /d "%~dp0"
if not exist "ChappyCompanion.exe" (
  echo ChappyCompanion.exe was not found.
  echo Download and extract the Windows CI preview artifact.
  pause
  exit /b 1
)
echo WARNING: This is a preview for a private LAN you own or manage.
echo The PC will advertise itself and temporarily accept a PINNED TLS connection.
echo The app will display a fresh certificate fingerprint for your phone.
echo The phone must show the SAME six-character code before you type YES.
echo No files or commands will be shared. Ctrl+C stops this console.
echo.
pause
"ChappyCompanion.exe" --start --pair --minutes 10
echo.
echo PC confirmation preview is stopped.
pause
