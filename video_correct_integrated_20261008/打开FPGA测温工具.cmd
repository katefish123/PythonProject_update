@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\open_fpga_temperature.ps1"
if errorlevel 1 pause
