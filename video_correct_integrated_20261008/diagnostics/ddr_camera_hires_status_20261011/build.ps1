$ErrorActionPreference = 'Stop'
$outputRoot = Join-Path $PSScriptRoot 'results'
$qualification = Get-Content -LiteralPath (Join-Path $outputRoot 'simulation_qualification.json') -Raw | ConvertFrom-Json
if (@($qualification.tests.PSObject.Properties).Count -ne 8) { throw 'Eight diagnostic regressions required' }
foreach ($test in $qualification.tests.PSObject.Properties) {
    if (-not $test.Value.passed) { throw "Required regression failed: $($test.Name)" }
}
$buildLog = Join-Path $outputRoot 'build_run.log'
& 'C:\pango\PDS_2022.2-SP6.4\bin\pds_shell.exe' -file (Join-Path $outputRoot 'build.tcl') -work_dir $outputRoot -project_name ddr_camera_hires_status *> $buildLog
$buildExit = $LASTEXITCODE
$buildText = Get-Content -LiteralPath $buildLog -Raw
if ($buildExit -ne 0 -or $buildText -notmatch 'Executing : gen_bit_stream successfully\.') {
    throw "DDR diagnostic build did not complete. Log: $buildLog"
}
Write-Output "DDR diagnostic bitstream generated; timing/release qualification required. Log: $buildLog"
