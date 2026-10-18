@echo off
rem Fallback launcher: use this if the .vbs does nothing (some security policies block wscript).
start "" /min powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0orb.ps1"
