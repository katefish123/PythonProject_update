$ErrorActionPreference='Stop'
$outputRoot=Join-Path $PSScriptRoot 'results'
$pythonExe='C:\Users\夏菲\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$modelBin='C:\modeltech64_2020.4\win64'
foreach ($prepare in @('prepare_engine.py','prepare_checks.py','prepare_display_check.py')) {
    & $pythonExe -X utf8 (Join-Path $PSScriptRoot $prepare)
    if ($LASTEXITCODE -ne 0) { throw "Preparation failed: $prepare" }
}
Push-Location -LiteralPath $outputRoot
try {
    if (-not (Test-Path -LiteralPath 'modelsim.ini')) {
        & (Join-Path $modelBin 'vmap.exe') -c *> 'create_local_ini.log'
        if ($LASTEXITCODE -ne 0) { throw 'Local mapping failed' }
    }
    $cases=Get-Content -LiteralPath 'simulation_cases.json' -Raw | ConvertFrom-Json
    $completed=[ordered]@{}
    foreach ($case in $cases.PSObject.Properties) {
        $name=$case.Name
        & (Join-Path $modelBin 'vsim.exe') -modelsimini (Join-Path $outputRoot 'modelsim.ini') -c -do "$name.do" *> "$name.run.log"
        $testExit=$LASTEXITCODE
        $path=Join-Path $outputRoot "$name.run.log"
        $log=Get-Content -LiteralPath $path -Raw
        if ($testExit -ne 0 -or $log -match 'FAIL_|\*\* Error|\*\* Fatal|\*\* Warning' -or $log -notmatch $case.Value) { throw "Prototype check failed: $name. Log: $path" }
        $completed[$name]=[ordered]@{passed=$true;log=$path;log_sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
        Write-Output "PASS: $($case.Value)"
    }
    [ordered]@{recorded_at_utc=[DateTime]::UtcNow.ToString('o');unit_checks_passed=$true;display_engine_integration_passed=$true;physical_DDR_latency_measured=$false;tests=$completed;qualified_for_board=$false;programmed=$false} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath 'unit_qualification.json' -Encoding utf8
} finally { Pop-Location }
