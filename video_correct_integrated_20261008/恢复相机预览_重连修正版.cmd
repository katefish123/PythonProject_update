@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\program_camera_live_bram_reconnect.ps1"
if errorlevel 1 goto failed
echo Preview Program and Verify passed. Wake the R50 if the picture is absent.
pause
exit /b 0
:failed
echo Programming failed. The detailed log is in results\hardware_20261009.
pause
exit /b 1
