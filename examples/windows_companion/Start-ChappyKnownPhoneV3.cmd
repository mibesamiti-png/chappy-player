@echo off
setlocal
title Chappy PC Link - Manually Compare Known Phone
cd /d "%~dp0"
if not exist "ChappyCompanion.exe" (
  echo ChappyCompanion.exe is missing. Extract the Windows preview ZIP first.
  pause
  exit /b 1
)
echo This optional QR-v3 mode compares a PREVIOUSLY VERIFIED phone key.
echo You will manually select a public fingerprint before the listener starts.
echo A matching fingerprint alone grants NO trust; both signatures and
echo both approvals are still required for this one-time verification.
echo.
"ChappyCompanion.exe" --doctor
if errorlevel 1 (
  echo Local preflight failed; no pairing listener started.
  pause
  exit /b 1
)
echo.
pause
chcp 65001 >nul
"ChappyCompanion.exe" --start --pair --qr --identity-pair --compare-known-phone --minutes 10
set "result=%errorlevel%"
echo.
echo Known-phone QR-v3 preview stopped. Exit code: %result%
pause
exit /b %result%
