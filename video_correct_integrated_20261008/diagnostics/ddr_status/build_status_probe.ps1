param([string]$OutputName='ddr_status_probe')
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$sim=Join-Path $PSScriptRoot 'run_status_sim.ps1'
& powershell -NoProfile -ExecutionPolicy Bypass -File $sim
if($LASTEXITCODE -ne 0){throw 'Status-screen simulation verification failed; PDS was not started.'}
$output=Join-Path $root (Join-Path 'results' $OutputName)
New-Item -ItemType Directory -Force -Path $output | Out-Null
$log=Join-Path $output 'pds_build.log'
& 'C:\pango\PDS_2022.2-SP6.4\bin\pds_shell.exe' -file (Join-Path $PSScriptRoot 'pds\build_ddr_status.tcl') -work_dir $output -project_name video_correct_ddr_status *> $log
if($LASTEXITCODE -ne 0){throw "Diagnostic PDS build failed ($LASTEXITCODE); see $log"}
Write-Output "Diagnostic build complete: $output"
Get-ChildItem $output -Recurse -File -Include '*.sbit','*.smsk','*.rtr' | Select-Object FullName,Length
