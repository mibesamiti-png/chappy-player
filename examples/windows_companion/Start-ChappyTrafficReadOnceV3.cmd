@echo off
setlocal
title Chappy PC Link - One-time owner-PC traffic counters (QR-v3)
cd /d "%~dp0"
if not exist "ChappyCompanion.exe" (
  echo Windows Companion EXE not found. Extract the Debug preview ZIP.
  pause
  exit /b 1
)
echo ONE 10-second capture of THIS PC's aggregate received/sent byte counters.
echo All network adapters count; Wi-Fi, Ethernet, VPN, virtual interfaces.
echo No packet contents, endpoints, other devices or background monitoring.
echo PC: independently approve YES then TRAFFIC. Android: separate approvals.
echo.
"ChappyCompanion.exe" --doctor
if errorlevel 1 (
  echo QR-v3 prerequisites not ready. Nothing started.
  pause
  exit /b 1
)
pause
chcp 65001 >nul
"ChappyCompanion.exe" --start --pair --qr --identity-pair --traffic-read-once --traffic-read-seconds 10 --minutes 10
set "code=%errorlevel%"
echo.
echo Preview stopped, exit code %code%.
pause
exit /b %code%
