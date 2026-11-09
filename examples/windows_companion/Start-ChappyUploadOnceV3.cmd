@echo off
setlocal
title Chappy PC Link - one-file Android to PC receive
cd /d "%~dp0"
if not exist "ChappyCompanion.exe" (
 echo Extract Windows Companion preview ZIP first.
 pause
 exit /b 1
)
echo Select a NEW local destination that does not exist.
echo One file only, maximum 4 MiB, never overwrite.
echo Windows QR-v3 YES and separate RECEIVE, Android separate consent.
"ChappyCompanion.exe" --doctor
if errorlevel 1 (
 echo No identity ready. Server was NOT started.
 pause
 exit /b 1
)
pause
chcp 65001 >nul
"ChappyCompanion.exe" --start --pair --qr --identity-pair --receive-file-once --minutes 10
set "rc=%errorlevel%"
echo Preview stopped: %rc%
pause
exit /b %rc%
