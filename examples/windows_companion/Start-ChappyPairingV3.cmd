@echo off
setlocal
title Chappy PC Link - QR-v3 Mutual Verification
cd /d "%~dp0"
if not exist "ChappyCompanion.exe" (
  echo ChappyCompanion.exe is missing. Extract the Windows preview ZIP first.
  pause
  exit /b 1
)
echo Chappy PC Link QR-v3, ONE-TIME mutual identity verification.
echo Use only on a trusted private LAN with your own Android device.
echo This does not authorize files, remote control or persistent sessions.
echo A PC signing identity must already be created by your explicit action.
echo.
"ChappyCompanion.exe" --doctor
if errorlevel 1 (
  echo.
  echo Local preflight needs attention. No network listener was started.
  echo To create your first PC key intentionally, use:
  echo   ChappyCompanion.exe --identity-create
  pause
  exit /b 1
)
echo.
echo On Android: Network Lab ^> PC - workstation ^> scan ^> QR-v3.
echo Compare the short code on BOTH devices; approve only if it matches.
echo The phone must separately approve the one-time device signature.
echo Ctrl+C stops the temporary listener at any time.
echo.
pause
chcp 65001 >nul
"ChappyCompanion.exe" --start --pair --qr --identity-pair --minutes 10
set "result=%errorlevel%"
echo.
echo QR-v3 preview stopped. Exit code: %result%
pause
exit /b %result%
