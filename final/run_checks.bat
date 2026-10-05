@echo off
cd /d "%~dp0"
python -B scripts\run_checks.py %*
if errorlevel 1 (
  echo Validation FAILED. See results\verification.json and logs.
  exit /b 1
)
