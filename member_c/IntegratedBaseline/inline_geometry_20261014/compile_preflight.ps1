param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../a_sync_20261013/assert_reproduction_inputs.ps1')
$binding=Assert-ReproductionInputs -Root $OutputRoot
$candidate=Join-Path $OutputRoot 'diagnostics/ddr_camera_hires_prefetch_20261012/results'
$cases=Get-Content -LiteralPath (Join-Path $candidate 'simulation_cases.json') -Raw | ConvertFrom-Json
$worker=Join-Path $OutputRoot 'compile_preflight'
New-Item -ItemType Directory -Path $worker -Force | Out-Null
$commands=[System.Collections.Generic.List[string]]::new()
foreach($case in $cases.PSObject.Properties){
 $lines=@(foreach($line in (Get-Content -LiteralPath (Join-Path $candidate ($case.Name+'.do')))){
  if($line -match '^vsim '){break}
  if($line -match '^(onerror|if|vmap|vlog) '){$line}
 })
 if($lines.Count -ne 4 -or $lines[3] -notmatch '^vlog '){throw ('Unexpected compile script: '+$case.Name)}
 foreach($line in $lines){$commands.Add($line)}
 # Loading catches instance-port warnings which plain vlog cannot diagnose.
 $load=@(Get-Content -LiteralPath (Join-Path $candidate ($case.Name+'.do')) | Where-Object {$_ -match '^vsim '})
 if($load.Count -ne 1){throw ('Unexpected load script: '+$case.Name)}
 $commands.Add($load[0])
 $commands.Add('quit -sim')
}
$commands.Add('puts "COMPILE_PREFLIGHT_PASS"')
$commands.Add('quit -f -code 0')
$script=Join-Path $worker 'compile_all.do'
$log=Join-Path $worker 'compile_all.log'
[System.IO.File]::WriteAllLines($script,$commands,[System.Text.UTF8Encoding]::new($false))
$exe=(Get-Command vsim.exe -ErrorAction Stop).Source
Push-Location -LiteralPath $worker
try {& $exe -c -do $script *> $log;$code=$LASTEXITCODE} finally {Pop-Location}
$content=Get-Content -LiteralPath $log -Raw
if($code -ne 0 -or $content -match '\*\* Error|\*\* Fatal|\*\* Warning' -or $content -notmatch 'COMPILE_PREFLIGHT_PASS'){
 throw ('Compile preflight failed: '+$log)
}
$null=Assert-ReproductionInputs -Root $OutputRoot -ExpectedDigest $binding.digest
Write-Output ('COMPILE_PREFLIGHT_PASS tests='+@($cases.PSObject.Properties).Count+' simulation_qualified=false')
