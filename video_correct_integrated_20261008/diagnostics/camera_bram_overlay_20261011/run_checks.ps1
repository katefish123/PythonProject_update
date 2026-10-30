$ErrorActionPreference = 'Stop'
$outputRoot = Join-Path $PSScriptRoot 'results'
$pythonExe = 'C:\Users\夏菲\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$modelBin = 'C:\modeltech64_2020.4\win64'
& $pythonExe -X utf8 (Join-Path $PSScriptRoot 'prepare.py')
if ($LASTEXITCODE -ne 0) { throw 'Overlay preparation failed' }
Push-Location -LiteralPath $outputRoot
try {
    if (-not (Test-Path -LiteralPath 'modelsim.ini')) {
        & (Join-Path $modelBin 'vmap.exe') -c *> 'create_local_ini.log'
        if ($LASTEXITCODE -ne 0) { throw 'Local simulation mapping failed' }
    }
    $tests = [ordered]@{
        tb_hdmi_bram_probe = 'PASS_BRAM_TWO_CLOCKS_TWO_BANKS'
        tb_hdmi_bram_stale = 'PASS_BRAM_STALE_TIMEOUT_AND_RECOVERY'
        tb_camera_bram_overlay = 'PASS_LIVE_CAMERA_STATUS_OVERLAY_FULL_1080P'
    }
    $completed = [ordered]@{}
    foreach ($test in $tests.Keys) {
        & (Join-Path $modelBin 'vsim.exe') -modelsimini (Join-Path $outputRoot 'modelsim.ini') -c -do "$test.do" *> "$test.run.log"
        $testExit = $LASTEXITCODE
        $testPath = Join-Path $outputRoot "$test.run.log"
        $testLog = Get-Content -LiteralPath $testPath -Raw
        if ($testExit -ne 0 -or $testLog -match 'FAIL_|\*\* Error|\*\* Warning' -or $testLog -notmatch $tests[$test]) {
            throw "Live overlay test failed: $test"
        }
        $completed[$test] = [ordered]@{passed=$true;exit_code=$testExit;pass_message=$tests[$test];log=$testPath;log_sha256=(Get-FileHash -LiteralPath $testPath -Algorithm SHA256).Hash.ToLowerInvariant()}
        Write-Output "PASS: $($tests[$test])"
    }
    [ordered]@{qualified_at_utc=[DateTime]::UtcNow.ToString('o');tests=$completed;hardware_accepted=$false} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath 'simulation_qualification.json' -Encoding utf8
} finally { Pop-Location }
