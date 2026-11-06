@echo off
title Chappy Companion - QR Pairing Preview
cd /d "%~dp0"
if not exist "ChappyCompanion.exe" (
  echo ChappyCompanion.exe was not found here.
  echo Download and extract the Windows Companion Preview artifact.
  pause
  exit /b 1
)
echo This opens a TEMPORARY QR invitation on your own PC.
echo Only use this on a private network you own or manage.
echo It expires after 10 minutes or ONE request.
echo You must compare the six-character code on your phone and PC,
echo then type YES on your PC to confirm.
echo No PC files, commands, or traffic become accessible.
echo Ctrl+C stops the session. Close the QR image viewer afterward.
echo.
pause
"ChappyCompanion.exe" --start --pair --qr --minutes 10
echo.
echo QR confirmation preview stopped.
pause
