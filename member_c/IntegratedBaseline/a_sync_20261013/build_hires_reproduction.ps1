param(
 [Parameter(Mandatory=$true)][string]$OutputRoot,
 [Parameter(Mandatory=$true)][string]$PdsExe
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'assert_reproduction_inputs.ps1')
$binding=Assert-ReproductionInputs -Root $OutputRoot
$candidate=Join-Path $OutputRoot 'diagnostics\ddr_camera_hires_prefetch_20261012\results'
$manifest=Get-Content -LiteralPath (Join-Path $OutputRoot 'reproduction_manifest.json') -Raw | ConvertFrom-Json
$qualification=Get-Content -LiteralPath (Join-Path $candidate 'reproduced_simulation_qualification.json') -Raw | ConvertFrom-Json
if($qualification.status -ne 'passed' -or $qualification.source_manifest_sha256 -ne $binding.digest -or
   $qualification.upstream_commit -ne $binding.commit){throw 'Simulation evidence belongs to different or unqualified inputs'}
$simulationDigest=(Get-FileHash -LiteralPath (Join-Path $candidate 'reproduced_simulation_qualification.json') -Algorithm SHA256).Hash.ToLowerInvariant()
if(@($qualification.tests.PSObject.Properties).Count -ne 12){throw 'Twelve fresh checks required'}
foreach($test in $qualification.tests.PSObject.Properties){
 if(-not $test.Value.passed -or
    (Get-FileHash -LiteralPath $test.Value.log -Algorithm SHA256).Hash.ToLowerInvariant() -ne $test.Value.log_sha256){
  throw "Simulation evidence invalid: $($test.Name)"
 }
}
$run=Join-Path $OutputRoot ('build_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $run -ErrorAction Stop | Out-Null
$log=Join-Path $run 'build.log'
Write-Output "Build directory: $run"
& $PdsExe -file (Join-Path $candidate 'build.tcl') -work_dir $run -project_name ddr_camera_hires_prefetch *> $log
$exitCode=$LASTEXITCODE
$text=Get-Content -LiteralPath $log -Raw
if($exitCode -ne 0 -or $text -notmatch 'Executing : gen_bit_stream successfully\.'){
 throw "PDS build failed: $log"
}
$timing=@(Get-ChildItem -LiteralPath $run -Recurse -Filter '*timing_summary_after_hold_fix.txt')
if($timing.Count -ne 1 -or (Get-Content -LiteralPath $timing[0].FullName -Raw) -notmatch 'Design Summary : All Constraints Met\.'){
 throw "Final timing qualification failed: $run"
}
$artifacts=[ordered]@{}
foreach($extension in @('sbit','smsk')){
 $files=@(Get-ChildItem -LiteralPath $run -Recurse -Filter "video_correct_ddr_top.$extension")
 if($files.Count -ne 1){throw "Expected one $extension artifact"}
 $artifacts[$extension]=[ordered]@{path=$files[0].FullName;sha256=(Get-FileHash -LiteralPath $files[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$null=Assert-ReproductionInputs -Root $OutputRoot -ExpectedDigest $binding.digest
if((Get-FileHash -LiteralPath (Join-Path $candidate 'reproduced_simulation_qualification.json') -Algorithm SHA256).Hash.ToLowerInvariant() -ne $simulationDigest){throw 'Simulation qualification changed during build'}
[ordered]@{qualified_at_utc=[DateTime]::UtcNow.ToString('o');upstream_commit=$manifest.upstream_commit;
 simulation_qualification_sha256=$simulationDigest;
 simulations_passed=$true;timing_passed=$true;hardware_accepted=$false;
 source_manifest_sha256=(Get-FileHash -LiteralPath (Join-Path $OutputRoot 'reproduction_manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant();
 build_log=$log;timing_report=$timing[0].FullName;artifacts=$artifacts} |
 ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'build_qualification.json') -Encoding utf8
Write-Output "BUILD_AND_TIMING_PASS $run"
