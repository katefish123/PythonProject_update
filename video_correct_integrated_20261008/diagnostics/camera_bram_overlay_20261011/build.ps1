$ErrorActionPreference = 'Stop'
$outputRoot = Join-Path $PSScriptRoot 'results'
$qualification = Get-Content -LiteralPath (Join-Path $outputRoot 'simulation_qualification.json') -Raw | ConvertFrom-Json
foreach ($test in $qualification.tests.PSObject.Properties) {
    if (-not $test.Value.passed) { throw "Overlay test failed: $($test.Name)" }
}
$buildLog = Join-Path $outputRoot 'build_run.log'
& 'C:\pango\PDS_2022.2-SP6.4\bin\pds_shell.exe' -file (Join-Path $outputRoot 'build.tcl') -work_dir $outputRoot -project_name camera_bram_overlay *> $buildLog
$buildExit = $LASTEXITCODE
$buildText = Get-Content -LiteralPath $buildLog -Raw
if ($buildExit -ne 0 -or $buildText -notmatch 'Executing : gen_bit_stream successfully\.') {
    throw "Overlay build did not complete. Log: $buildLog"
}
Write-Output "Overlay bitstream generated; timing/release qualification required. Log: $buildLog"
