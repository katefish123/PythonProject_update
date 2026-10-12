$ErrorActionPreference = 'Stop'
$previewRoot = $PSScriptRoot
$resultsRoot = Join-Path $previewRoot 'results'
$pythonExe = 'C:\Users\夏菲\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$modelBin = 'C:\modeltech64_2020.4\win64'
& $pythonExe (Join-Path $previewRoot 'prepare.py')
if ($LASTEXITCODE -ne 0) { throw 'Preview preparation failed' }
Push-Location -LiteralPath $resultsRoot
try {
    if (-not (Test-Path -LiteralPath 'modelsim.ini')) {
        & (Join-Path $modelBin 'vmap.exe') -c *> 'create_local_ini.log'
        if ($LASTEXITCODE -ne 0) { throw 'Local simulation mapping failed' }
    }
    $tests = [ordered]@{
        tb_hdmi_bram_probe = 'PASS_BRAM_TWO_CLOCKS_TWO_BANKS'
        tb_hdmi_bram_stale = 'PASS_BRAM_STALE_TIMEOUT_AND_RECOVERY'
        tb_camera_live_bram = 'PASS_RAW_CAMERA_FULL_1080P_FRAME'
    }
    $completed = [ordered]@{}
    foreach ($test in $tests.Keys) {
        & (Join-Path $modelBin 'vsim.exe') -modelsimini (Join-Path $resultsRoot 'modelsim.ini') -c -do "$test.do" *> "$test.run.log"
        $testExit = $LASTEXITCODE
        $testLog = Get-Content -LiteralPath "$test.run.log" -Raw
        if ($testExit -ne 0 -or $testLog -match 'FAIL_|\*\* Error' -or $testLog -notmatch $tests[$test]) {
            throw "Camera preview test failed: $test"
        }
        $completed[$test] = [ordered]@{exit_code=$testExit;pass_message=$tests[$test]}
        Write-Output "PASS: $($tests[$test])"
    }
    [ordered]@{qualified_at_utc=[DateTime]::UtcNow.ToString('o');tests=$completed;hardware_accepted=$false} |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath 'simulation_qualification.json' -Encoding utf8
} finally { Pop-Location }
