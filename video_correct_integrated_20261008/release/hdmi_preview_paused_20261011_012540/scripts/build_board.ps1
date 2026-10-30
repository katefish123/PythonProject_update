param([string]$OutputName = 'board_bram_final')
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$pythonExe = 'C:\Users\夏菲\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
& $pythonExe (Join-Path $PSScriptRoot 'prepare_board_build.py')
if ($LASTEXITCODE -ne 0) { throw 'Board build preparation failed' }
$outputDir = Join-Path $taskRoot (Join-Path 'results' $OutputName)
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
& 'C:\pango\PDS_2022.2-SP6.4\bin\pds_shell.exe' -file (Join-Path $taskRoot 'pds\build_board_bram.tcl') -work_dir $outputDir -project_name video_correct_bram
if ($LASTEXITCODE -ne 0) { throw "PDS failed with exit code $LASTEXITCODE" }
