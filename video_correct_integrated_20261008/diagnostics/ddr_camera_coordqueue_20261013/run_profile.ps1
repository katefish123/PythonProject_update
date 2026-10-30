$ErrorActionPreference='Stop'
$outputRoot=Join-Path $PSScriptRoot 'results'
$modelBin='C:\modeltech64_2020.4\win64'
Push-Location -LiteralPath $outputRoot
try {
    if (-not (Test-Path -LiteralPath 'modelsim.ini')) {
        & (Join-Path $modelBin 'vmap.exe') -c *> 'create_local_ini.log'
        if ($LASTEXITCODE -ne 0) { throw 'Profile local mapping failed' }
    }
    & (Join-Path $modelBin 'vsim.exe') -modelsimini (Join-Path $outputRoot 'modelsim.ini') -c -do 'tb_frame_profile.do' *> 'tb_frame_profile.run.log'
    $exit=$LASTEXITCODE
    $log=Get-Content -LiteralPath 'tb_frame_profile.run.log' -Raw
    if ($exit -ne 0 -or $log -match '\*\* (Warning|Error|Fatal)|FAIL_' -or $log -notmatch 'DDR_FULL_FRAME_PASS' -or $log -notmatch 'VERIFIED_PASS_BIT=1') { throw 'Baseline profile/golden check failed' }
    Write-Output 'Baseline stage profile and exact native RGB golden passed.'
} finally { Pop-Location }
