@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnostics\ddr_camera_black_20261014\program.ps1"
if errorlevel 1 pause
