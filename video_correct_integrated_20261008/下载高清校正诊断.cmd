@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\program_ddr_camera_hires_status.ps1"
if errorlevel 1 pause
