$ErrorActionPreference = 'Stop'
$pollingRoot = $PSScriptRoot
$pollingResults = Join-Path $pollingRoot 'results'
$pollingPython = 'C:\Users\夏菲\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$pollingModel = 'C:\modeltech64_2020.4\win64'
& $pollingPython (Join-Path $pollingRoot 'prepare.py')
if ($LASTEXITCODE -ne 0) { throw 'RX-first polling preparation failed' }
Push-Location -LiteralPath $pollingResults
try {
    if (-not (Test-Path -LiteralPath 'modelsim.ini')) {
        & (Join-Path $pollingModel 'vmap.exe') -c *> 'create_local_ini.log'
        if ($LASTEXITCODE -ne 0) { throw 'Local polling ModelSim mapping failed' }
    }
    & (Join-Path $pollingModel 'vsim.exe') -modelsimini 'modelsim.ini' -c -do 'baseline_polling.do' *> 'baseline_polling.run.log'
    $pollingBaselineExit = $LASTEXITCODE
    $pollingBaselineLog = Get-Content -LiteralPath 'baseline_polling.run.log' -Raw
    if ($pollingBaselineExit -eq 0 -or $pollingBaselineLog -notmatch 'TEST_FAIL_RECONNECT receiver polling stopped after TX initialization' -or $pollingBaselineLog -match '\*\* Error') {
        throw 'Expected RX-first polling failure not reproduced cleanly'
    }
    Write-Output 'REPRODUCED: integrated RX-first configuration stops receiver polling after TX initialization'
    $pollingTests = [ordered]@{
        fixed_rx_reconnect = @('TEST_PASS_TWO_RECONNECTS_WITHOUT_RESET')
        fixed_rx_dvi = @('TEST_PASS_TWO_RECONNECTS_WITHOUT_RESET')
        fixed_tx_reconnect = @('TEST_PASS_TWO_RECONNECTS_WITHOUT_RESET')
        config_rx = @('TEST_PASS_CONFIG','TEST_PASS_OPEN_DRAIN','TEST_PASS_BOOTSTRAP_NACK_RECOVERY','TEST_PASS_POSTPROBE_NACK_FATAL','TEST_PASS_NO_DEVICE')
        config_tx = @('TEST_PASS_CONFIG','TEST_PASS_OPEN_DRAIN','TEST_PASS_BOOTSTRAP_NACK_RECOVERY','TEST_PASS_POSTPROBE_NACK_FATAL','TEST_PASS_NO_DEVICE')
        pixels = @('PASS_NATIVE_ALL_PIXELS')
        pixels_missing_vs = @('PASS_NATIVE_ALL_PIXELS')
    }
    $pollingPassed = [ordered]@{}
    foreach ($pollingTest in $pollingTests.Keys) {
        & (Join-Path $pollingModel 'vsim.exe') -modelsimini 'modelsim.ini' -c -do "$pollingTest.do" *> "$pollingTest.run.log"
        $pollingExit = $LASTEXITCODE
        $pollingLog = Get-Content -LiteralPath "$pollingTest.run.log" -Raw
        if ($pollingExit -ne 0 -or $pollingLog -match 'FAIL_|TEST_FAIL|\*\* Error' -or $pollingLog -notmatch 'Errors: 0, Warnings: 0') {
            throw "Polling test failed: $pollingTest"
        }
        foreach ($pollingToken in $pollingTests[$pollingTest]) {
            if ($pollingLog -notmatch [regex]::Escape($pollingToken)) { throw "Missing completion: $pollingTest / $pollingToken" }
        }
        $pollingPassed[$pollingTest] = [ordered]@{passed=$true;exit_code=$pollingExit;completion=$pollingTests[$pollingTest]}
        Write-Output "PASS: $pollingTest"
    }
    [ordered]@{utc=[DateTime]::UtcNow.ToString('o');baseline_polling_failure_reproduced=$true;tests=$pollingPassed;hardware_accepted=$false} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath 'simulation_qualification.json' -Encoding utf8
} finally { Pop-Location }
