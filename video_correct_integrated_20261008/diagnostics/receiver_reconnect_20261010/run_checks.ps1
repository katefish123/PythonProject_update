$ErrorActionPreference = 'Stop'
$reconnectRoot = $PSScriptRoot
$resultsRoot = Join-Path $reconnectRoot 'results'
$pythonExe = 'C:\Users\夏菲\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$modelBin = 'C:\modeltech64_2020.4\win64'
& $pythonExe (Join-Path $reconnectRoot 'prepare.py')
if ($LASTEXITCODE -ne 0) { throw 'Reconnect preparation failed' }
Push-Location -LiteralPath $resultsRoot
try {
    if (-not (Test-Path -LiteralPath 'modelsim.ini')) {
        & (Join-Path $modelBin 'vmap.exe') -c *> 'create_local_ini.log'
        if ($LASTEXITCODE -ne 0) { throw 'Local simulation mapping failed' }
    }
    & (Join-Path $modelBin 'vsim.exe') -modelsimini (Join-Path $resultsRoot 'modelsim.ini') -c -do baseline.do *> baseline.run.log
    $baselineExit = $LASTEXITCODE
    $baselineLog = Get-Content -LiteralPath baseline.run.log -Raw
    if ($baselineExit -eq 0 -or $baselineLog -notmatch 'TEST_FAIL_RECONNECT source relock did not produce exactly one receiver setup' -or $baselineLog -match '\*\* Error') {
        throw 'The predicted baseline reconnect failure was not reproduced cleanly'
    }
    Write-Output 'REPRODUCED: current receiver initializes status 03 but misses status 03 relock'
    $qualified = [ordered]@{}
    foreach ($test in @('fixed_hdmi','fixed_dvi','config_tx_first','config_rx_first')) {
        & (Join-Path $modelBin 'vsim.exe') -modelsimini (Join-Path $resultsRoot 'modelsim.ini') -c -do "$test.do" *> "$test.run.log"
        $testExit = $LASTEXITCODE
        $testLog = Get-Content -LiteralPath "$test.run.log" -Raw
        if ($testExit -ne 0 -or $testLog -match 'TEST_FAIL|\*\* Error') { throw "Receiver regression failed: $test" }
        if ($test.StartsWith('fixed')) {
            if ($testLog -notmatch 'TEST_PASS_TWO_RECONNECTS_WITHOUT_RESET') { throw "Missing reconnect completion: $test" }
        } else {
            foreach ($pass in @('TEST_PASS_CONFIG','TEST_PASS_OPEN_DRAIN','TEST_PASS_BOOTSTRAP_NACK_RECOVERY','TEST_PASS_POSTPROBE_NACK_FATAL','TEST_PASS_NO_DEVICE')) {
                if ($testLog -notmatch $pass) { throw "Missing configuration test: $test / $pass" }
            }
        }
        $qualified[$test]=[ordered]@{exit_code=$testExit;passed=$true}
        Write-Output "PASS: $test"
    }
    [ordered]@{utc=[DateTime]::UtcNow.ToString('o');baseline_failure_reproduced=$true;
        tests=$qualified;hardware_programmed=$false} | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath simulation_qualification.json -Encoding utf8
} finally { Pop-Location }
