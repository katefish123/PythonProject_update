$ErrorActionPreference='Stop'
$outputRoot=Join-Path $PSScriptRoot 'results'
$qualification=Get-Content -LiteralPath (Join-Path $outputRoot 'simulation_qualification.json') -Raw | ConvertFrom-Json
if (@($qualification.tests.PSObject.Properties).Count -ne 15) { throw 'Fifteen coordinate lookahead checks required' }
foreach ($test in $qualification.tests.PSObject.Properties) {
    if (-not $test.Value.passed -or (Get-FileHash -LiteralPath $test.Value.log -Algorithm SHA256).Hash.ToLowerInvariant() -ne $test.Value.log_sha256) { throw "Required check changed: $($test.Name)" }
}
$sources=Get-Content -LiteralPath (Join-Path $outputRoot 'source_hashes.json') -Raw | ConvertFrom-Json
foreach ($source in $sources.PSObject.Properties) {
    if ((Get-FileHash -LiteralPath $source.Name -Algorithm SHA256).Hash.ToLowerInvariant() -ne $source.Value) { throw "Source changed after checks: $($source.Name)" }
}
$buildLog=Join-Path $outputRoot 'build_run.log'
& 'C:\pango\PDS_2022.2-SP6.4\bin\pds_shell.exe' -file (Join-Path $outputRoot 'build.tcl') -work_dir $outputRoot -project_name ddr_camera_coordqueue *> $buildLog
$buildExit=$LASTEXITCODE
$buildText=Get-Content -LiteralPath $buildLog -Raw
if ($buildExit -ne 0 -or $buildText -notmatch 'Executing : gen_bit_stream successfully\.') { throw "Coordinate lookahead build did not complete. Log: $buildLog" }
Write-Output "Coordinate lookahead bitstream generated; timing/release qualification required. Log: $buildLog"
