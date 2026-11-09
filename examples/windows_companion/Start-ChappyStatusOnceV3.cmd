@echo off
setlocal
title Chappy PC Link - Opt-in one-time read-only status (QR-v3)
cd /d "%~dp0"
if not exist "ChappyCompanion.exe" (
  echo Windows Companion EXE not found. Extract the preview ZIP.
  pause
  exit /b 1
)
echo One-use status: logical CPU count, RAM totals, uptime (if available).
echo No files, process list, network traffic, shell, remote control or auto-pair.
echo On PC approve the usual QR-v3 YES, then independently type STATUS.
echo On Android separately approve status after completing QR-v3 identity.
echo This is a Debug preview, NOT an always-on server.
echo.
"ChappyCompanion.exe" --doctor
if errorlevel 1 (
  echo Local QR-v3 prerequisites not ready. No server started.
  pause
  exit /b 1
)
pause
chcp 65001 >nul
"ChappyCompanion.exe" --start --pair --qr --identity-pair --status-once --minutes 10
set "code=%errorlevel%"
echo.
echo Preview stopped, exit code %code%.
pause
exit /b %code%
