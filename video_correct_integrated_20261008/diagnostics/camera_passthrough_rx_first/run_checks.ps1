$ErrorActionPreference = 'Stop'
$diagnosticRoot = $PSScriptRoot
$resultsRoot = Join-Path $diagnosticRoot 'results'
$pythonExe = 'C:\Users\夏菲\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$modelBin = 'C:\modeltech64_2020.4\win64'
& $pythonExe (Join-Path $diagnosticRoot 'prepare_rx_first.py')
if ($LASTEXITCODE -ne 0) { throw 'RX-first simulation preparation failed' }
Push-Location -LiteralPath $resultsRoot
try {
    # Every test uses a workspace-local mapping; never write the installed INI.
    if (-not (Test-Path -LiteralPath (Join-Path $resultsRoot 'modelsim.ini'))) {
        & (Join-Path $modelBin 'vmap.exe') -c *> 'create_local_ini.log'
        if ($LASTEXITCODE -ne 0) { throw 'Failed to create local modelsim.ini' }
    }
    $env:RX_FIRST_MISSING_VS = '0'
    $env:RX_FIRST_H_FRONT = '88'
    & (Join-Path $modelBin 'vsim.exe') -modelsimini (Join-Path $resultsRoot 'modelsim.ini') -c -do 'run_pixels.do' *> 'pixels_normal_run.log'
    $normalExit = $LASTEXITCODE
    $normalLog = Get-Content -LiteralPath 'pixels_normal_run.log' -Raw
    if ($normalExit -ne 0 -or $normalLog -match 'FAIL_NATIVE_|\*\* Error' -or $normalLog -notmatch 'PASS_NATIVE_ALL_PIXELS') {
        throw 'Normal 1080p pixel simulation failed'
    }
    Write-Output 'PASS: two complete 1080p frames, normal VS'
    $env:RX_FIRST_MISSING_VS = '1'
    $env:RX_FIRST_H_FRONT = '90'
    & (Join-Path $modelBin 'vsim.exe') -modelsimini (Join-Path $resultsRoot 'modelsim.ini') -c -do 'run_pixels.do' *> 'pixels_missing_vs_run.log'
    $missingExit = $LASTEXITCODE
    $missingLog = Get-Content -LiteralPath 'pixels_missing_vs_run.log' -Raw
    if ($missingExit -ne 0 -or $missingLog -match 'FAIL_NATIVE_|\*\* Error' -or $missingLog -notmatch 'PASS_NATIVE_ALL_PIXELS') {
        throw 'Missing-VS recovery pixel simulation failed'
    }
    Write-Output 'PASS: two complete 1080p frames, missing VS and H_FRONT=90'
    & (Join-Path $modelBin 'vsim.exe') -modelsimini (Join-Path $resultsRoot 'modelsim.ini') -c -do 'run_config.do' *> 'config_run_verified.log'
    $configExit = $LASTEXITCODE
    $configLog = Get-Content -LiteralPath 'config_run_verified.log' -Raw
    $expectedPasses = @('TEST_PASS_CONFIG','TEST_PASS_OPEN_DRAIN','TEST_PASS_BOOTSTRAP_NACK_RECOVERY','TEST_PASS_POSTPROBE_NACK_FATAL','TEST_PASS_NO_DEVICE')
    if ($configExit -ne 0 -or $configLog -match 'TEST_FAIL|\*\* Error') { throw 'RX-first I2C simulation failed' }
    foreach ($expected in $expectedPasses) { if ($configLog -notmatch $expected) { throw "Missing I2C test result: $expected" } }
    Write-Output 'PASS: RX-first real I2C controller normal/retry/fatal/missing-device cases'
    $qualification = [ordered]@{
        qualified_at_utc = [DateTime]::UtcNow.ToString('o')
        normal_two_frames_passed = $true
        missing_vs_two_frames_passed = $true
        rx_first_i2c_passed = $true
        normal_exit_code = $normalExit
        missing_vs_exit_code = $missingExit
        i2c_exit_code = $configExit
    }
    $qualification | ConvertTo-Json | Set-Content -LiteralPath 'simulation_qualification.json' -Encoding utf8
} finally {
    Remove-Item Env:\RX_FIRST_MISSING_VS -ErrorAction SilentlyContinue
    Remove-Item Env:\RX_FIRST_H_FRONT -ErrorAction SilentlyContinue
    Pop-Location
}
