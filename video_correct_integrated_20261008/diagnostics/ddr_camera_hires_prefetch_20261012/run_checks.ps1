$ErrorActionPreference = 'Stop'
$outputRoot = Join-Path $PSScriptRoot 'results'
$pythonExe = 'C:\Users\夏菲\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$modelBin = 'C:\modeltech64_2020.4\win64'
foreach ($prepare in @('prepare.py','prepare_fixture.py','prepare_checks.py')) {
    & $pythonExe -X utf8 (Join-Path $PSScriptRoot $prepare)
    if ($LASTEXITCODE -ne 0) { throw "Preparation failed: $prepare" }
}
Push-Location -LiteralPath $outputRoot
try {
    if (-not (Test-Path -LiteralPath 'modelsim.ini')) {
        & (Join-Path $modelBin 'vmap.exe') -c *> 'create_local_ini.log'
        if ($LASTEXITCODE -ne 0) { throw 'Local simulation mapping failed' }
    }
    $tests = Get-Content -LiteralPath 'simulation_cases.json' -Raw | ConvertFrom-Json
    $completed = [ordered]@{}
    foreach ($case in $tests.PSObject.Properties) {
        $name=$case.Name
        & (Join-Path $modelBin 'vsim.exe') -modelsimini (Join-Path $outputRoot 'modelsim.ini') -c -do "$name.do" *> "$name.run.log"
        $testExit=$LASTEXITCODE
        $path=Join-Path $outputRoot "$name.run.log"
        $log=Get-Content -LiteralPath $path -Raw
        if ($testExit -ne 0 -or $log -match 'FAIL_|\*\* Error|\*\* Fatal|\*\* Warning' -or $log -notmatch $case.Value -or $log -notmatch 'VERIFIED_PASS_BIT=1') {
            throw "High-resolution regression failed: $name. Log: $path"
        }
        $completed[$name]=[ordered]@{passed=$true;exit_code=$testExit;pass_message=$case.Value;log=$path;log_sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
        Write-Output "PASS: $($case.Value)"
    }
    [ordered]@{qualified_at_utc=[DateTime]::UtcNow.ToString('o');tests=$completed;hardware_accepted=$false} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath 'simulation_qualification.json' -Encoding utf8
} finally { Pop-Location }
