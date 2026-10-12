param([string]$Root=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path)
$ErrorActionPreference='Stop'
$sim = Join-Path $PSScriptRoot 'work'
if(Test-Path -LiteralPath $sim){Remove-Item -LiteralPath $sim -Recurse -Force}
New-Item -ItemType Directory -Path $sim | Out-Null
Push-Location $Root
try {
  vlib $sim | Out-Null
  vmap work $sim | Out-Null
  vlog -sv -work work diagnostics/internal_fixture/internal_fixture_video.v diagnostics/internal_fixture/sim/tb_internal_fixture_video.sv
  if($LASTEXITCODE -ne 0){throw 'vlog failed'}
  $log=Join-Path $PSScriptRoot 'internal_fixture_sim.log'
  vsim -c work.tb_internal_fixture_video -do "run -all; quit -f" | Tee-Object -FilePath $log
  if($LASTEXITCODE -ne 0){throw 'vsim failed'}
  $content=Get-Content -Raw $log
  if($content -notmatch 'test_passed=1' -or $content -notmatch 'FIXTURE_TB_CHECKED_PIXELS=691200 ROWS=480') {throw 'simulation did not report the explicit pass sentinel and full pixel coverage'}
} finally { Pop-Location }

