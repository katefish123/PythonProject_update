$ErrorActionPreference = 'Stop'
$nativeRoot = $PSScriptRoot
$nativeResults = Join-Path $nativeRoot 'results'
$nativePython = 'C:\Users\夏菲\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$nativeModel = 'C:\modeltech64_2020.4\win64'
& $nativePython (Join-Path $nativeRoot 'prepare.py')
if ($LASTEXITCODE -ne 0) { throw 'Native candidate preparation failed' }
Push-Location -LiteralPath $nativeResults
try {
    if (-not (Test-Path -LiteralPath 'modelsim.ini')) {
        & (Join-Path $nativeModel 'vmap.exe') -c *> 'create_local_ini.log'
        if ($LASTEXITCODE -ne 0) { throw 'Local ModelSim mapping failed' }
    }
    $nativeTests = [ordered]@{
        pixels_normal = @('PASS_NATIVE_ALL_PIXELS')
        pixels_missing_vs = @('PASS_NATIVE_ALL_PIXELS')
        real_config = @('TEST_PASS_CONFIG','TEST_PASS_OPEN_DRAIN','TEST_PASS_BOOTSTRAP_NACK_RECOVERY','TEST_PASS_POSTPROBE_NACK_FATAL','TEST_PASS_NO_DEVICE')
        real_reconnect = @('TEST_PASS_INITIAL_LOCK','TEST_PASS_NO_SIGNAL_NO_WRITES','TEST_PASS_RELOCK','TEST_PASS_LOCKED_MODE_BIT_CHANGE_NO_WRITES','TEST_PASS_TWO_RECONNECTS_WITHOUT_RESET')
    }
    $nativePassed = [ordered]@{}
    foreach ($nativeTest in $nativeTests.Keys) {
        & (Join-Path $nativeModel 'vsim.exe') -modelsimini (Join-Path $nativeResults 'modelsim.ini') -c -do "$nativeTest.do" *> "$nativeTest.run.log"
        $nativeExit = $LASTEXITCODE
        $nativeLog = Get-Content -LiteralPath "$nativeTest.run.log" -Raw
        if ($nativeExit -ne 0 -or $nativeLog -match 'FAIL_|TEST_FAIL|\*\* Error' -or $nativeLog -notmatch 'Errors: 0, Warnings: 0') {
            throw "Native test failed: $nativeTest"
        }
        foreach ($nativeToken in $nativeTests[$nativeTest]) {
            if ($nativeLog -notmatch [regex]::Escape($nativeToken)) { throw "Missing completion: $nativeTest / $nativeToken" }
        }
        $nativePassed[$nativeTest] = [ordered]@{passed=$true;exit_code=$nativeExit;completion=$nativeTests[$nativeTest]}
        Write-Output "PASS: $nativeTest"
    }
    [ordered]@{utc=[DateTime]::UtcNow.ToString('o');tests=$nativePassed;hardware_accepted=$false} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath 'simulation_qualification.json' -Encoding utf8
} finally { Pop-Location }
