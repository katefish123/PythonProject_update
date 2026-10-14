param([Parameter(Mandatory=$true)][string]$OutputRoot,[int]$RequiredChecks=27,[int]$Parallel=2)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../a_sync_20261013/assert_reproduction_inputs.ps1')
$binding=Assert-ReproductionInputs -Root $OutputRoot
$candidate=Join-Path $OutputRoot 'diagnostics/ddr_camera_hires_prefetch_20261012/results'
$simulator=(Get-Command vsim.exe -ErrorAction Stop).Source
$cases=Get-Content -LiteralPath (Join-Path $candidate 'simulation_cases.json') -Raw | ConvertFrom-Json
if(@($cases.PSObject.Properties).Count -ne $RequiredChecks){throw 'Unexpected test count'}
if($Parallel -lt 1 -or $Parallel -gt 2){throw 'Only one or two isolated test workers supported'}
$qualification=Join-Path $candidate 'reproduced_simulation_qualification.json'
@{status='running';hardware_accepted=$false} | ConvertTo-Json | Set-Content -LiteralPath $qualification
$pending=[System.Collections.Generic.Queue[object]]::new()
# Long tests start first, with every simulator library/mapping in its own directory.
foreach($case in @($cases.PSObject.Properties | Sort-Object @{Expression={if($_.Name -like 'tb_fullhd_pipeline*'){0}else{1}}},Name)){$pending.Enqueue($case)}
$running=@();$completed=[ordered]@{}
try {
 while($pending.Count -gt 0 -or $running.Count -gt 0){
  while($pending.Count -gt 0 -and $running.Count -lt $Parallel){
   $case=$pending.Dequeue();$worker=Join-Path $OutputRoot ('simulation_workers/'+$case.Name)
   New-Item -ItemType Directory -Path $worker -Force | Out-Null
   $log=Join-Path $candidate ($case.Name+'.reproduction.log');$script=Join-Path $candidate ($case.Name+'.do')
   $job=Start-Job -ArgumentList $simulator,$script,$log,$worker -ScriptBlock {
    param($exe,$script,$log,$worker)
    $ErrorActionPreference='Stop';Set-Location -LiteralPath $worker
    & $exe -c -do $script *> $log
    [int]$LASTEXITCODE
   }
   $running+=@{job=$job;name=$case.Name;marker=$case.Value;log=$log}
   Write-Output ('RUN '+$case.Name)
  }
  $null=Wait-Job -Job @($running | ForEach-Object {$_.job}) -Any -Timeout 1
  foreach($item in @($running | Where-Object {$_.job.State -ne 'Running'})){
   $exitCode=Receive-Job -Job $item.job -ErrorAction Stop
   if($item.job.State -ne 'Completed' -or @($exitCode).Count -ne 1 -or $exitCode -ne 0){throw ('Simulator failed: '+$item.name)}
   $content=Get-Content -LiteralPath $item.log -Raw
   if($content -match 'FAIL_|\*\* Error|\*\* Fatal|\*\* Warning' -or $content -notmatch [regex]::Escape($item.marker) -or $content -notmatch 'VERIFIED_PASS_BIT=1'){throw ('Regression failed: '+$item.name)}
   $completed[$item.name]=[ordered]@{passed=$true;exit_code=0;pass_message=$item.marker;log=$item.log;log_sha256=(Get-FileHash -LiteralPath $item.log -Algorithm SHA256).Hash.ToLowerInvariant()}
   Write-Output ('PASS '+$item.name);Remove-Job -Job $item.job
   $running=@($running | Where-Object {$_.name -ne $item.name})
  }
 }
 $null=Assert-ReproductionInputs -Root $OutputRoot -ExpectedDigest $binding.digest
 [ordered]@{qualified_at_utc=[DateTime]::UtcNow.ToString('o');tests=$completed;hardware_accepted=$false;source_manifest_sha256=$binding.digest;upstream_commit=$binding.commit;status='passed'} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $qualification -Encoding utf8
} finally {
 foreach($item in $running){Stop-Job -Job $item.job;Remove-Job -Job $item.job}
}
