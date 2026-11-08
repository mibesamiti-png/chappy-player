@echo off
setlocal
title Chappy PC Link - Create PC Identity (Local Only)
cd /d "%~dp0"
if not exist "ChappyCompanion.exe" (
  echo ChappyCompanion.exe is missing. Extract the Windows preview ZIP first.
  pause
  exit /b 1
)
echo Current user PC identity status:
"ChappyCompanion.exe" --identity-status
echo.
echo Create a PC identity only if you intentionally want to use QR-v3.
echo The Windows DPAPI key remains local to this Windows user.
echo This action does NOT start networking or create a trusted pairing.
echo Existing identities are not overwritten.
echo.
set /p "choice=Type CREATE to request first-time PC identity creation: "
if not "%choice%"=="CREATE" (
  echo Cancelled; no key creation was requested.
  pause
  exit /b 2
)
"ChappyCompanion.exe" --identity-create
set "result=%errorlevel%"
echo.
pause
exit /b %result%
