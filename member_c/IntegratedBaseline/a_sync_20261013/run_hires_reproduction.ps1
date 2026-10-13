param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'assert_reproduction_inputs.ps1')
$binding=Assert-ReproductionInputs -Root $OutputRoot
$candidate=Join-Path $OutputRoot 'diagnostics\ddr_camera_hires_prefetch_20261012\results'
$simulator=(Get-Command vsim.exe -ErrorAction Stop).Source
$cases=Get-Content -LiteralPath (Join-Path $candidate 'simulation_cases.json') -Raw | ConvertFrom-Json
if(@($cases.PSObject.Properties).Count -ne 12){throw 'Expected twelve upstream tests'}
$completed=[ordered]@{}
[ordered]@{status='running';hardware_accepted=$false} | ConvertTo-Json |
 Set-Content -LiteralPath (Join-Path $candidate 'reproduced_simulation_qualification.json') -Encoding utf8
Push-Location -LiteralPath $candidate
try {
 foreach($case in $cases.PSObject.Properties){
  $name=$case.Name
  $log=Join-Path $candidate "$name.reproduction.log"
  & $simulator -c -do "$name.do" *> $log
  $exitCode=$LASTEXITCODE
  $content=Get-Content -LiteralPath $log -Raw
  if($exitCode -ne 0 -or $content -match 'FAIL_|\*\* Error|\*\* Fatal|\*\* Warning' -or
     $content -notmatch [regex]::Escape($case.Value) -or $content -notmatch 'VERIFIED_PASS_BIT=1'){
   throw "Regression failed: $name; see $log"
  }
  $completed[$name]=[ordered]@{passed=$true;exit_code=$exitCode;pass_message=$case.Value;
   log=$log;log_sha256=(Get-FileHash -LiteralPath $log -Algorithm SHA256).Hash.ToLowerInvariant()}
  Write-Output "PASS $name"
 }
 $null=Assert-ReproductionInputs -Root $OutputRoot -ExpectedDigest $binding.digest
 [ordered]@{qualified_at_utc=[DateTime]::UtcNow.ToString('o');tests=$completed;hardware_accepted=$false;
  source_manifest_sha256=$binding.digest;upstream_commit=$binding.commit;status='passed'} |
  ConvertTo-Json -Depth 6 | Set-Content -LiteralPath 'reproduced_simulation_qualification.json' -Encoding utf8
} finally {Pop-Location}
