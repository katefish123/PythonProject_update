param([string]$OutputName='internal_fixture_ddr')
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$py='C:\Users\??\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
& $py (Join-Path $PSScriptRoot 'make_internal_fixture.py')
if($LASTEXITCODE -ne 0){throw 'Fixture golden generation failed'}
& powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'sim\run_internal_fixture_sim.ps1')
if($LASTEXITCODE -ne 0){throw 'Fixture raster simulation failed'}
$required=@(
 'reference\baselines\ddr_before_hdmi_startup_fix\rtl\hdmi\hdmi_config.v',
 'constr\board_ddr.fdc',
 'rtl\memory\ddr3_ip\ddr3_ip.v')
foreach($item in $required){if(!(Test-Path -LiteralPath (Join-Path $root $item))){throw "Missing required baseline/build input: $item"}}
$out=Join-Path $PSScriptRoot (Join-Path 'results' $OutputName)
New-Item -ItemType Directory -Force -Path $out | Out-Null
$pds='C:\pango\PDS_2022.2-SP6.4\bin\pds_shell.exe'
& $pds -file (Join-Path $PSScriptRoot 'pds\build_internal_fixture.tcl') -work_dir $out -project_name video_correct_ddr_internal_fixture
if($LASTEXITCODE -ne 0){throw "PDS build failed with exit code $LASTEXITCODE"}
Write-Host "Independent diagnostic build completed in $out. No programmer/JTAG step was run."
