param([string]$OutputName = 'board_ddr_ready')
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
& 'C:\Users\夏菲\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' (Join-Path $PSScriptRoot 'prepare_ddr_build.py')
if ($LASTEXITCODE -ne 0) { throw 'DDR build preparation failed' }
$outputDir = Join-Path $taskRoot (Join-Path 'results' $OutputName)
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
& 'C:\pango\PDS_2022.2-SP6.4\bin\pds_shell.exe' -file (Join-Path $taskRoot 'pds\build_board_ddr.tcl') -work_dir $outputDir -project_name video_correct_ddr
if ($LASTEXITCODE -ne 0) { throw "PDS DDR build failed with exit code $LASTEXITCODE" }
