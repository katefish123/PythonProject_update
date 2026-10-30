$ErrorActionPreference = 'Stop'
$outputRoot = Join-Path $PSScriptRoot 'results'
$cases = Get-Content -LiteralPath (Join-Path $outputRoot 'simulation_cases.json') -Raw | ConvertFrom-Json
$evidence = [ordered]@{}
Push-Location -LiteralPath $outputRoot
try {
    foreach ($case in $cases.PSObject.Properties) {
        $name = $case.Name
        $log = Join-Path $outputRoot ($name + '.run.log')
        & 'C:\modeltech64_2020.4\win64\vsim.exe' -c -do ($name + '.do') *> $log
        $testExit = $LASTEXITCODE
        $testText = Get-Content -LiteralPath $log -Raw
        $marker = $case.Value[2]
        if ($testExit -ne 0 -or $testText -notmatch [regex]::Escape($marker) -or $testText -match 'TEST_FAIL|\*\* Error|\*\* Warning') {
            throw "Required HDMI test did not pass: $name. Log: $log"
        }
        $evidence[$name] = [ordered]@{passed=$true;exit_code=$testExit;log=$log;log_sha256=(Get-FileHash -LiteralPath $log -Algorithm SHA256).Hash.ToLowerInvariant()}
        Write-Output "Passed: $name"
    }
    [ordered]@{utc=[DateTime]::UtcNow.ToString('o');tests=$evidence;hardware_accepted=$false} | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $outputRoot 'simulation_qualification.json') -Encoding utf8
} finally {
    Pop-Location
}
