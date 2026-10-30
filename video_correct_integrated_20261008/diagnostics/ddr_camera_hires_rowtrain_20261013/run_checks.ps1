param([string[]]$Cases=@(),[switch]$ResumeVerified)
$ErrorActionPreference='Stop'
$outputRoot=Join-Path $PSScriptRoot 'results'
$modelBin='C:\modeltech64_2020.4\win64'
Push-Location -LiteralPath $outputRoot
try {
    if (-not (Test-Path -LiteralPath 'modelsim.ini')) {
        & (Join-Path $modelBin 'vmap.exe') -c *> 'create_local_ini.log'
        if ($LASTEXITCODE -ne 0) { throw 'Local simulation mapping failed' }
    }
    $tests=Get-Content -LiteralPath 'simulation_cases.json' -Raw | ConvertFrom-Json
    $completed=[ordered]@{}
    $saved=$null
    if ($ResumeVerified) {
        $saved=Get-Content -LiteralPath 'focused_qualification.json' -Raw | ConvertFrom-Json
    }
    foreach ($case in $tests.PSObject.Properties) {
        $name=$case.Name
        if ($Cases.Count -gt 0 -and $name -notin $Cases) { continue }
        $prior=if ($saved) { $saved.tests.PSObject.Properties[$name] } else { $null }
        if ($prior) {
            $p=$prior.Value
            $log=Get-Content -LiteralPath $p.log -Raw
            if (-not $p.passed -or (Get-FileHash -LiteralPath $p.log -Algorithm SHA256).Hash.ToLowerInvariant() -ne $p.log_sha256 -or
                $log -match 'FAIL_|\*\* Error|\*\* Fatal|\*\* Warning' -or $log -notmatch $case.Value -or $log -notmatch 'VERIFIED_PASS_BIT=1') {
                throw "Saved check changed: $name"
            }
            foreach ($inputFile in @('ddr_result_display.v','ddr_word_engine.v','tb_hires_read_ahead_display.sv',"$name.do")) {
                if ((Get-Item -LiteralPath $inputFile).LastWriteTimeUtc -gt (Get-Item -LiteralPath $p.log).LastWriteTimeUtc) {
                    throw "Check input changed after saved test: $name / $inputFile"
                }
            }
            $completed[$name]=$p
            Write-Output "RETAINED VERIFIED: $name"
            continue
        }
        & (Join-Path $modelBin 'vsim.exe') -modelsimini (Join-Path $outputRoot 'modelsim.ini') -c -do "$name.do" *> "$name.run.log"
        $testExit=$LASTEXITCODE
        $path=Join-Path $outputRoot "$name.run.log"
        $log=Get-Content -LiteralPath $path -Raw
        if ($testExit -ne 0 -or $log -match 'FAIL_|\*\* Error|\*\* Fatal|\*\* Warning' -or $log -notmatch $case.Value -or $log -notmatch 'VERIFIED_PASS_BIT=1') {
            throw "Row-train regression failed: $name. Log: $path"
        }
        $completed[$name]=[ordered]@{passed=$true;exit_code=$testExit;pass_message=$case.Value;log=$path;log_sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
        Write-Output "PASS: $name"
    }
    $recordName=if ($Cases.Count -gt 0) { 'focused_qualification.json' } else { 'simulation_qualification.json' }
    [ordered]@{qualified_at_utc=[DateTime]::UtcNow.ToString('o');tests=$completed;hardware_accepted=$false} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $recordName -Encoding utf8
} finally { Pop-Location }
