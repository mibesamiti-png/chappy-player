@echo off
setlocal
title Chappy PC Link - One media key (QR-v3 Debug)
cd /d "%~dp0"
if not exist "ChappyCompanion.exe" (
  echo Windows Companion EXE not found. Extract the preview ZIP.
  pause
  exit /b 1
)
echo Permits ONE volume up/down, mute toggle or play/pause command.
echo PC identity YES then independent CONTROL for the exact chosen key.
echo Android must approve again. NO shell, arbitrary keys, files or mouse.
echo Debug preview; no unattended remote operation.
echo.
"ChappyCompanion.exe" --doctor
if errorlevel 1 (
  echo PC QR-v3 preflight failed. Nothing was started.
  pause
  exit /b 1
)
pause
chcp 65001 >nul
"ChappyCompanion.exe" --start --pair --qr --identity-pair --media-once --minutes 10
set "code=%errorlevel%"
echo Preview stopped, exit code %code%.
pause
exit /b %code%
