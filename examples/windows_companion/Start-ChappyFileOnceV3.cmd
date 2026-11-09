@echo off
setlocal
title Chappy PC Link - one chosen file to Android (QR-v3)
cd /d "%~dp0"
if not exist "ChappyCompanion.exe" (
  echo Preview EXE is missing. Extract the Windows Companion artifact first.
  pause
  exit /b 1
)
echo Share ONE file only. No directory browsing, remote file listing, or PC control.
echo Windows requires QR-v3 YES, then separate SEND.
echo Android requires a separate file receive consent and native Save As.
echo Max file size 4 MiB; this preview does not resume interrupted transfers.
echo.
"ChappyCompanion.exe" --doctor
if errorlevel 1 (
  echo Identity prerequisite not ready. Server was NOT started.
  pause
  exit /b 1
)
pause
chcp 65001 >nul
"ChappyCompanion.exe" --start --pair --qr --identity-pair --send-file-once --minutes 10
set "code=%errorlevel%"
echo.
echo Transfer preview stopped with code %code%.
pause
exit /b %code%
